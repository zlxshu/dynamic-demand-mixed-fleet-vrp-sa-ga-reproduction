function report = enforce_section_spec(phase, sectionName, fn, varargin)
% 修改日志
% - v1 2026-01-21: 新增 section 规范检查器；在 run_all 中 pre/post 强制校验，避免未来新增 section 漏掉统一管线约束。
%
% 设计目标（硬约束）：
% - section 必须以 ctx 为唯一真源（禁止在 section 内调用 get_config/opt27_constants/paper_constants）。
% - section 必须使用 output_paths 统一输出目录；产物路径必须落在 outputs/<section>/ 下。
% - 如声明为 sensitivity（out.meta.features 含 'sensitivity'），必须同时产出 paper+diag 两版图。

    if nargin < 1, phase = 'pre'; end
    if nargin < 2, sectionName = ''; end
    if nargin < 3, fn = []; end

    report = struct();
    report.phase = char(string(phase));
    report.sectionName = char(string(sectionName));
    report.warnings = {};

    ph = lower(strtrim(char(string(phase))));
    switch ph
        case 'pre'
            precheck_(sectionName, fn);
        case 'post'
            if numel(varargin) < 2
                error('enforce_section_spec:missingArgs', 'post 检查需要 out 与 paths');
            end
            out = varargin{1};
            paths = varargin{2};
            postcheck_(sectionName, out, paths);
        otherwise
            error('enforce_section_spec:badPhase', '未知 phase=%s（仅支持 pre/post）', ph);
    end
end

% ===================== pre =====================
function precheck_(sectionName, fn)
if isempty(fn) || ~isa(fn, 'function_handle')
    error('enforce_section_spec:badFn', 'section 未注册有效函数句柄：%s', sectionName);
end

% 必须至少接收一个入参 ctx（允许 varargin）
try
    ni = nargin(fn);
    if ~(ni == 1 || ni < 0 || ni > 1)
        error('enforce_section_spec:nargin', 'section 函数入参不符合约定（期望 1 或 varargin）：%s (nargin=%d)', sectionName, ni);
    end
catch
end

% 源码静态扫描（防止未来 AI 漏写）
fnName = func2str(fn);
srcPath = which(fnName);
if isempty(srcPath)
    return;
end
if exist(srcPath, 'file') ~= 2
    return;
end

txt = '';
try
    txt = fileread(srcPath);
catch
    return;
end

deny = { ...
    'get_config(', ...
    'truth_baseline(', ...
    'paper_constants(', ...
    'opt27_constants(' ...
    };
for i = 1:numel(deny)
    if contains(txt, deny{i})
        error('enforce_section_spec:denyCall', 'section(%s) 禁止调用 %s（必须仅从 ctx 取参）：%s', sectionName, deny{i}, srcPath);
    end
end

% 软检查：推荐使用 output_paths/build_signature（不满足先给出明确错误，避免悄悄散落输出）
if ~contains(txt, 'output_paths(')
    error('enforce_section_spec:missingOutputPaths', 'section(%s) 缺少 output_paths(...) 调用（必须统一输出目录）：%s', sectionName, srcPath);
end
if ~contains(txt, 'build_signature(')
    error('enforce_section_spec:missingSignature', 'section(%s) 缺少 build_signature(ctx) 调用（必须生成签名用于追溯/缓存隔离）：%s', sectionName, srcPath);
end
end

% ===================== post =====================
function postcheck_(sectionName, out, paths)
if ~isstruct(out)
    error('enforce_section_spec:badOut', 'section(%s) 输出必须为 struct', sectionName);
end

% meta 必备字段
reqMeta = {'sectionName','runTag','timestamp','paramSig','dataSig','features'};
if ~isfield(out, 'meta') || ~isstruct(out.meta)
    error('enforce_section_spec:missingMeta', 'section(%s) 输出缺少 out.meta', sectionName);
end
for i = 1:numel(reqMeta)
    if ~isfield(out.meta, reqMeta{i})
        error('enforce_section_spec:missingMetaField', 'section(%s) out.meta 缺少字段: %s', sectionName, reqMeta{i});
    end
end
if ~strcmp(char(string(out.meta.sectionName)), sectionName)
    error('enforce_section_spec:metaMismatch', 'section(%s) out.meta.sectionName 不一致: %s', sectionName, char(string(out.meta.sectionName)));
end

% paths 必备
if ~isfield(out, 'paths') || ~isstruct(out.paths) || ~isfield(out.paths,'root')
    error('enforce_section_spec:missingPaths', 'section(%s) 输出缺少 out.paths.root', sectionName);
end

% 所有 artifacts 路径必须落在 outputs/<section>/ 下（允许为空）
if isfield(out,'artifacts') && isstruct(out.artifacts) && ~isempty(fieldnames(out.artifacts))
    fns = fieldnames(out.artifacts);
    for i = 1:numel(fns)
        v = out.artifacts.(fns{i});
        if ~(ischar(v) || isstring(v))
            continue;
        end
        p = char(string(v));
        if isempty(p)
            continue;
        end
        if ~startsWith(normalize_path_(p), normalize_path_(paths.root))
            error('enforce_section_spec:artifactOutside', 'section(%s) 产物路径不在 outputs/%s 下: %s=%s', sectionName, sectionName, fns{i}, p);
        end
    end
end

% sensitivity 双版本强制：声明 features 含 sensitivity 时，必须同时存在 paper+diag png
isSens = false;
if isfield(out.meta,'features')
    try
        feat = out.meta.features;
        if ischar(feat) || isstring(feat)
            feat = cellstr(string(feat));
        end
        if iscell(feat)
            isSens = any(strcmpi(strtrim(string(feat)), "sensitivity"));
        end
    catch
    end
end
if isSens
    if ~isfield(out,'artifacts') || ~isstruct(out.artifacts)
        error('enforce_section_spec:sensMissingArtifacts', 'section(%s) sensitivity 必须输出 out.artifacts（含 paper+diag 图）', sectionName);
    end
    fns = fieldnames(out.artifacts);
    hasPaper = any(contains(lower(fns), 'paper'));
    hasDiag  = any(contains(lower(fns), 'diag'));
    if ~(hasPaper && hasDiag)
        error('enforce_section_spec:sensMissingDual', 'section(%s) sensitivity 必须同时产出 paper+diag 两版图（artifacts 字段缺失）', sectionName);
    end
end
end

function p = normalize_path_(p)
try
    p = char(string(p));
    p = strrep(p, '/', filesep);
    p = strrep(p, '\\', filesep);
    p = char(java.io.File(p).getCanonicalPath());
catch
end
end

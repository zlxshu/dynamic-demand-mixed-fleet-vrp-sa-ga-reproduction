function init = load_initial_plan_from_531_541(ctx, paths541)
% load_initial_plan_from_531_541 - 从 section_531 的落盘结果加载初始方案（Table5.7 真源）
% 修改日志
% - v5 2026-02-11: 修复 macOS 资源分叉文件污染（._*.mat）：加载前过滤隐藏/AppleDouble 文件，并按时间倒序容错尝试，避免单个坏文件导致 541 中断。
% - v1 2026-01-24: 支持从 section_531 的 mats/out__*.mat（签名匹配）加载初始方案；无匹配则自动运行一次 section_531(ctx)。
% - v2 2026-01-24: 自动运行 531 时保存变量名为 out（兼容 run_all），并在本函数内保存/恢复 RNG，避免影响 section_541 的随机序列。
% - v3 2026-01-24: 增加终端提示：明确 541 为获取 Table5.7 可能自动跑一次 531（依赖步骤，不是模式切换）。
% - v4 2026-01-31: 增加 5 车排查日志（debug）。
%
% 约束：
% - 优先读取 section_531 的“签名匹配”缓存输出（run_all 保存的 out.mat）
% - 若无匹配缓存，则自动运行一次 section_531(ctx) 生成初始方案（并将 out 保存到 outputs/section_531/mats 供后续复用）

if nargin < 2 || ~isstruct(paths541) || ~isfield(paths541,'logs')
    paths541 = struct();
end

matsDir = fullfile(ctx.Meta.projectRoot, 'outputs', 'section_531', 'mats');

sig = build_signature(ctx);
runTag = char(string(ctx.Meta.runTag));
runTagSafe = sanitize_(runTag);

out531 = [];
pickPath = '';

% 1) 优先读取“签名匹配”的缓存输出（run_all 保存的 out.mat）
if exist(matsDir, 'dir') == 7
    files = dir(fullfile(matsDir, '*.mat'));
    files = filter_valid_mat_files_541_(files);
    match = [];
    for i = 1:numel(files)
        n = files(i).name;
        if ~contains(n, 'out__section_531__')
            continue;
        end
        if ~contains(n, ['__' runTagSafe '__'])
            continue;
        end
        if ~contains(n, ['__' sig.param.short '__'])
            continue;
        end
        if ~contains(n, ['__' sig.data.short '__'])
            continue;
        end
        match(end+1) = i; %#ok<AGROW>
    end
    if ~isempty(match)
        [~, order] = sort([files(match).datenum], 'descend');
        candIdx = match(order);
        for j = 1:numel(candIdx)
            iPick = candIdx(j);
            candPath = fullfile(matsDir, files(iPick).name);
            s = [];
            okLoad = false;
            try
                s = load(candPath);
                okLoad = true;
            catch ME
                log_append_init_541_(paths541, sprintf('[init] skip unreadable mat: %s | reason=%s', candPath, ME.message));
            end
            if ~okLoad
                continue;
            end
            if isfield(s, 'out') && isfield(s.out,'bestGlobal') && isfield(s.out.bestGlobal,'detail')
                out531 = s.out;
                pickPath = candPath;
                break;
            elseif isfield(s, 'out531') && isfield(s.out531,'bestGlobal') && isfield(s.out531.bestGlobal,'detail')
                out531 = s.out531;
                pickPath = candPath;
                break;
            else
                log_append_init_541_(paths541, sprintf('[init] skip incompatible mat(no out.bestGlobal.detail): %s', candPath));
            end
        end
    end
end
if ~isempty(out531) && ~isempty(pickPath)
    fprintf('[section_541][init] cache hit -> use section_531 result: %s\n', pickPath);
    try
        if isfield(paths541,'logs') && ~isempty(paths541.logs)
            p = fullfile(paths541.logs, 'init_from_531.txt');
            fid = fopen(p, 'a');
            if fid > 0
                c = onCleanup(@() fclose(fid));
                fprintf(fid, '[init] cache hit: %s\n', pickPath);
            end
        end
    catch
    end
end

% 2) 若无匹配缓存：自动跑一次 section_531（在 541 的 RNG 隔离范围内，不污染外部）
if isempty(out531)
    fprintf('[section_541][init] cache miss -> auto run section_531 once for Table5.7 (dependency step, not mode switch)\n');
    fprintf('[section_541][init] expect signature: runTag=%s | paramSig=%s | dataSig=%s\n', runTagSafe, sig.param.short, sig.data.short);
    try
        if isfield(paths541,'logs') && ~isempty(paths541.logs)
            p = fullfile(paths541.logs, 'init_from_531.txt');
            fid = fopen(p, 'a');
            if fid > 0
                c = onCleanup(@() fclose(fid));
                fprintf(fid, '[init] no matching cache found -> auto run section_531 once\n');
                fprintf(fid, '       expect file token: runTag=%s | paramSig=%s | dataSig=%s\n', runTagSafe, sig.param.short, sig.data.short);
            end
        end
    catch
    end

    % 重要：保存/恢复 RNG，避免是否命中 531 缓存导致 541 求解随机序列漂移
    rngStateBefore531 = rng;
    rngCleanup = onCleanup(@() rng(rngStateBefore531));
    out531 = run_section_531(ctx);
    clear rngCleanup;
    fprintf('[section_541][init] section_531 finished -> continue section_541\n');

    % 将 out 保存到 section_531/mats 作为可复用缓存（模拟 run_all 的保存行为）
    try
        p531 = output_paths(ctx.Meta.projectRoot, 'section_531', ctx.Meta.runTag);
        out = out531; %#ok<NASGU>
        outMat = fullfile(p531.mats, artifact_filename('out', 'section_531', ctx.Meta.runTag, sig.param.short, sig.data.short, [ctx.Meta.timestamp '_autoFrom541'], '.mat'));
        save(outMat, 'out');
        pickPath = outMat;
    catch
    end
end

if ~isfield(out531,'bestGlobal') || ~isfield(out531.bestGlobal,'detail')
    error('section_541:bad531Out', 'section_531 output missing bestGlobal.detail');
end

init = struct();
init.sourceMat = pickPath;
init.detail = out531.bestGlobal.detail;
init.cost = out531.bestGlobal.cost;
init.isFeasible = false;
try init.isFeasible = logical(out531.bestGlobal.isFeasible); catch, end

% 车队规模（来自 ctx 真源；不修改）
init.nCV = ctx.P.Fleet.nCV;
init.nEV = ctx.P.Fleet.nEV;

% 记录到 541 自己的 logs（若给了 paths541）
try
    if isfield(paths541,'logs') && ~isempty(paths541.logs)
        p = fullfile(paths541.logs, 'init_from_531.txt');
        fid = fopen(p, 'a');
        if fid > 0
            c = onCleanup(@() fclose(fid));
            fprintf(fid, '[init] pick=%s | cost=%.6f | feasible=%d\n', pickPath, init.cost, double(init.isFeasible));
        end
    end
catch
end
end

function files = filter_valid_mat_files_541_(filesIn)
files = filesIn;
if isempty(files)
    return;
end
keep = false(numel(files), 1);
for i = 1:numel(files)
    name = '';
    isDir = false;
    try
        name = char(string(files(i).name));
        isDir = logical(files(i).isdir);
    catch
    end
    if isDir
        continue;
    end
    if is_hidden_mat_artifact_541_(name)
        continue;
    end
    keep(i) = true;
end
files = files(keep);
end

function tf = is_hidden_mat_artifact_541_(name)
n = char(string(name));
tf = false;
if isempty(n)
    tf = true;
    return;
end
if startsWith(n, '.')
    tf = true;
    return;
end
if startsWith(n, '._')
    tf = true;
    return;
end
end

function log_append_init_541_(paths541, line)
try
    if ~isstruct(paths541) || ~isfield(paths541,'logs') || isempty(paths541.logs)
        return;
    end
    p = fullfile(paths541.logs, 'init_from_531.txt');
    fid = fopen(p, 'a');
    if fid <= 0
        return;
    end
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s\n', char(string(line)));
catch
end
end

function s = sanitize_(s)
s = char(string(s));
s = regexprep(s, '\\s+', '_');
s = regexprep(s, '[\\\\/:\\*\\?\"<>\\|]+', '_');
s = regexprep(s, '__+', '__');
s = regexprep(s, '^_+|_+$', '');
if isempty(s)
    s = 'x';
end
end

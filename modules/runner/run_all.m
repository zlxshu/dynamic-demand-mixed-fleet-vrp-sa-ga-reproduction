function results = run_all(varargin)
% 修改日志
% - v8 2026-02-10: 新增统一“并行检测提示”：每个 section 开跑前打印 SECTIONxxx_PARALLEL_ENABLE/WORKERS/LOG_LEVEL，便于终端快速确认并行开关状态。
% - v7 2026-02-08: enforce_run_modes_env 升级为硬失败（违规即中断），并打印规则报告路径，防止带违规继续运行。
% - v1 2026-01-21: 新增统一执行器 run_all；统一配置入口/签名/审计/输出落盘/section 注册表。
% - v1 2026-01-21: 每个 section 开跑前打印审计表并落盘 outputs/<section>/logs/audit.txt；输出 out 保存到 mats/。
% - v2 2026-01-21: 接入 enforce_section_spec（pre/post 强制校验 future section 规范）；控制台输出中文化（out 已保存）。
% - v3 2026-01-25: 若仅运行 section_541，则默认按 SECTION541_DATA_POLICY 优先使用 data/（通过 get_config PreferInternal=false，避免默认 internal）。
% - v4 2026-02-02: 移除 PreferInternal 覆盖逻辑（内部数据机制已废除）。
% - v5 2026-02-03: 集成 enforce_switch_panel 和 enforce_changelog_sync 检查。
% - v6 2026-02-04: 集成 enforce_run_modes_env，确保 SECTIONxx_* 环境变量仅在 run_modes.m 中设置。

p = inputParser();
p.addParameter('Sections', {}, @(c) iscell(c) || isstring(c));
p.addParameter('RunTag', 'default', @(s) ischar(s) || isstring(s));
p.addParameter('ModeLabel', 'PAPER', @(s) ischar(s) || isstring(s));
p.addParameter('ForceRecompute', false, @(x) islogical(x) && isscalar(x));
p.addParameter('Override', struct(), @(s) isstruct(s));
p.addParameter('AlgoProfile', 'BASELINE', @(s) ischar(s) || isstring(s));
p.parse(varargin{:});
opt = p.Results;

init_modules();

registry = section_registry();
allKeys = sort(keys(registry));

% ===== 规范检查：开关面板和变更日志同步 =====
checkerCfg = struct();
checkerCfg.supportedSections = allKeys;
checkerCfg.runModesPath = get_run_modes_path_();
checkerCfg.strictMode = false;  % 非严格模式：仅警告不中断

try
    % 开关面板检查
    switchResult = enforce_switch_panel(checkerCfg);
    if ~switchResult.passed
        warning('run_all:switchPanelCheck', '开关面板检查未通过，详见上方错误信息');
    end

    % 变更日志同步检查
    changelogResult = enforce_changelog_sync(checkerCfg);
    if ~changelogResult.passed
        warning('run_all:changelogSyncCheck', '变更日志同步检查未通过，详见上方错误信息');
    end
catch ME
    warning('run_all:checkerFailed', '规范检查执行失败：%s', ME.message);
end

% SECTIONxx_* 环境变量集中检查（硬失败）
envResult = enforce_run_modes_env(checkerCfg);
if ~envResult.passed
    error('run_all:runModesEnvCheck', ...
        ['SECTIONxx_* 环境变量使用不规范，已按硬规则中断。' newline ...
        '报告: %s' newline ...
        '%s'], ...
        char(string(getfield_safe_(envResult, 'reportPath', ''))), ...
        char(string(getfield_safe_(envResult, 'fixHint', '检测到后必须修复并同步 CHANGELOG，不允许带违规继续运行。'))));
end
% ===========================================

sections = opt.Sections;
if isempty(sections)
    sections = allKeys;
end
if isstring(sections)
    sections = cellstr(sections);
end
sections = normalize_sections_(sections);

% ctx 真源（同一次 run_all 共享 ctx，确保 531/532 签名一致）
% 注意：内部数据机制已废除（v4 2026-02-02），所有 section 强制使用 xlsx 文件
ctx = get_config('RunTag', opt.RunTag, 'ModeLabel', opt.ModeLabel, 'ForceRecompute', opt.ForceRecompute);
% 算法档位（仅流程增强，不改参数）
try
    ctx.Meta.algoProfile = upper(strtrim(char(string(opt.AlgoProfile))));
catch
    ctx.Meta.algoProfile = 'BASELINE';
end
if ~isempty(fieldnames(opt.Override))
    ctx = apply_override(ctx, opt.Override);
    ctx = assert_config(ctx);
end
sig = build_signature(ctx);

results = struct();

for i = 1:numel(sections)
    sectionName = sections{i};
    if ~isKey(registry, sectionName)
        error('run_all:unknownSection', '未注册 section: %s', sectionName);
    end

    paths = output_paths(ctx.Meta.projectRoot, sectionName, ctx.Meta.runTag);

    % 规范检查（pre）：防止 future section 漏掉统一管线约束
    fn = registry(sectionName);
    enforce_section_spec('pre', sectionName, fn);

    % 统一并行状态提示（所有 section 终端输出可见）
    print_parallel_status_hint_(sectionName);

    % 运行前审计
    auditText = print_audit(ctx, 'SectionName', sectionName, 'ParamSig', sig.param, 'DataSig', sig.data, 'Paths', paths);
    auditFile = fullfile(paths.logs, 'audit.txt');
    append_text_(auditFile, auditText);

    % 运行
    out = fn(ctx);

    % 规范检查（post）：产物位置/元信息/敏感性双版本等
    enforce_section_spec('post', sectionName, fn, out, paths);

    % 统一保存 out
    outMat = fullfile(paths.mats, artifact_filename('out', sectionName, ctx.Meta.runTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.mat'));
    save(outMat, 'out');
    fprintf('[%s] out 已保存：%s\n', sectionName, outMat);

    % 汇总返回（字段名合法化）
    results.(matlab.lang.makeValidName(sectionName)) = out;
end
end

function sections = normalize_sections_(sections)
for i = 1:numel(sections)
    s = char(string(sections{i}));
    if ~startsWith(lower(s), 'section_')
        s = ['section_' s];
    end
    sections{i} = s;
end
end

function append_text_(filePath, text)
ensure_dir(fileparts(filePath));
fid = fopen(filePath, 'a');
if fid < 0
    warning('run_all:auditWriteFailed', '无法写入审计日志: %s', filePath);
    return;
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n\n', text);
end

function runModesPath = get_run_modes_path_()
% 获取 run_modes.m 的完整路径
% 假设 run_all.m 位于 modules/runner/，run_modes.m 位于项目根目录
thisFile = mfilename('fullpath');
runnerDir = fileparts(thisFile);
modulesDir = fileparts(runnerDir);
projectRoot = fileparts(modulesDir);
runModesPath = fullfile(projectRoot, 'run_modes.m');
end

function v = getfield_safe_(s, f, d)
v = d;
try
    if isstruct(s) && isfield(s, f)
        v = s.(f);
    end
catch
    v = d;
end
end

function print_parallel_status_hint_(sectionName)
secTok = regexp(char(string(sectionName)), '^section_(\d+)$', 'tokens', 'once');
if isempty(secTok)
    fprintf('[%s] 并行检测: section 名称不符合 section_xxx 规范，跳过并行开关读取。\n', sectionName);
    return;
end

secId = secTok{1};
keyEnable = sprintf('SECTION%s_PARALLEL_ENABLE', secId);
keyWorkers = sprintf('SECTION%s_PARALLEL_WORKERS', secId);
keyLog = sprintf('SECTION%s_PARALLEL_LOG_LEVEL', secId);

rawEnable = strtrim(char(string(getenv(keyEnable))));
rawWorkers = strtrim(char(string(getenv(keyWorkers))));
rawLog = strtrim(char(string(getenv(keyLog))));

enabled = parse_bool_env_(rawEnable, false);
if isempty(rawWorkers)
    rawWorkers = '0';
end
if isempty(rawLog)
    rawLog = 'detailed';
end

fprintf('[%s] 并行检测: enabled=%d | workers=%s | logLevel=%s | keys={%s,%s,%s}\n', ...
    sectionName, double(enabled), rawWorkers, rawLog, keyEnable, keyWorkers, keyLog);
end

function v = parse_bool_env_(s, def)
v = def;
try
    ss = lower(strtrim(char(string(s))));
    if any(strcmp(ss, {'1','true','on','yes'}))
        v = true;
    elseif any(strcmp(ss, {'0','false','off','no'}))
        v = false;
    end
catch
    v = def;
end
end

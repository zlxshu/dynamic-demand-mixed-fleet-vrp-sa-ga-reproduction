function result = enforce_run_modes_env(cfg)
% 修改日志
% - v3 2026-02-08: 扩展为全量规则检查：除 setenv 越界外，新增 SECTION 读取未声明检查；输出统一报告到 outputs/_policy/logs，并附“必须修复”指令。
% - v2 2026-02-07: 忽略 *_bak_*.m / run_modes_bak_*.m / AppleDouble 临时文件，避免备份文件误触发 SECTIONxx_* 违规告警。
% - v1 2026-02-07: 新增 runner 层环境变量规范检查器，修复 run_all 调用不可见导致的未定义警告。
%
% enforce_run_modes_env - 确保 SECTIONxx_* 开关仅由 run_modes.m 唯一控制
%
% 规则：
% 1) 仅 run_modes.m 允许 setenv('SECTIONxx_*', ...)
% 2) 任意文件读取 SECTIONxx_*（getenv/env_*_or_default_）时，该 key 必须已在 run_modes.m 声明并同步
%
% 输出字段（向后兼容）：
% - passed / violations
% - violationsSetenv / violationsReadUndeclared
% - runModesDeclared / reportPath / fixHint

result = struct();
result.passed = true;
result.violations = {};
result.violationsSetenv = {};
result.violationsReadUndeclared = {};
result.runModesDeclared = {};
result.reportPath = '';
result.fixHint = '检测到后必须修复并同步 CHANGELOG，不允许带违规继续运行。';
result.cacheDirectRefs = {};

try
    if nargin < 1
        cfg = struct();
    end

    runModesPath = resolve_run_modes_path_(cfg);
    if isempty(runModesPath) || exist(runModesPath, 'file') ~= 2
        warning('enforce_run_modes_env:noRunModes', ...
            '未能定位 run_modes.m，跳过 SECTIONxx_* 环境变量检查。');
        return;
    end

    runModesPath = normalize_path_(runModesPath);
    rootDir = fileparts(runModesPath);
    runModesText = fileread(runModesPath);

    declared = parse_declared_section_keys_(runModesText);
    result.runModesDeclared = declared;

    files = dir(fullfile(rootDir, '**', '*.m'));
    setenvViol = {};
    readViol = {};
    cacheRefs = {};

    for i = 1:numel(files)
        if should_skip_file_(files(i).name)
            continue;
        end

        fpath = fullfile(files(i).folder, files(i).name);
        canon = normalize_path_(fpath);
        if strcmpi(canon, runModesPath)
            continue;
        end

        txt = fileread(fpath);
        rel = strrep(canon, [rootDir filesep], '');

        if has_cache_direct_ref_(txt)
            cacheRefs{end+1} = rel; %#ok<AGROW>
        end

        [setenvKeys, readKeys] = scan_section_keys_(txt);

        if ~isempty(setenvKeys)
            setenvViol{end+1} = sprintf('%s | keys=%s', rel, strjoin(setenvKeys, ',')); %#ok<AGROW>
        end

        if ~isempty(readKeys)
            for k = 1:numel(readKeys)
                key = readKeys{k};
                if ~ismember(key, declared)
                    readViol{end+1} = sprintf('%s | key=%s', rel, key); %#ok<AGROW>
                end
            end
        end
    end

    setenvViol = unique(setenvViol, 'stable');
    readViol = unique(readViol, 'stable');
    cacheRefs = unique(cacheRefs, 'stable');

    result.violationsSetenv = setenvViol;
    result.violationsReadUndeclared = readViol;
    result.cacheDirectRefs = cacheRefs;
    result.violations = [setenvViol(:); readViol(:)]';
    result.passed = isempty(setenvViol) && isempty(readViol);

    result.reportPath = write_report_(rootDir, runModesPath, result);

    if ~result.passed
        fprintf('[enforce_run_modes_env] 检测到 SECTIONxx_* 规则违规：\n');
        if ~isempty(setenvViol)
            fprintf('  - setenv 越界: %d 项\n', numel(setenvViol));
        end
        if ~isempty(readViol)
            fprintf('  - 未声明读取: %d 项\n', numel(readViol));
        end
        fprintf('[enforce_run_modes_env] 报告: %s\n', result.reportPath);
        fprintf('[enforce_run_modes_env] %s\n', result.fixHint);
    else
        fprintf('[enforce_run_modes_env] 检查通过：SECTIONxx_* 全量收口于 run_modes.m\n');
        fprintf('[enforce_run_modes_env] 报告: %s\n', result.reportPath);
    end
catch ME
    warning('enforce_run_modes_env:failed', ...
        '执行 enforce_run_modes_env 失败：%s', ME.message);
end

end

function runModesPath = resolve_run_modes_path_(cfg)
runModesPath = '';
try
    if isfield(cfg, 'runModesPath') && ~isempty(cfg.runModesPath)
        runModesPath = char(string(cfg.runModesPath));
        return;
    end
catch
end

try
    rootDir = project_root_dir();
    cand = fullfile(rootDir, 'run_modes.m');
    if exist(cand, 'file') == 2
        runModesPath = cand;
    end
catch
    runModesPath = '';
end
end

function p = normalize_path_(p)
try
    p = char(java.io.File(p).getCanonicalPath());
catch
    p = char(string(p));
end
end

function tf = should_skip_file_(name)
name = char(string(name));
lname = lower(name);
tf = false;

if startsWith(lname, '._')
    tf = true;
    return;
end

if contains(lname, '_bak_') || startsWith(lname, 'run_modes_bak_')
    tf = true;
    return;
end
end

function keys = parse_declared_section_keys_(runModesText)
keys = {};

try
    patDecl = '(?m)^\s*(SECTION\d+_[A-Za-z0-9_]+)\s*=';
    mm1 = regexp(runModesText, patDecl, 'tokens');
    for i = 1:numel(mm1)
        keys{end+1} = upper(strtrim(char(mm1{i}{1}))); %#ok<AGROW>
    end

    lines = regexp(char(string(runModesText)), '\r\n|\n|\r', 'split');
    for i = 1:numel(lines)
        line = strip_comment_(lines{i});
        if isempty(line)
            continue;
        end
        toks = regexp(line, 'setenv\s*\(\s*[''\"](SECTION\d+_[A-Za-z0-9_]+)[''\"]', 'tokens');
        for j = 1:numel(toks)
            keys{end+1} = upper(strtrim(char(toks{j}{1}))); %#ok<AGROW>
        end
    end
catch
end

keys = unique(keys, 'stable');
end

function [setenvKeys, readKeys] = scan_section_keys_(txt)
setenvKeys = {};
readKeys = {};

lines = regexp(char(string(txt)), '\r\n|\n|\r', 'split');
for i = 1:numel(lines)
    line = strip_comment_(lines{i});
    if isempty(line)
        continue;
    end

    s1 = regexp(line, 'setenv\s*\(\s*[''\"](SECTION\d+_[A-Za-z0-9_]+)[''\"]', 'tokens');
    for j = 1:numel(s1)
        setenvKeys{end+1} = upper(strtrim(char(s1{j}{1}))); %#ok<AGROW>
    end

    s2 = regexp(line, 'getenv\s*\(\s*[''\"](SECTION\d+_[A-Za-z0-9_]+)[''\"]', 'tokens');
    for j = 1:numel(s2)
        readKeys{end+1} = upper(strtrim(char(s2{j}{1}))); %#ok<AGROW>
    end

    s3 = regexp(line, 'env_[A-Za-z0-9_]*_or_default_\s*\(\s*[''\"](SECTION\d+_[A-Za-z0-9_]+)[''\"]', 'tokens');
    for j = 1:numel(s3)
        readKeys{end+1} = upper(strtrim(char(s3{j}{1}))); %#ok<AGROW>
    end
end

setenvKeys = unique(setenvKeys, 'stable');
readKeys = unique(readKeys, 'stable');
end

function line = strip_comment_(line)
line = char(string(line));
p = strfind(line, '%');
if ~isempty(p)
    line = line(1:p(1)-1);
end
line = strtrim(line);
end

function tf = has_cache_direct_ref_(txt)
tf = false;
lines = regexp(char(string(txt)), '\r\n|\n|\r', 'split');
for i = 1:numel(lines)
    line = strip_comment_(lines{i});
    if isempty(line)
        continue;
    end
    if ~isempty(regexp(line, '[\''\"]CACHE[\''\"]', 'once'))
        tf = true;
        return;
    end
end
end

function reportPath = write_report_(rootDir, runModesPath, result)
reportPath = '';
try
    outDir = fullfile(rootDir, 'outputs', '_policy', 'logs');
    ensure_dir_local_(outDir);
    ts = datestr(now, 'yyyymmddTHHMMSS');
    reportPath = fullfile(outDir, sprintf('enforce_run_modes_env_report__%s.txt', ts));

    fid = fopen(reportPath, 'w');
    if fid < 0
        reportPath = '';
        return;
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

    fprintf(fid, '[enforce_run_modes_env] report_timestamp=%s\n', ts);
    fprintf(fid, 'run_modes=%s\n', runModesPath);
    fprintf(fid, 'passed=%d\n', double(result.passed));
    fprintf(fid, 'fix_hint=%s\n', result.fixHint);
    fprintf(fid, '\n');

    fprintf(fid, '[run_modes_declared_keys] count=%d\n', numel(result.runModesDeclared));
    for i = 1:numel(result.runModesDeclared)
        fprintf(fid, '  - %s\n', result.runModesDeclared{i});
    end
    fprintf(fid, '\n');

    fprintf(fid, '[violations_setenv] count=%d\n', numel(result.violationsSetenv));
    for i = 1:numel(result.violationsSetenv)
        fprintf(fid, '  - %s\n', result.violationsSetenv{i});
    end
    fprintf(fid, '\n');

    fprintf(fid, '[violations_read_undeclared] count=%d\n', numel(result.violationsReadUndeclared));
    for i = 1:numel(result.violationsReadUndeclared)
        fprintf(fid, '  - %s\n', result.violationsReadUndeclared{i});
    end
    fprintf(fid, '\n');

    fprintf(fid, '[cache_direct_reference_summary] count=%d\n', numel(result.cacheDirectRefs));
    for i = 1:numel(result.cacheDirectRefs)
        fprintf(fid, '  - %s\n', result.cacheDirectRefs{i});
    end
    fprintf(fid, '  note=若存在直连 CACHE，请确认已使用 build_signature + cache_load_best/cache_save 做签名隔离。\n');
    fprintf(fid, '\n');

    fprintf(fid, '[policy]\n');
    fprintf(fid, '检测到后必须修复并同步 CHANGELOG，不允许带违规继续运行。\n');
catch
    reportPath = '';
end
end

function ensure_dir_local_(d)
if isempty(d)
    return;
end
if exist(d, 'dir') ~= 7
    mkdir(d);
end
end

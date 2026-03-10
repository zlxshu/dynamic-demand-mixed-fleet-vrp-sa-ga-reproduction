function result = enforce_run_modes_env(cfg)
% 修改日志
% - v2 2026-02-07: 忽略 *_bak_*.m / run_modes_bak_*.m / AppleDouble 临时文件，避免备份文件误触发 SECTIONxx_* 违规告警。
% - v1 2026-02-07: 新增 SECTIONxx_* 环境变量护栏检查器（仅允许 run_modes.m 设置）。
% enforce_run_modes_env - 确保 SECTIONxx_* 环境变量仅在 run_modes.m 中设置
%
% 用法：
%   result = enforce_run_modes_env(cfg)
%   其中 cfg.runModesPath 为 run_modes.m 的完整路径（可选）。
%
% 行为：
%   - 扫描工程下所有 .m 文件（除 run_modes.m 自身），查找 setenv('SECTION / setenv("SECTION 调用；
%   - 如发现违规文件，将路径记录到 result.violations，并输出警告信息。
%
% 设计：
%   - 不中断运行（由调用方决定是否视为致命错误），但会给出清晰提示；
%   - 仅作为“护栏”，不修改任何文件。

result = struct();
result.passed = true;
result.violations = {};

try
    if nargin < 1
        cfg = struct();
    end
    runModesPath = '';
    if isfield(cfg, 'runModesPath') && ~isempty(cfg.runModesPath)
        runModesPath = char(string(cfg.runModesPath));
    else
        % 回退：尝试通过固定文件名查找
        rootDir = project_root_dir();
        cand = fullfile(rootDir, 'run_modes.m');
        if exist(cand, 'file')
            runModesPath = cand;
        end
    end

    if isempty(runModesPath) || ~exist(runModesPath, 'file')
        warning('enforce_run_modes_env:noRunModes', ...
            '未能定位 run_modes.m，跳过 SECTIONxx_* 环境变量检查。');
        return;
    end

    runModesPath = char(java.io.File(runModesPath).getCanonicalPath());

    rootDir = fileparts(runModesPath);
    files = dir(fullfile(rootDir, '**', '*.m'));

    violations = {};

    for i = 1:numel(files)
        if should_skip_file_(files(i).name)
            continue;
        end
        fpath = fullfile(files(i).folder, files(i).name);
        canon = char(java.io.File(fpath).getCanonicalPath());
        if strcmpi(canon, runModesPath)
            continue; % run_modes.m 内允许 setenv('SECTIONxx_*')
        end
        txt = fileread(fpath);
        if has_section_setenv_call_(txt)
            rel = strrep(canon, [rootDir filesep], '');
            violations{end+1} = rel; %#ok<AGROW>
        end
    end

    if ~isempty(violations)
        result.passed = false;
        result.violations = violations;
        fprintf('[enforce_run_modes_env] 检测到以下文件在 run_modes.m 之外直接调用 setenv(''SECTIONxx_*'')：\n');
        for i = 1:numel(violations)
            fprintf('  - %s\n', violations{i});
        end
        fprintf('请将上述 setenv 调用迁回 run_modes.m 的开关面板或其辅助函数中。\n');
    end
catch ME
    warning('enforce_run_modes_env:failed', ...
        '执行 enforce_run_modes_env 失败：%s', ME.message);
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

function tf = has_section_setenv_call_(txt)
tf = false;
try
    lines = regexp(char(string(txt)), '\r\n|\n|\r', 'split');
    for i = 1:numel(lines)
        line = char(lines{i});
        p = strfind(line, '%');
        if ~isempty(p)
            line = line(1:p(1)-1);
        end
        line = strtrim(line);
        if isempty(line)
            continue;
        end
        if ~isempty(regexp(line, 'setenv\s*\(\s*[''"]SECTION', 'once'))
            tf = true;
            return;
        end
    end
catch
    tf = false;
end
end


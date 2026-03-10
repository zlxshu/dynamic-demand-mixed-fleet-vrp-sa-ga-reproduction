function result = enforce_changelog_sync(cfg)
% enforce_changelog_sync - 强制检查代码修改日志同步
%
% 用法：
%   result = enforce_changelog_sync(cfg)
%
% 输入：
%   cfg - 配置结构体，包含：
%     cfg.runModesPath - run_modes.m 的完整路径（用于定位项目根目录）
%     cfg.strictMode   - 严格模式（可选，默认 false）
%
% 输出：
%   result - 检查结果结构体
%     result.passed       - 是否通过（true/false）
%     result.errors       - 错误列表（cell array）
%     result.warnings     - 警告列表（cell array）
%     result.missingCount - 缺失条目数量
%
% 检查项：
%   1. 扫描所有 .m 文件的修改日志
%   2. 对比 docs/CHANGELOG.md 中的记录
%   3. 检测不一致：文件中有日志但 CHANGELOG 中缺失
%
% 修改日志
% - v1 2026-02-03: 新增变更日志同步检查

result = struct();
result.passed = true;
result.errors = {};
result.warnings = {};
result.missingCount = 0;

if nargin < 1 || isempty(cfg)
    result.passed = false;
    result.errors{end+1} = 'enforce_changelog_sync: 缺少 cfg 参数';
    return;
end

% 定位项目根目录
if isfield(cfg, 'runModesPath') && ~isempty(cfg.runModesPath)
    runModesPath = cfg.runModesPath;
    if ~endsWith(runModesPath, '.m')
        runModesPath = [runModesPath '.m'];
    end
    projectRoot = fileparts(runModesPath);
else
    result.passed = false;
    result.errors{end+1} = 'enforce_changelog_sync: cfg.runModesPath 未指定';
    return;
end

changelogPath = fullfile(projectRoot, 'docs', 'CHANGELOG.md');

% 检查 CHANGELOG.md 是否存在
if ~exist(changelogPath, 'file')
    result.warnings{end+1} = sprintf('enforce_changelog_sync: docs/CHANGELOG.md 不存在: %s', changelogPath);
    % 非严格模式下仅警告，不报错
    if isfield(cfg, 'strictMode') && cfg.strictMode
        result.passed = false;
        result.errors{end+1} = 'enforce_changelog_sync: docs/CHANGELOG.md 不存在（严格模式）';
    end
    return;
end

fprintf('[enforce_changelog_sync] 项目根目录: %s\n', projectRoot);
fprintf('[enforce_changelog_sync] CHANGELOG: %s\n', changelogPath);

% 定义需要扫描的目录和文件
scanTargets = {
    fullfile(projectRoot, 'run_modes.m');
    fullfile(projectRoot, 'modules', 'experiments');
    fullfile(projectRoot, 'modules', 'config');
    fullfile(projectRoot, 'modules', 'runner');
    fullfile(projectRoot, 'modules', 'registry');
    fullfile(projectRoot, 'modules', 'core');
    fullfile(projectRoot, 'tools');
};

% 收集所有 .m 文件
allFiles = {};
for i = 1:numel(scanTargets)
    target = scanTargets{i};
    if exist(target, 'file') == 2
        allFiles{end+1} = target; %#ok<AGROW>
    elseif exist(target, 'dir') == 7
        files = dir(fullfile(target, '**', '*.m'));
        for j = 1:numel(files)
            allFiles{end+1} = fullfile(files(j).folder, files(j).name); %#ok<AGROW>
        end
    end
end

fprintf('[enforce_changelog_sync] 扫描 %d 个 .m 文件...\n', numel(allFiles));

% 读取 CHANGELOG.md 内容
changelogContent = fileread(changelogPath);

% 解析每个文件的修改日志并检查
missingLogs = {};
scannedWithLogs = 0;

for i = 1:numel(allFiles)
    fpath = allFiles{i};
    logs = parse_file_changelog_local_(fpath);
    
    if ~isempty(logs)
        scannedWithLogs = scannedWithLogs + 1;
        relPath = strrep(fpath, [projectRoot filesep], '');
        
        for j = 1:numel(logs)
            logLine = logs{j};
            % 提取版本号，例如 "v10 2026-02-02"
            vMatch = regexp(logLine, 'v(\d+)\s+\d{4}-\d{2}-\d{2}', 'match', 'once');
            if ~isempty(vMatch)
                % 检查 CHANGELOG 中是否包含该版本
                if ~contains(changelogContent, vMatch)
                    missingLogs{end+1} = struct('file', relPath, 'log', logLine, 'version', vMatch); %#ok<AGROW>
                end
            end
        end
    end
end

result.missingCount = numel(missingLogs);

% 输出结果
if isempty(missingLogs)
    fprintf('[enforce_changelog_sync] 检查通过：所有文件日志已同步到 CHANGELOG.md\n');
    fprintf('[enforce_changelog_sync] 扫描文件数: %d，有日志文件数: %d\n', numel(allFiles), scannedWithLogs);
else
    fprintf('[enforce_changelog_sync] 发现 %d 条日志未同步到 CHANGELOG.md：\n', numel(missingLogs));
    for i = 1:numel(missingLogs)
        item = missingLogs{i};
        fprintf('  - %s: %s\n', item.file, item.log);
        result.warnings{end+1} = sprintf('[未同步] %s: %s', item.file, item.log);
    end
    
    % 非严格模式下仅警告，不报错
    if isfield(cfg, 'strictMode') && cfg.strictMode
        result.passed = false;
        result.errors{end+1} = sprintf('enforce_changelog_sync: 发现 %d 条日志未同步（严格模式）', numel(missingLogs));
    end
    
    fprintf('[enforce_changelog_sync] 请手动更新 docs/CHANGELOG.md 或运行 sync_changelog(''sync'')\n');
end

end

function logs = parse_file_changelog_local_(fpath)
% 解析文件顶部的修改日志
logs = {};
try
    fid = fopen(fpath, 'r', 'n', 'UTF-8');
    if fid < 0
        return;
    end
    cleanup = onCleanup(@() fclose(fid));
    
    lineCount = 0;
    maxLines = 100;
    
    while ~feof(fid) && lineCount < maxLines
        line = fgetl(fid);
        if ~ischar(line)
            break;
        end
        lineCount = lineCount + 1;
        
        % 检测日志条目 "% - v* YYYY-MM-DD:"
        if startsWith(strtrim(line), '% - v') || startsWith(strtrim(line), '%- v')
            logEntry = regexprep(line, '^%\s*-?\s*', '');
            logs{end+1} = strtrim(logEntry); %#ok<AGROW>
            continue;
        end
        
        % 遇到函数定义或非注释行，退出
        if startsWith(strtrim(line), 'function') || ...
           (~startsWith(strtrim(line), '%') && ~isempty(strtrim(line)))
            break;
        end
    end
catch
    logs = {};
end
end

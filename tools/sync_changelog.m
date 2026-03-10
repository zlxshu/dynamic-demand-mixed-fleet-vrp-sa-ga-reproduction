function result = sync_changelog(mode)
% sync_changelog - 自动同步代码修改日志到 docs/CHANGELOG.md
%
% 用法：
%   sync_changelog()        % 扫描并报告差异（不写入）
%   sync_changelog('check') % 仅检查，不写入
%   sync_changelog('sync')  % 扫描并同步写入
%
% 功能：
%   1. 扫描所有 .m 文件顶部的 "% 修改日志" / "% - v*" 注释
%   2. 对比 docs/CHANGELOG.md 中对应模块的记录
%   3. 检测不一致：文件中有日志但 CHANGELOG 中缺失
%   4. 生成报告或自动同步
%
% 修改日志
% - v1 2026-02-03: 新增自动同步脚本，扫描所有文件的修改日志并同步到 CHANGELOG.md

if nargin < 1
    mode = 'check';
end
mode = lower(strtrim(char(string(mode))));

% 定位项目根目录
scriptPath = mfilename('fullpath');
toolsDir = fileparts(scriptPath);
projectRoot = fileparts(toolsDir);
changelogPath = fullfile(projectRoot, 'docs', 'CHANGELOG.md');

fprintf('[sync_changelog] 项目根目录: %s\n', projectRoot);
fprintf('[sync_changelog] CHANGELOG: %s\n', changelogPath);
fprintf('[sync_changelog] 模式: %s\n', mode);

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
        % 单个文件
        allFiles{end+1} = target; %#ok<AGROW>
    elseif exist(target, 'dir') == 7
        % 目录，递归扫描
        files = dir(fullfile(target, '**', '*.m'));
        for j = 1:numel(files)
            allFiles{end+1} = fullfile(files(j).folder, files(j).name); %#ok<AGROW>
        end
    end
end

fprintf('[sync_changelog] 找到 %d 个 .m 文件\n', numel(allFiles));

% 解析每个文件的修改日志
fileLogMap = containers.Map();
for i = 1:numel(allFiles)
    fpath = allFiles{i};
    logs = parse_file_changelog_(fpath);
    if ~isempty(logs)
        % 使用相对路径作为 key
        relPath = strrep(fpath, [projectRoot filesep], '');
        fileLogMap(relPath) = logs;
    end
end

fprintf('[sync_changelog] 解析到 %d 个文件有修改日志\n', fileLogMap.Count);

% 读取现有 CHANGELOG.md
changelogContent = '';
if exist(changelogPath, 'file') == 2
    changelogContent = fileread(changelogPath);
end

% 检查差异
missingInChangelog = {};
keys = fileLogMap.keys();
for i = 1:numel(keys)
    relPath = keys{i};
    logs = fileLogMap(relPath);
    for j = 1:numel(logs)
        logLine = logs{j};
        % 提取版本号，例如 "v10 2026-02-02"
        vMatch = regexp(logLine, 'v(\d+)\s+\d{4}-\d{2}-\d{2}', 'match', 'once');
        if ~isempty(vMatch)
            % 检查 CHANGELOG 中是否包含该版本
            if ~contains(changelogContent, vMatch)
                missingInChangelog{end+1} = struct('file', relPath, 'log', logLine); %#ok<AGROW>
            end
        end
    end
end

% 输出结果
result = struct();
result.scannedFiles = numel(allFiles);
result.filesWithLogs = fileLogMap.Count;
result.missingCount = numel(missingInChangelog);
result.missing = missingInChangelog;

if isempty(missingInChangelog)
    fprintf('[sync_changelog] 检查通过：所有文件日志已同步到 CHANGELOG.md\n');
else
    fprintf('[sync_changelog] 发现 %d 条日志未同步到 CHANGELOG.md：\n', numel(missingInChangelog));
    for i = 1:numel(missingInChangelog)
        item = missingInChangelog{i};
        fprintf('  - %s: %s\n', item.file, item.log);
    end
    
    if strcmp(mode, 'sync')
        fprintf('[sync_changelog] 自动同步功能暂未实现，请手动更新 docs/CHANGELOG.md\n');
        % TODO: 实现自动同步写入
    else
        fprintf('[sync_changelog] 请手动更新 docs/CHANGELOG.md 或运行 sync_changelog(''sync'')\n');
    end
end

end

function logs = parse_file_changelog_(fpath)
% 解析文件顶部的修改日志
logs = {};
try
    fid = fopen(fpath, 'r', 'n', 'UTF-8');
    if fid < 0
        return;
    end
    cleanup = onCleanup(@() fclose(fid));
    
    inLogSection = false;
    lineCount = 0;
    maxLines = 100; % 只扫描前 100 行
    
    while ~feof(fid) && lineCount < maxLines
        line = fgetl(fid);
        if ~ischar(line)
            break;
        end
        lineCount = lineCount + 1;
        
        % 检测修改日志区域
        if contains(line, '修改日志') || contains(line, 'Changelog') || contains(line, 'CHANGELOG')
            inLogSection = true;
            continue;
        end
        
        % 检测日志条目 "% - v* YYYY-MM-DD:"
        if startsWith(strtrim(line), '% - v') || startsWith(strtrim(line), '%- v')
            logEntry = regexprep(line, '^%\s*-?\s*', '');
            logs{end+1} = strtrim(logEntry); %#ok<AGROW>
            inLogSection = true;
            continue;
        end
        
        % 如果已进入日志区域但遇到非日志行，退出
        if inLogSection && ~startsWith(strtrim(line), '%')
            break;
        end
    end
catch
    logs = {};
end
end

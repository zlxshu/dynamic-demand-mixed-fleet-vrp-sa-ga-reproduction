function paths = output_paths(projectRoot, sectionName, runTag)
% 修改日志
% - v1 2026-01-21: 新增统一输出目录规范 outputs/<sectionName>/{logs,cache,mats,figures,tables}。
% - v1 2026-01-21: 自动创建目录并返回 paths struct；文件命名由 artifact_filename 统一生成。

    if nargin < 1 || isempty(projectRoot)
        projectRoot = project_root_dir();
    end
    if nargin < 2 || isempty(sectionName)
        sectionName = 'unknown_section';
    end
    if nargin < 3
        runTag = 'default';
    end

    sectionName = char(string(sectionName));

    outRoot = fullfile(projectRoot, 'outputs', sectionName);
    paths = struct();
    paths.root = outRoot;
    paths.logs = fullfile(outRoot, 'logs');
    paths.cache = fullfile(outRoot, 'cache');
    paths.mats = fullfile(outRoot, 'mats');
    paths.figures = fullfile(outRoot, 'figures');
    paths.tables = fullfile(outRoot, 'tables');
    paths.sectionName = sectionName;
    paths.runTag = char(string(runTag));

    ensure_dir(paths.root);
    ensure_dir(paths.logs);
    ensure_dir(paths.cache);
    ensure_dir(paths.mats);
    ensure_dir(paths.figures);
    ensure_dir(paths.tables);
end



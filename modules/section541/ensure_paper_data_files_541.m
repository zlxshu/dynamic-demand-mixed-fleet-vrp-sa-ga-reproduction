function info = ensure_paper_data_files_541(projectRoot, staticName, dynamicName, logPath, alignReportPath)
% ensure_paper_data_files_541 - 保障论文示例静态/动态数据文件存在；若缺失则按论文表格生成
% 修改日志
% - v1 2026-01-26: 新增：基于论文表 4.1/5.6 的静态/动态数据生成（缺失时创建，不覆盖已有文件）。
% - v2 2026-01-27: 兼容绝对/相对路径，避免 data/data 重复前缀。
% - v3 2026-01-27: 兼容 projectRoot 传入 data/；自动折叠为工程根，避免再次生成 data/data。

    if nargin < 1 || isempty(projectRoot)
        projectRoot = project_root_dir();
    end
    if nargin < 2 || isempty(staticName)
        staticName = '论文示例静态节点数据.xlsx';
    end
    if nargin < 3 || isempty(dynamicName)
        dynamicName = '论文示例动态需求数据.xlsx';
    end

    info = struct();
    info.staticPath = resolve_paper_path_541_(projectRoot, staticName);
    info.dynamicPath = resolve_paper_path_541_(projectRoot, dynamicName);
    info.staticCreated = false;
    info.dynamicCreated = false;

    ensure_dir(fileparts(info.staticPath));

    % 静态数据（表4.1）
    if exist(info.staticPath, 'file') ~= 2
        try
            staticRows = paper_static_rows_541_();
            header = {'ID','X','Y','需求(kg)','时间窗'};
            raw = [header; staticRows];
            if exist('writecell','file') == 2
                writecell(raw, info.staticPath);
            else
                T = cell2table(staticRows, 'VariableNames', matlab.lang.makeValidName(header));
                writetable(T, info.staticPath);
            end
            info.staticCreated = true;
            log_append_(logPath, sprintf('[paper_data] created static: %s', info.staticPath));
            log_append_(alignReportPath, sprintf('[paper_data] created static: %s', info.staticPath));
        catch ME
            log_append_(logPath, sprintf('[paper_data] create static failed: %s', ME.message));
            log_append_(alignReportPath, sprintf('[paper_data] create static failed: %s', ME.message));
        end
    else
        log_append_(logPath, sprintf('[paper_data] static exists: %s', info.staticPath));
    end

    % 动态数据（表5.6）
    if exist(info.dynamicPath, 'file') ~= 2
        try
            dynamicRows = paper_dynamic_rows_541_();
            header = {'ID','需求类型','X','Y','需求(kg)','时间窗','更新时间'};
            raw = [header; dynamicRows];
            if exist('writecell','file') == 2
                writecell(raw, info.dynamicPath);
            else
                T = cell2table(dynamicRows, 'VariableNames', matlab.lang.makeValidName(header));
                writetable(T, info.dynamicPath);
            end
            info.dynamicCreated = true;
            log_append_(logPath, sprintf('[paper_data] created dynamic: %s', info.dynamicPath));
            log_append_(alignReportPath, sprintf('[paper_data] created dynamic: %s', info.dynamicPath));
        catch ME
            log_append_(logPath, sprintf('[paper_data] create dynamic failed: %s', ME.message));
            log_append_(alignReportPath, sprintf('[paper_data] create dynamic failed: %s', ME.message));
        end
    else
        log_append_(logPath, sprintf('[paper_data] dynamic exists: %s', info.dynamicPath));
    end
end

% ========================= helpers =========================
function p = resolve_paper_path_541_(projectRoot, name)
    p = '';
    if isempty(name)
        return;
    end
    n = char(string(name));
    if isempty(n)
        return;
    end

    projectRoot = normalize_project_root_541_(projectRoot);
    if is_absolute_path_541_(n)
        p = n;
        return;
    end
    hasSep = contains(n, {'/','\'});
    if hasSep
        p = fullfile(projectRoot, n);
    else
        p = fullfile(projectRoot, 'data', n);
    end
end

function root = normalize_project_root_541_(projectRoot)
    root = projectRoot;
    try
        root = char(string(projectRoot));
    catch
    end
    if isempty(root)
        return;
    end
    [parent, last] = fileparts(root);
    if ~isempty(parent) && strcmpi(last, 'data')
        root = parent;
    end
end

function tf = is_absolute_path_541_(p)
    tf = false;
    if isempty(p)
        return;
    end
    p = char(string(p));
    if ispc
        tf = ~isempty(regexp(p, '^[A-Za-z]:[\\/]', 'once'));
    else
        tf = startsWith(p, '/');
    end
end

function rows = paper_static_rows_541_()
% 表4.1 各节点信息（论文示例）
rows = {
    0, 56, 56, 0,   '[00:00-24:00]';
    1, 66, 78, 214, '[09:20-14:00]';
    2, 56, 27, 204, '[10:00-14:20]';
    3, 88, 72, 216, '[07:00-17:00]';
    4, 50, 38, 215, '[05:20-14:00]';
    5, 32, 80, 229, '[00:00-10:00]';
    6, 16, 69, 276, '[00:00-07:00]';
    7, 88, 96, 189, '[06:00-12:00]';
    8, 48, 96, 203, '[07:00-12:00]';
    9, 35, 94, 165, '[04:00-10:00]';
    10, 68, 48, 278, '[07:00-09:00]';
    11, 24, 16, 208, '[02:00-12:00]';
    12, 16, 32, 210, '[07:00-10:20]';
    13, 8, 48, 209,  '[07:00-14:20]';
    14, 32, 66, 255, '[00:00-09:40]';
    15, 24, 48, 210, '[02:00-10:00]';
    16, 72, 64, 213, '[07:00-12:00]';
    17, 72, 96, 203, '[06:00-12:00]';
    18, 72, 104, 215,'[00:00-24:00]';
    19, 87, 25, 231, '[07:00-12:00]';
    20, 83, 45, 247, '[08:00-10:00]';
    'R1', 40, 80, 0, '[00:00-24:00]';
    'R2', 40, 35, 0, '[00:00-24:00]';
    'R3', 69, 63, 0, '[00:00-24:00]';
    'R4', 67, 90, 0, '[00:00-24:00]';
    'R5', 26, 54, 0, '[00:00-24:00]';
    };
end

function rows = paper_dynamic_rows_541_()
% 表5.6 动态需求信息（论文示例）
rows = {
    21, '新增', 38, 45, 223, '[10:40-14:00]', '08:03';
    22, '新增', 56, 76, 258, '[08:40-16:00]', '08:17';
    2,  '取消', 56, 27, 204, '[10:00-14:20]', '08:35';
    4,  '减少', 50, 38, 180, '[05:20-14:00]', '08:50';
    23, '新增', 28, 45, 243, '[10:00-12:00]', '08:59';
    24, '新增', 41, 58, 246, '[10:20-15:40]', '09:14';
    25, '新增', 29, 12, 251, '[10:00-13:40]', '09:43';
    14, '取消', 88, 25, 255, '[00:00-09:20]', '09:50';
    };
end

function log_append_(logPath, line)
    if nargin < 1 || isempty(logPath)
        return;
    end
    try
        ensure_dir(fileparts(logPath));
        fid = fopen(logPath, 'a');
        if fid < 0, return; end
        c = onCleanup(@() fclose(fid));
        fprintf(fid, '%s\n', char(string(line)));
    catch
    end
end

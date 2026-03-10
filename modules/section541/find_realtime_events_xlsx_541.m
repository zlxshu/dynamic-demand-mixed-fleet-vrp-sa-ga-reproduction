function xlsxPath = find_realtime_events_xlsx_541(projectRoot, preferredName)
% find_realtime_events_xlsx_541 - 在项目 data/ 下定位“动态需求事件”表
% 兼容：
% - 优先使用指定文件名（如“论文示例动态需求数据.xlsx”）
% - 文件名可能被转义为 #Uxxxx（Windows/zip 某些场景）
% - 多个候选时按关键字打分
% 修改日志
% - v1 2026-01-24: 初版：基于关键字打分选择。
% - v2 2026-01-26: 支持 preferredName 优先定位（论文示例事件表）。
% - v3 2026-01-27: 兼容 projectRoot 传入 data/；自动折叠为工程根，避免 data/data。

    if nargin < 1 || isempty(projectRoot)
        projectRoot = project_root_dir();
    end
    if nargin < 2
        preferredName = '';
    end

    projectRoot = normalize_project_root_541_(projectRoot);
    dataDir = fullfile(projectRoot, 'data');
    if exist(dataDir, 'dir') ~= 7
        error('section_541:missingDataDir', 'data/ not found under: %s', projectRoot);
    end

    cand = dir(fullfile(dataDir, '*.xlsx'));
    if isempty(cand)
        error('section_541:noXlsx', 'no .xlsx found under: %s', dataDir);
    end

    % 1) 优先：指定文件名（严格匹配）
    if ~isempty(preferredName)
        prefPath = fullfile(dataDir, char(string(preferredName)));
        if exist(prefPath, 'file') == 2
            xlsxPath = prefPath;
            return;
        end
    end

    names = string({cand.name});
    score = zeros(numel(cand), 1);
    for i = 1:numel(cand)
        n = lower(names(i));
        if contains(n, "论文"), score(i) = score(i) + 8; end
        if contains(n, "示例"), score(i) = score(i) + 6; end
        if contains(n, "动态"), score(i) = score(i) + 6; end
        if contains(n, "需求"), score(i) = score(i) + 6; end
        if contains(n, "实时"), score(i) = score(i) + 5; end
        if contains(n, "客户"), score(i) = score(i) + 4; end
        if contains(n, "数据"), score(i) = score(i) + 3; end
        if contains(n, "#u"),   score(i) = score(i) + 1; end
        % 更近更新优先（同分时）
        score(i) = score(i) + 1e-6 * cand(i).datenum;
    end

    [~, idx] = max(score);
    xlsxPath = fullfile(dataDir, cand(idx).name);

    if exist(xlsxPath, 'file') ~= 2
        error('section_541:xlsxNotFound', 'xlsx not found: %s', xlsxPath);
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

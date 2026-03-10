function [events, recvWindow] = read_realtime_events_541(xlsxPath)
% read_realtime_events_541 - 读取动态事件表并标准化为统一字段
% 允许内部使用表格读取函数（与 section 主入口隔离，避免静态扫描误伤）。
% 修改日志
% - v1 2026-01-24: 初版：多 sheet + 容错列匹配。
% - v2 2026-01-26: 修复“需求”列误匹配到“需求变更”等文本列：优先精确匹配，并在包含匹配时用相似度评分选择最优列。
% - v3 2026-01-26: 支持“时间窗/更新时间”列；当 LTW/RTW 缺失时由时间窗解析补齐。
% - v4 2026-01-27: 接收窗口仅从“动态需求接收时间/接收窗口”读取，避免误用客户服务时间窗。
% - v5 2026-01-31: 增加 5 车排查日志（debug）。

    if nargin < 1 || isempty(xlsxPath) || exist(xlsxPath, 'file') ~= 2
        error('section_541:badXlsxPath', 'xlsxPath invalid');
    end

    recvWindow = [];
    rows = {};

    sheets = list_sheets_(xlsxPath);
    for si = 1:numel(sheets)
        sheet = sheets{si};

        [raw, header] = read_sheet_raw_(xlsxPath, sheet);
        if isempty(raw) || isempty(header)
            continue;
        end

        % 列定位（优先列名，缺失再 fallback 到常见位置）
        c_customer = find_col_(header, {'客户','客户点','节点','id','ID','customer'});
        c_type     = find_col_(header, {'需求类型','类型','事件','变更','新增','取消','type'});
        c_x        = find_col_(header, {'x','X'});
        c_y        = find_col_(header, {'y','Y'});
        c_q        = find_col_(header, {'需求(kg)','需求','demand','q'});
        c_ltw      = find_col_(header, {'ltw','lt','最早'});
        c_rtw      = find_col_(header, {'rtw','rt','最晚'});
        c_time     = find_col_(header, {'更新时间','出现时间','到达时间','接收时间','时间','t'});
        c_win      = find_col_(header, {'动态需求接收时间','接收窗口','接收时间窗','窗口'});
        c_tw       = find_col_(header, {'时间窗','时间窗口'});

        % fallback（常见格式：A 客户点，B 类型，C X，D Y，E 需求，F LTW，G RTW，H 出现时间，J 窗口）
        if isempty(c_customer), c_customer = 1; end
        if isempty(c_type),     c_type     = min(2, size(raw,2)); end
        if isempty(c_x),        c_x        = min(3, size(raw,2)); end
        if isempty(c_y),        c_y        = min(4, size(raw,2)); end
        if isempty(c_q),        c_q        = min(5, size(raw,2)); end
        if isempty(c_ltw),      c_ltw      = min(6, size(raw,2)); end
        if isempty(c_rtw),      c_rtw      = min(7, size(raw,2)); end
        if isempty(c_time),     c_time     = min(8, size(raw,2)); end
        if isempty(c_win) && size(raw,2) >= 10
            c_win = 10;
        end
        if isempty(c_time) && size(raw,2) >= 8
            c_time = min(8, size(raw,2));
        end

        % recvWindow：仅从“动态需求接收时间/接收窗口”列解析
        if isempty(recvWindow)
            if ~isempty(c_win) && c_win <= size(raw,2)
                wv = first_nonempty_(raw(:, c_win));
                recvWindow = parse_window_to_min_541(wv);
            end
        end

        for r = 1:size(raw,1)
            cid = to_double_scalar_(raw{r, c_customer});
            typ = string(raw{r, c_type});
            t0  = parse_time_to_min_541(raw{r, c_time});
            if ~isfinite(cid) || strlength(strtrim(typ)) == 0 || ~isfinite(t0)
                continue;
            end

            ev = normalize_type_(typ);

            x = to_double_scalar_(safe_cell_(raw, r, c_x));
            y = to_double_scalar_(safe_cell_(raw, r, c_y));
            q = to_double_scalar_(safe_cell_(raw, r, c_q));
            ltw = to_double_scalar_(safe_cell_(raw, r, c_ltw));
            rtw = to_double_scalar_(safe_cell_(raw, r, c_rtw));

            % 若 LTW/RTW 缺失，尝试从“时间窗”列解析
            if (~isfinite(ltw) || ~isfinite(rtw)) && ~isempty(c_tw) && c_tw <= size(raw,2)
                win = parse_window_to_min_541(safe_cell_(raw, r, c_tw));
                if numel(win) == 2
                    if ~isfinite(ltw), ltw = win(1); end
                    if ~isfinite(rtw), rtw = win(2); end
                end
            end

            rows(end+1,:) = {cid, ev, string(typ), t0, x, y, ltw, rtw, q, string(sheet), r}; %#ok<AGROW>
        end
    end

    if isempty(rows)
        events = table('Size',[0 11], ...
            'VariableTypes', {'double','string','string','double','double','double','double','double','double','string','double'}, ...
            'VariableNames', {'customerId','eventType','rawType','tAppearMin','x','y','LTW','RTW','newDemandKg','sheet','rowInSheet'});
        return;
    end

    events = cell2table(rows, 'VariableNames', {'customerId','eventType','rawType','tAppearMin','x','y','LTW','RTW','newDemandKg','sheet','rowInSheet'});
    events = sortrows(events, 'tAppearMin');
end

% ========================= helpers =========================
function sheets = list_sheets_(xlsxPath)
    sheets = {};
    try
        if exist('sheetnames', 'file') == 2
            s = sheetnames(xlsxPath);
            sheets = cellstr(s);
            return;
        end
    catch
    end
    try
        [~, sheets] = xlsfinfo(xlsxPath);
        if isempty(sheets)
            sheets = {'Sheet1'};
        end
    catch
        sheets = {'Sheet1'};
    end
end

function [raw, header] = read_sheet_raw_(xlsxPath, sheet)
    raw = {};
    header = {};
    try
        if exist('readcell', 'file') == 2
            rawAll = readcell(xlsxPath, 'Sheet', sheet);
            [raw, header] = split_header_(rawAll);
            return;
        end
    catch
    end

    % fallback: readtable then convert to cell
    try
        T = readtable(xlsxPath, 'Sheet', sheet, 'PreserveVariableNames', true);
        header = T.Properties.VariableNames;
        raw = table2cell(T);
    catch
        raw = {};
        header = {};
    end
end

function [data, header] = split_header_(rawAll)
    data = {};
    header = {};
    if isempty(rawAll)
        return;
    end
    % 找到第一行“非空且包含字符”的作为 header
    headerRow = 0;
    for r = 1:size(rawAll,1)
        row = rawAll(r,:);
        hasText = false;
        for c = 1:numel(row)
            v = row{c};
            if isstring(v) || ischar(v)
                s = strtrim(char(string(v)));
                if ~isempty(s)
                    hasText = true;
                    break;
                end
            end
        end
        if hasText
            headerRow = r;
            break;
        end
    end
    if headerRow == 0
        return;
    end
    header = rawAll(headerRow,:);
    data = rawAll(headerRow+1:end, :);
end

function idx = find_col_(header, keys)
    idx = [];
    if isempty(header)
        return;
    end
    h = string(header);
    h = lower(strtrim(h));
    h(ismissing(h)) = "";

    % 1) 优先精确匹配（避免 key='需求' 命中 '需求变更'）
    for k = 1:numel(keys)
        key = lower(strtrim(string(keys{k})));
        if strlength(key) == 0
            continue;
        end
        m = find(h == key, 1, 'first');
        if ~isempty(m)
            idx = m;
            return;
        end
    end

    % 2) 包含匹配：在所有候选中挑“最接近”的列（key/len(header) 越大越接近）
    bestScore = -inf;
    bestIdx = [];
    for k = 1:numel(keys)
        key = lower(strtrim(string(keys{k})));
        if strlength(key) == 0
            continue;
        end
        ms = find(contains(h, key));
        if isempty(ms)
            continue;
        end
        for ii = 1:numel(ms)
            j = ms(ii);
            denom = double(strlength(h(j)));
            if denom <= 0
                denom = 1;
            end
            score = double(strlength(key)) / denom;
            if startsWith(h(j), key)
                score = score + 0.05;
            end
            if score > bestScore
                bestScore = score;
                bestIdx = j;
            end
        end
    end
    if ~isempty(bestIdx)
        idx = bestIdx;
    end
end

function v = safe_cell_(raw, r, c)
    v = NaN;
    try
        if r <= size(raw,1) && c <= size(raw,2)
            v = raw{r,c};
        end
    catch
    end
end

function v = first_nonempty_(col)
    v = [];
    for i = 1:numel(col)
        x = col{i};
        if isempty(x)
            continue;
        end
        if ismissing(x)
            continue;
        end
        if ischar(x) || isstring(x)
            if strlength(strtrim(string(x))) == 0
                continue;
            end
        end
        v = x;
        return;
    end
end

function d = to_double_scalar_(x)
    d = NaN;
    if isempty(x)
        return;
    end
    if iscell(x) && numel(x) == 1
        x = x{1};
    end
    if isnumeric(x) && isscalar(x)
        d = double(x);
        return;
    end
    if isstring(x) || ischar(x)
        s = strtrim(char(string(x)));
        if isempty(s)
            return;
        end
        d2 = str2double(s);
        if isfinite(d2)
            d = d2;
        end
        return;
    end
end

function ev = normalize_type_(typ)
    s = lower(strtrim(char(string(typ))));
    if contains(s, '新增') || contains(s, 'add')
        ev = "add";
    elseif contains(s, '取消') || contains(s, 'cancel')
        ev = "cancel";
    elseif contains(s, '减少') || contains(s, '增加') || contains(s, '变更') || contains(s, 'update') || contains(s, 'change')
        ev = "update";
    else
        ev = "update";
    end
end

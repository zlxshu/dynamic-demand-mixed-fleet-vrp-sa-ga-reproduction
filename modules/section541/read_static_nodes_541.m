function [Data, meta] = read_static_nodes_541(xlsxPath, ctx)
% read_static_nodes_541 - 读取论文静态节点表（表4.1）并构建 Data 结构
% 修改日志
% - v1 2026-01-26: 初版：支持 ID/坐标/需求/时间窗；R1..RE 识别为充电站。

    if nargin < 1 || isempty(xlsxPath) || exist(xlsxPath,'file') ~= 2
        error('section_541:staticXlsxMissing', 'static xlsx not found: %s', char(string(xlsxPath)));
    end
    if nargin < 2, ctx = struct(); end %#ok<NASGU>

    rawAll = {};
    try
        if exist('readcell','file') == 2
            rawAll = readcell(xlsxPath);
        end
    catch
        rawAll = {};
    end
    if isempty(rawAll)
        try
            T = readtable(xlsxPath, 'PreserveVariableNames', true);
            rawAll = [T.Properties.VariableNames; table2cell(T)];
        catch ME
            error('section_541:staticReadFailed', 'read static xlsx failed: %s', ME.message);
        end
    end

    [raw, header] = split_header_(rawAll);
    if isempty(raw) || isempty(header)
        error('section_541:staticBadHeader', 'static xlsx header not found: %s', xlsxPath);
    end

    c_id   = find_col_(header, {'ID','id','节点','客户'});
    c_x    = find_col_(header, {'X','x'});
    c_y    = find_col_(header, {'Y','y'});
    c_q    = find_col_(header, {'需求(kg)','需求','demand'});
    c_tw   = find_col_(header, {'时间窗','时间窗口','TW'});

    if isempty(c_id), c_id = 1; end
    if isempty(c_x),  c_x  = min(2, size(raw,2)); end
    if isempty(c_y),  c_y  = min(3, size(raw,2)); end
    if isempty(c_q),  c_q  = min(4, size(raw,2)); end
    if isempty(c_tw), c_tw = min(5, size(raw,2)); end

    rows = {};
    maxCustId = 0;
    maxStationIdx = 0;
    for r = 1:size(raw,1)
        rid = raw{r, c_id};
        [isStation, idNum, stIdx] = parse_id_(rid);
        if ~isfinite(idNum) && ~isStation
            continue;
        end
        x = to_double_scalar_(safe_cell_(raw, r, c_x));
        y = to_double_scalar_(safe_cell_(raw, r, c_y));
        q = to_double_scalar_(safe_cell_(raw, r, c_q));
        tw = safe_cell_(raw, r, c_tw);
        win = parse_window_to_min_541(tw);
        if numel(win) ~= 2
            win = [0 1440];
        end
        if ~isStation
            maxCustId = max(maxCustId, idNum);
        else
            maxStationIdx = max(maxStationIdx, stIdx);
        end
        rows(end+1,:) = {isStation, idNum, stIdx, x, y, q, win(1), win(2)}; %#ok<AGROW>
    end

    n = maxCustId;
    E = maxStationIdx;
    if n <= 0
        error('section_541:staticNoCustomers', 'no valid customer IDs in static xlsx');
    end
    if E <= 0
        E = 0;
    end

    coord = NaN(1+n+E, 2);
    q = zeros(1+n+E, 1);
    LT = NaN(1+n+E, 1);
    RT = NaN(1+n+E, 1);

    for i = 1:size(rows,1)
        isStation = rows{i,1};
        idNum = rows{i,2};
        stIdx = rows{i,3};
        x = rows{i,4};
        y = rows{i,5};
        dem = rows{i,6};
        lt = rows{i,7};
        rt = rows{i,8};

        if ~isStation
            nodeId = idNum;
            idx = nodeId + 1;
            coord(idx,:) = [x y];
            q(idx) = max(0, dem);
            LT(idx) = lt;
            RT(idx) = rt;
        else
            nodeId = n + stIdx;
            idx = nodeId + 1;
            coord(idx,:) = [x y];
            q(idx) = 0;
            LT(idx) = lt;
            RT(idx) = rt;
        end
    end

    % depot (id=0) 必须存在
    if any(~isfinite(coord(1,:)))
        error('section_541:staticDepotMissing', 'depot (ID=0) missing in static xlsx');
    end
    if ~isfinite(LT(1)) || ~isfinite(RT(1))
        LT(1) = 0; RT(1) = 1440;
    end

    % 缺失时间窗补全为全窗
    LT(~isfinite(LT)) = 0;
    RT(~isfinite(RT)) = 1440;

    Data = struct();
    Data.coord = coord;
    Data.q = q;
    Data.LT = LT;
    Data.RT = RT;
    Data.n = n;
    Data.E = E;
    try Data.ST = ctx.Data.ST; catch, Data.ST = 20; end
    Data.D = pairwise_dist_fast(coord);

    meta = struct();
    meta.source = 'paper_static_xlsx';
    meta.path = xlsxPath;
    meta.n = n;
    meta.E = E;
end

% ========================= helpers =========================
function [data, header] = split_header_(rawAll)
    data = {};
    header = {};
    if isempty(rawAll)
        return;
    end
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
            if denom <= 0, denom = 1; end
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

function [isStation, idNum, stIdx] = parse_id_(rid)
    isStation = false;
    idNum = NaN;
    stIdx = NaN;
    if isempty(rid)
        return;
    end
    if iscell(rid) && numel(rid) == 1
        rid = rid{1};
    end
    if isnumeric(rid) && isscalar(rid)
        idNum = double(rid);
        return;
    end
    if isstring(rid) || ischar(rid)
        s = upper(strtrim(char(string(rid))));
        if startsWith(s,'R')
            isStation = true;
            stIdx = str2double(regexprep(s,'[^0-9]',''));
            if ~isfinite(stIdx), stIdx = NaN; end
            return;
        end
        v = str2double(s);
        if isfinite(v)
            idNum = v;
        end
    end
end

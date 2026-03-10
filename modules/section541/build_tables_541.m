function [tblPlan, tblCost, costHistory] = build_tables_541(instance, planNow, timelineNow, tNow, cfg, costHistory)
% build_tables_541 - 每次更新输出：方案表（路径/节点+时间/里程）与成本对比表（累计）
% 修改日志
% - v1 2026-01-25: 表头与成本项中文化（论文中文口径），不改变求解结果与数值。
% - v2 2026-01-27: 方案表改为论文结构；成本表改为“初始+历次更新累计对比”。
% - v3 2026-01-27: 路径命名与表头对齐论文；方案/成本表改为 cell 以保持原样表头。
% - v4 2026-01-27: 成本表行名改为“HH:MM 路径”；HH:MM 对 NaN 输出 --:--（仅影响展示）。

    if nargin < 6
        costHistory = struct([]);
    end
    if nargin < 5, cfg = struct(); end %#ok<NASGU>

    % ===== 方案表（每条路径一行，节点与时间信息同单元格两行显示）=====
    rows = {};
    veh = timelineNow.vehicles;
    names = strings(numel(veh),1);
    for k = 1:numel(veh)
        names(k) = string(veh(k).name);
    end
    order = vehicle_order_541_(names);
    pathIdx = 0;
    for oi = 1:numel(order)
        k = order(oi);
        v = veh(k);
        if v.distanceKm < 1e-9
            continue;
        end
        pathIdx = pathIdx + 1;
        pathName = sprintf('路径%d\n(%s)', pathIdx, v.name);
        [nodeStr, timeStr] = route_strings_541_(v, instance);
        nodeTime = sprintf('%s\n%s', nodeStr, timeStr);
        rows(end+1,:) = {pathName, nodeTime, v.distanceKm}; %#ok<AGROW>
    end
    headerPlan = {'路径','节点和时间信息','里程(km)'};
    tblPlan = [headerPlan; rows];

    % ===== 成本对比表（累计：初始+历次更新）=====
    nowCost = summary_cost_(timelineNow, planNow);
    labelNow = sprintf('%s 路径', min_to_hhmm_(tNow));
    costHistory = append_cost_history_(costHistory, labelNow, nowCost);

    tblCost = build_cost_table_cumulative_(costHistory);
end

function s = summary_cost_(timelineNow, planNow)
    s = struct('startCost',NaN,'driveCost',NaN,'fuelCost',NaN,'elecCost',NaN,'carbonCost',NaN,'totalCost',NaN);
    try
        if isfield(timelineNow,'summary')
            s.startCost = timelineNow.summary.startCost;
            s.driveCost = timelineNow.summary.driveCost;
            s.fuelCost = timelineNow.summary.fuelCost;
            s.elecCost = timelineNow.summary.elecCost;
            s.carbonCost = timelineNow.summary.carbonCost;
            s.totalCost = timelineNow.summary.totalCost;
            return;
        end
    catch
    end
    try
        d = planNow.detail;
        s.startCost = sum([d.startCost]);
        s.driveCost = sum([d.driveCost]);
        s.fuelCost = sum([d.fuelCost]);
        s.elecCost = sum([d.elecCost]);
        s.carbonCost = sum([d.carbonCost]);
        s.totalCost = sum([d.totalCost]);
    catch
    end
end

function s = min_to_hhmm_(tMin)
    if ~isfinite(tMin)
        s = '--:--';
        return;
    end
    h = floor(tMin/60);
    m = round(tMin - 60*h);
    s = sprintf('%02d:%02d', h, m);
end

function hist = append_cost_history_(hist, label, cost)
    if isempty(hist)
        hist = struct('label', {}, 'startCost', {}, 'driveCost', {}, 'fuelCost', {}, 'elecCost', {}, 'carbonCost', {}, 'totalCost', {});
    end
    hist(end+1).label = label; %#ok<AGROW>
    hist(end).startCost = cost.startCost;
    hist(end).driveCost = cost.driveCost;
    hist(end).fuelCost = cost.fuelCost;
    hist(end).elecCost = cost.elecCost;
    hist(end).carbonCost = cost.carbonCost;
    hist(end).totalCost = cost.totalCost;
end

function tbl = build_cost_table_cumulative_(hist)
    if isempty(hist)
        tbl = {};
        return;
    end
    n = numel(hist);
    paths = strings(n,1);
    startCost = NaN(n,1);
    driveCost = NaN(n,1);
    fuelCost = NaN(n,1);
    elecCost = NaN(n,1);
    carbonCost = NaN(n,1);
    totalCost = NaN(n,1);
    for i = 1:n
        paths(i) = string(hist(i).label);
        startCost(i) = hist(i).startCost;
        driveCost(i) = hist(i).driveCost;
        fuelCost(i) = hist(i).fuelCost;
        elecCost(i) = hist(i).elecCost;
        carbonCost(i) = hist(i).carbonCost;
        totalCost(i) = hist(i).totalCost;
    end
    header = {'配送路径','启动成本  (元)','行驶成本  (元)','油耗成本  (元)','耗电成本  (元)','碳排放成本  (元)','总成本  (元)'};
    rows = cell(n, numel(header));
    for i = 1:n
        rows(i,:) = {char(paths(i)), startCost(i), driveCost(i), fuelCost(i), elecCost(i), carbonCost(i), totalCost(i)};
    end
    tbl = [header; rows];
end

function [nodeStr, timeStr] = route_strings_541_(veh, instance)
    route = veh.route(:).';
    if isempty(route)
        nodeStr = '';
        timeStr = '';
        return;
    end
    labels = strings(numel(route),1);
    for i = 1:numel(route)
        labels(i) = node_label_table_541_(route(i), instance.Data.n, instance.Data.E);
    end
    nodeStr = strjoin(cellstr(labels), '->');

    % 时间序列：起点用 startTimeMin，其余用 visits 匹配 seqIndex 的时间
    tVals = NaN(numel(route),1);
    tVals(1) = veh.startTimeMin;
    for i = 2:numel(route)
        vi = find_visit_by_seq_(veh, i);
        if isempty(vi)
            tVals(i) = NaN;
        else
            if vi.isCustomer
                tVals(i) = vi.tServiceStartMin;
            elseif vi.isStation
                tVals(i) = vi.tArriveMin;
            else
                tVals(i) = vi.tArriveMin;
            end
        end
    end
    tStr = strings(numel(tVals),1);
    for i = 1:numel(tVals)
        tStr(i) = string(min_to_hhmm_(tVals(i)));
    end
    timeStr = strjoin(cellstr(tStr), '->');
end

function vi = find_visit_by_seq_(veh, seqIndex)
    vi = [];
    if ~isfield(veh,'visits') || isempty(veh.visits)
        return;
    end
    for i = 1:numel(veh.visits)
        if isfield(veh.visits(i),'seqIndex') && veh.visits(i).seqIndex == seqIndex
            vi = veh.visits(i);
            return;
        end
    end
end

function label = node_label_table_541_(node, n, E)
    if node == 0
        label = '0';
        return;
    end
    if node >= (n+1) && node <= (n+E)
        label = sprintf('R%d', node - n);
        return;
    end
    label = sprintf('%d', node);
end

function order = vehicle_order_541_(names)
    n = numel(names);
    meta = zeros(n, 3); % [typeOrder, idxNum, origIdx]
    for i = 1:n
        s = upper(strtrim(char(string(names(i)))));
        t = 3;
        idxNum = i;
        if startsWith(s,'CV')
            t = 1;
            idxNum = str2double(regexprep(s,'[^0-9]',''));
        elseif startsWith(s,'EV')
            t = 2;
            idxNum = str2double(regexprep(s,'[^0-9]',''));
        end
        if ~isfinite(idxNum), idxNum = i; end
        meta(i,:) = [t, idxNum, i];
    end
    [~, ord] = sortrows(meta, [1 2 3]);
    order = ord(:).';
end

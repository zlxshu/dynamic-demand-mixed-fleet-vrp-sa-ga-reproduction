function fig = plot_dynamic_plan_541(instance, planNow, timelineNow, tNow, cfg)
% plot_dynamic_plan_541 - 优化路线图（全实线）
% 修改日志
% - v1 2026-01-24: 初版：全实线路线绘制。
% - v2 2026-01-26: 图例顺序/颜色映射固定；节点标注中文化（配送中心/客户/充电站）。
% - v3 2026-01-27: 图例仅保留“路径1..K”，不显示节点图例。
% - v4 2026-01-29: 图例条目数量=实际绘制的路径数量（跳过空驶/无移动的 [0->0]）；并修复颜色重复（避免 lines() 超过默认色循环导致重色）。

    if nargin < 5, cfg = struct(); end %#ok<NASGU>

    n = instance.Data.n;
    E = instance.Data.E;
    coord = instance.Data.coord;

    fig = figure('Color','w', 'WindowStyle','normal', 'Resize','on', 'NumberTitle','off'); hold on; box on;
    try set(fig,'ToolBar','figure','MenuBar','figure'); catch, end

    hDepot = plot(coord(1,1), coord(1,2), 'r^', 'MarkerFaceColor','r', 'MarkerSize',10, 'HandleVisibility','off');
    hCust = plot(coord(2:n+1,1), coord(2:n+1,2), 'bo', 'MarkerFaceColor','b', 'MarkerSize',5, 'HandleVisibility','off');
    hStation = plot(coord(n+2:n+E+1,1), coord(n+2:n+E+1,2), 'gs', 'MarkerFaceColor','g', 'MarkerSize',8, 'HandleVisibility','off');

    xy = coord(1:(n+E+1), :);
    labels = strings(n+E+1, 1);
    labels(1) = string(node_label_plot_541_(0,n,E));
    for i = 1:n
        labels(i+1) = string(node_label_plot_541_(i,n,E));
    end
    for r = 1:E
        labels(n+r+1) = string(node_label_plot_541_(n+r,n,E));
    end
    fw = repmat("normal", n+E+1, 1);
    fw(1) = "bold";
    fw(n+2:n+E+1) = "bold";
    fs = 8*ones(n+E+1, 1);
    fs(1) = 9;

    legH = [];
    legL = {};

    K = numel(planNow.detail);
    names = strings(K,1);
    for k = 1:K
        try names(k) = string(timelineNow.vehicles(k).name); catch, names(k) = "V"+k; end
    end
    order = vehicle_order_541_(names);

    pathIdx = 0;
    segs = zeros(0,4);
    for oi = 1:numel(order)
        k = order(oi);
        if k > numel(planNow.detail)
            continue;
        end
        route = planNow.detail(k).route(:).';
        route = route(isfinite(route));
        if numel(route) < 2
            continue;
        end
        if any(route < 0) || any(route > (n+E))
            continue;
        end
        % 跳过“无移动”的空车：避免图例出现 10 条但图上只有少数几条有效路线
        if numel(unique(route)) < 2
            continue;
        end
        vname = '';
        try vname = char(string(timelineNow.vehicles(k).name)); catch, vname = sprintf('V%d', k); end
        col = vehicle_color_541_(vname, k);
        xs = coord(route+1,1); ys = coord(route+1,2);
        h = plot(xs, ys, '-', 'Color', col, 'LineWidth', 2.2, 'HandleVisibility','off');
        if numel(xs) >= 2
            segs = [segs; [xs(1:end-1) ys(1:end-1) xs(2:end) ys(2:end)]]; %#ok<AGROW>
        end
        pathIdx = pathIdx + 1;
        hLeg = plot(nan, nan, '-', 'Color', col, 'LineWidth', 2.2);
        hLeg.DisplayName = sprintf('路径%d', pathIdx);
        legH(end+1) = hLeg; %#ok<AGROW>
        legL{end+1} = hLeg.DisplayName; %#ok<AGROW>
    end

    place_labels_no_overlap(gca, xy, labels, struct('fontSize', fs, 'fontWeight', fw, 'backgroundColor', 'none', 'margin', 1, 'avoidSegments', segs));

    title(sprintf('时刻 %s 优化路线', min_to_hhmm_(tNow)), 'Interpreter','none');
    if ~isempty(legH)
        legend(legH, legL, 'Location','best', 'Interpreter','none');
    end
    apply_plot_style(fig, findall(fig,'Type','axes'), 'default');
end

function c = vehicle_color_541_(name, fallbackIdx)
    % NOTE: lines(>7) 会复用默认 ColorOrder，容易出现重色；这里使用不重复调色板
    cols = [];
    try
        if exist('turbo','file') == 2
            cols = turbo(12);
        end
    catch
        cols = [];
    end
    if isempty(cols)
        cols = hsv(12);
    end
    t = upper(strtrim(char(string(name))));
    idxNum = NaN;
    if startsWith(t,'CV')
        idxNum = str2double(regexprep(t,'[^0-9]',''));
        if ~isfinite(idxNum), idxNum = fallbackIdx; end
        base = 1; span = 6;
        c = cols(base + mod(round(idxNum)-1, span), :);
        return;
    end
    if startsWith(t,'EV')
        idxNum = str2double(regexprep(t,'[^0-9]',''));
        if ~isfinite(idxNum), idxNum = fallbackIdx; end
        base = 7; span = 6;
        c = cols(base + mod(round(idxNum)-1, span), :);
        return;
    end
    if nargin < 2 || ~isfinite(fallbackIdx), fallbackIdx = 1; end
    c = cols(mod(round(fallbackIdx)-1, size(cols,1)) + 1, :);
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

function label = node_label_plot_541_(node, n, E)
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

function s = min_to_hhmm_(tMin)
    h = floor(tMin/60);
    m = round(tMin - 60*h);
    s = sprintf('%02d:%02d', h, m);
end

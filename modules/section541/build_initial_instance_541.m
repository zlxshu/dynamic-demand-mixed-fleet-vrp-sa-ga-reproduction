function instance = build_initial_instance_541(ctx, events, recvWindow, cfg)
% build_initial_instance_541 - 构建 section_541 的“可变实例”（不写回 ctx）
% 设计要点：
% - 为保持客户编号与事件 customerId 一致，实例客户数 n 取 max(ctx.Data.n, max(event.customerId))
% - 充电站集合固定为 ctx.Data.E，并始终放在 customers 之后（节点编号 R1..RE）
% - 动态新增客户在首次出现前 demand=0（inactive），出现后再由事件激活

    if nargin < 4, cfg = struct(); end %#ok<NASGU>

    nBase = ctx.Data.n;
    E = ctx.Data.E;

    maxId = nBase;
    try
        ids = events.customerId;
        ids = ids(isfinite(ids));
        if ~isempty(ids)
            maxId = max(maxId, max(ids));
        end
    catch
    end
    nAll = round(maxId);

    % Data arrays
    coord = NaN(1 + nAll + E, 2);
    q = zeros(1 + nAll + E, 1);
    LT = NaN(1 + nAll + E, 1);
    RT = NaN(1 + nAll + E, 1);

    % depot
    coord(1,:) = ctx.Data.coord(1,:);
    q(1) = ctx.Data.q(1);
    LT(1) = ctx.Data.LT(1);
    RT(1) = ctx.Data.RT(1);

    % customers (1..nBase)
    for c = 1:nBase
        coord(c+1,:) = ctx.Data.coord(c+1,:);
        q(c+1) = ctx.Data.q(c+1);
        LT(c+1) = ctx.Data.LT(c+1);
        RT(c+1) = ctx.Data.RT(c+1);
    end

    % stations copy (old stations: nBase+1..nBase+E)
    for r = 1:E
        oldNode = nBase + r;
        newNode = nAll + r;
        coord(newNode+1,:) = ctx.Data.coord(oldNode+1,:);
        q(newNode+1) = ctx.Data.q(oldNode+1);
        LT(newNode+1) = ctx.Data.LT(oldNode+1);
        RT(newNode+1) = ctx.Data.RT(oldNode+1);
    end

    % fill attributes from events (coords / TW) for customers up to nAll
    try
        for i = 1:height(events)
            cid = events.customerId(i);
            if ~isfinite(cid) || cid < 1 || cid > nAll
                continue;
            end
            x = events.x(i);
            y = events.y(i);
            if isfinite(x) && isfinite(y)
                if any(~isfinite(coord(cid+1,:)))
                    coord(cid+1,:) = [x y];
                end
            end
            ltw = events.LTW(i);
            rtw = events.RTW(i);
            if isfinite(ltw) && ~isfinite(LT(cid+1))
                LT(cid+1) = ltw;
            end
            if isfinite(rtw) && ~isfinite(RT(cid+1))
                RT(cid+1) = rtw;
            end
        end
    catch
    end

    % dynamic-add customers：初始需求置 0（避免进入初始方案）
    try
        addIds = events.customerId(strcmpi(events.eventType, 'add'));
        addIds = unique(addIds(isfinite(addIds) & addIds>=1 & addIds<=nAll));
        for i = 1:numel(addIds)
            q(addIds(i)+1) = 0;
        end
    catch
    end

    % 兜底：未提供时间窗的客户，使用全窗
    LT(~isfinite(LT)) = 0;
    RT(~isfinite(RT)) = 1440;

    Data = struct();
    Data.coord = coord;
    Data.q = q;
    Data.LT = LT;
    Data.RT = RT;
    Data.n = nAll;
    Data.E = E;
    Data.ST = ctx.Data.ST;
    Data.D = pairwise_dist_fast(coord);

    instance = struct();
    instance.Data = Data;
    instance.recvWindow = recvWindow;
    instance.meta = struct('nBase', nBase, 'nAll', nAll, 'E', E);

    instance.ActiveCustomers = (q(2:nAll+1) > 0);
    instance.CustomerStatus = strings(nAll, 1);
    instance.CustomerStatus(instance.ActiveCustomers) = "active";
    instance.CustomerStatus(~instance.ActiveCustomers) = "inactive";

    % 自检：所有 active 客户必须有坐标
    activeIds = find(instance.ActiveCustomers);
    if ~isempty(activeIds)
        bad = activeIds(any(~isfinite(coord(activeIds+1,:)), 2));
        if ~isempty(bad)
            error('section_541:missingCoord', 'active customers missing coord: %s', mat2str(bad(:).'));
        end
    end
end

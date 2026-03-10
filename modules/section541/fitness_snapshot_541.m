function [fx, feasible, ch_fixed, detail] = fitness_snapshot_541(ch, G)
% 修改日志
% - v2 2026-01-27: 未出发车辆 startTimeMin 不再沿用上轮计划；由 tNow 与首客户 LT 回推得到（支持可前移/可后移且可在后续更新重规划）。
% - v3 2026-01-27: 适应度评估改用 simulate_timeline_summary_541（轻量仿真）替代 simulate_timeline_541（结构体/visits/steps），显著降低 NP*MaxGen 开销；不改变模型口径与约束判定。
% - v4 2026-01-29: 载重约束按“整条路径总需求”计（含已服务客户），匹配论文表5.7/5.9 的“出发车辆负载”语义；避免把已服务客户当作释放容量从而错误允许插入新需求。
% - v5 2026-01-29: (已撤回) paper_repro 下曾禁止“已出发车辆接收新增客户”，但论文原文未给出该硬规则；现仅保留“冻结段不变 + 出发载重口径”以驱动是否需要派新车的自然结果。
% - v6 2026-01-30: 论文 5.4.1 对齐：未出发车辆（prefix=[0]/phase=not_started）可拼接待配送；仅“已回库”（prefix 中间有非 0 且结尾 0）才封口不可接客，修复可行=0/200（与 bak_20260129_0421 的 prefixClosed 逻辑一致）。
% - v7 2026-01-30: 移除 debug 日志（seed/feasible 复核已完成）。
% - v8 2026-01-31: paper_repro 增加“待配送客户不跨车重分配”惩罚（实现选择；论文 5.4.1 未规定）。
% - v9 2026-01-31: reassign 改为软惩罚，不作为可行性硬约束；可行解也纳入 reassign 惩罚。
% - v10 2026-01-31: 严丝合缝审查：论文无“重分配”惩罚，paper_repro 下 w_reassign=0 以严格对齐论文。
% - v11 2026-02-01: reassign 惩罚仅在 generalize 启用(=20)，paper_repro 维持 0。
% fitness_snapshot_541 - 541 动态快照适应度（冻结段不变；待配送段由 GSAA 排序）
% 修改日志
% - v1 2026-01-27: 新增，支持冻结前缀+待配送序列评估；EV 充电插站；容量/时间窗/电量违规统计。
    P_BIG = 1e9;
    P_BAD = 1e7;

    snap = struct();
    if isfield(G,'snapshot'), snap = G.snapshot; end
    fullG = snap.fullG;
    pendingIds = snap.pendingIds;
    vehInfo = snap.vehInfo;
    tNow = NaN;
    try tNow = snap.tNow; catch, tNow = NaN; end
    cfg = snap.cfg;

    n = G.n;
    K = G.K;
    ch_fixed = repair_chromosome_deterministic(ch, G);

    % 空待配送：直接返回冻结路线
    if n <= 0
        detail = build_detail_from_vehinfo_(vehInfo);
        sum = simulate_timeline_summary_541(fullG, detail, cfg);
        fx = sum.totalCost;
        feasible = true;
        return;
    end

    perm = ch_fixed(1:n);
    cuts = ch_fixed(n+1:end);
    cuts2 = [cuts, n];

    routesPending = cell(K,1);
    st = 1;
    for k = 1:K
        ed = cuts2(k);
        if st > ed
            routesPending{k} = [];
        else
            routesPending{k} = perm(st:ed);
        end
        st = ed + 1;
    end

    % 原待配送客户→原车辆映射（仅当 generalize 启用惩罚时使用；论文 5.4.1 未规定此惩罚）
    origOwner = zeros(fullG.n, 1);
    if isfield(cfg,'Mode') && strcmp(cfg.Mode, 'generalize')
        try
            for k = 1:K
                ids = [];
                try ids = vehInfo(k).pendingSeed(:); catch, ids = []; end
                ids = ids(isfinite(ids) & ids>=1 & ids<=fullG.n);
                for ii = 1:numel(ids)
                    cid = ids(ii);
                    if origOwner(cid) == 0
                        origOwner(cid) = k;
                    end
                end
            end
        catch
            origOwner(:) = 0;
        end
    end

    detail = repmat(struct('route',[],'startTimeMin',0), K, 1);
    vio = struct('tw',0,'bat',0,'cap',0,'unreach',0,'reassign',0);
    for k = 1:K
        info = vehInfo(k);
        prefix = normalize_prefix_(info.prefixNodes);
        tailIdx = routesPending{k};
        tailIds = pendingIds(tailIdx);
        tailIds = tailIds(isfinite(tailIds) & tailIds>=1 & tailIds<=fullG.n);

        % generalize：惩罚“原待配送客户”被分配到不同车辆
        if any(origOwner)
            try
                for ii = 1:numel(tailIds)
                    cid = tailIds(ii);
                    ok = (origOwner(cid) == 0) || (origOwner(cid) == k);
                    if ~ok
                        vio.reassign = vio.reassign + 1;
                    end
                end
            catch
            end
        end

        if ~info.available && ~isempty(tailIds)
            vio.unreach = vio.unreach + numel(tailIds);
            tailIds = [];
        end

        % 论文 5.4.1：未出发车辆可接客，已回库车辆不可再接客（与 fitness_snapshot_541_bak_20260129_0421 v4 一致）
        prefixClosed = false;
        try
            if ~isempty(prefix) && prefix(end) == 0
                if isfield(info,'phase') && strcmp(info.phase, 'not_started')
                    prefixClosed = false;
                else
                    % 已回库且前缀存在非 0 节点：视为本趟已结束（不允许再拼接新任务）
                    if numel(prefix) > 1 && any(prefix(2:end-1) ~= 0)
                        prefixClosed = true;
                    end
                end
            end
        catch
            prefixClosed = false;
        end

        if prefixClosed
            if ~isempty(tailIds)
                vio.unreach = vio.unreach + numel(tailIds);
            end
            route = prefix;
        else
            route = [prefix(:).' tailIds(:).' 0];
        end
        route = normalize_route_(route);

        if info.isEV && isfield(fullG,'allowCharging') && fullG.allowCharging
            [route, addVio] = insert_charging_after_prefix_(route, numel(prefix), info.batteryEndKWh, fullG);
            vio.unreach = vio.unreach + addVio;
        end

        detail(k).route = route;
        startTimeMin = info.startTimeMin;
        try
            if isfield(info,'phase') && strcmp(info.phase, 'not_started')
                startTimeMin = depart_time_not_started_541_(route, tNow, fullG, k);
            end
        catch
        end
        detail(k).startTimeMin = startTimeMin;
    end

    sum = simulate_timeline_summary_541(fullG, detail, cfg);
    vio.tw = sum.vioTw;
    vio.bat = sum.vioBat;
    vio.cap = cap_violation_from_detail_(vehInfo, detail, pendingIds, fullG);

    % === reassign 惩罚（paper_repro 严格对齐论文 5.4.1）===
    % 论文 5.4.1 原文："出发车辆的负载无法满足动态顾客需求，因此配送中心重新派出一辆电动汽车"
    % 即：派新车的原因是"负载/时间窗约束"，论文全文未出现"重分配""跨车重分配"惩罚概念。
    % 
    % paper_repro 模式：w_reassign = 0，严格对齐论文，不施加重分配惩罚；
    % generalize 模式：w_reassign = 20，作为可选的实现增强（减少不必要的跨车调度）。
    % ============================================
    w_reassign = 0;
    try
        if isfield(cfg,'Mode') && strcmp(cfg.Mode, 'generalize')
            w_reassign = 20.0;   % generalize 功能：跨车重分配惩罚（论文未规定）
        end
    catch
        w_reassign = 0;
    end
    vioScore = w_reassign * vio.reassign;
    if (vio.unreach <= 1e-9) && (vio.tw <= 1e-9) && (vio.bat <= 1e-9) && (vio.cap <= 1e-9)
        fx = sum.totalCost + w_reassign * vio.reassign;
        feasible = true;
    else
        % 论文未给出违反约束时的罚权重，此处为算法稳定性需要而设
        w_unreach = 10.0;
        w_tw = 3.0;
        w_cap = 2.0;
        w_bat = 1.5;
        vioScore = vioScore + w_unreach*vio.unreach + w_tw*vio.tw + w_cap*vio.cap + w_bat*vio.bat;
        fx = P_BIG + P_BAD * (1 + vioScore);
        feasible = false;
    end
end

% ========================= helpers =========================
function detail = build_detail_from_vehinfo_(vehInfo)
    K = numel(vehInfo);
    detail = repmat(struct('route',[0 0],'startTimeMin',0), K, 1);
    for k = 1:K
        route = normalize_route_(vehInfo(k).prefixNodes);
        detail(k).route = route;
        detail(k).startTimeMin = vehInfo(k).startTimeMin;
    end
end

function prefix = normalize_prefix_(prefix)
    if isempty(prefix)
        prefix = [0];
        return;
    end
    prefix = prefix(:).';
    prefix = prefix(isfinite(prefix));
    if isempty(prefix)
        prefix = [0];
        return;
    end
    if prefix(1) ~= 0
        prefix = [0 prefix];
    end
end

function route = normalize_route_(route)
    if isempty(route)
        route = [0 0];
        return;
    end
    route = route(isfinite(route));
    if isempty(route)
        route = [0 0];
        return;
    end
    if route(1) ~= 0
        route = [0 route(:).'];
    else
        route = route(:).';
    end
    if route(end) ~= 0
        route = [route 0];
    end
end

function startTimeMin = depart_time_not_started_541_(route, tNow, G, k)
    if nargin < 2 || ~isfinite(tNow)
        tNow = 0;
    end
    startTimeMin = tNow;
    if isempty(route) || numel(route) < 2
        return;
    end

    % 找到首个客户（跳过 0/充电站）
    firstCus = NaN;
    for i = 2:numel(route)
        node = route(i);
        if ~isfinite(node) || node == 0
            continue;
        end
        if is_station(node, G)
            continue;
        end
        if node >= 1 && node <= G.n
            firstCus = node;
            break;
        end
    end
    if ~isfinite(firstCus)
        return;
    end

    try
        lt = G.LT(firstCus+1);
        d = G.D(1, firstCus+1);
        tTravel = d / max(G.Speed(k), 1e-12);
        if isfinite(lt) && isfinite(tTravel)
            % 出发可后移到“到达首客恰好 LT”，不早于 tNow
            startTimeMin = max(startTimeMin, lt - tTravel);
        end
    catch
    end
    startTimeMin = max(startTimeMin, tNow);
end

function [route, vioUnreach] = insert_charging_after_prefix_(route, prefixLen, batteryStart, G)
    vioUnreach = 0;
    if isempty(route) || numel(route) < 2
        return;
    end
    if prefixLen < 1
        prefixLen = 1;
    end
    if prefixLen > numel(route)-1
        return;
    end
    if ~isfinite(batteryStart)
        batteryStart = G.B0;
    end
    battery = batteryStart;
    insertCount = 0;
    insertMax = 120;

    i = prefixLen;
    while i <= numel(route)-1
        fromNode = route(i);
        toNode = route(i+1);
        if fromNode == toNode
            i = i + 1;
            continue;
        end
        d = G.D(fromNode+1, toNode+1);
        battAfter = battery - d * G.gE;
        minAfter = min_soc_required(toNode, G);
        if battAfter < minAfter - 1e-9
            if insertCount >= insertMax
                vioUnreach = vioUnreach + 1;
                break;
            end
            if is_station(fromNode, G)
                vioUnreach = vioUnreach + 1;
                break;
            end
            [st, ok] = choose_best_station_battery(fromNode, toNode, battery, G);
            if ~ok
                vioUnreach = vioUnreach + 1;
                break;
            end
            route = [route(1:i) st route(i+1:end)];
            insertCount = insertCount + 1;
            d1 = G.D(fromNode+1, st+1);
            battery = battery - d1 * G.gE;
            if battery < min_soc_required(st, G) - 1e-9
                vioUnreach = vioUnreach + 1;
                break;
            end
            battery = G.B0;
            i = i + 1;
            continue;
        else
            battery = battAfter;
            if is_station(toNode, G)
                battery = G.B0;
            end
        end
        i = i + 1;
    end
end

function vcap = cap_violation_from_detail_(vehInfo, detail, pendingIds, Gfull)
    vcap = 0;
    if isempty(detail)
        return;
    end
    for k = 1:min(numel(vehInfo), numel(detail))
        route = [];
        try route = detail(k).route(:); catch, route = []; end
        if isempty(route)
            continue;
        end
        % 载重按“整条路径总需求”计（含已服务/冻结客户），匹配论文表5.7/5.9 的出发负载语义。
        cus = route(route>=1 & route<=Gfull.n);
        routeLoad = 0;
        if ~isempty(cus)
            try
                routeLoad = sum(Gfull.q(cus+1));
            catch
                routeLoad = 0;
            end
        end
        cap = Gfull.Qmax(k);
        if isfinite(cap) && (routeLoad > cap)
            vcap = vcap + (routeLoad - cap) / max(cap, 1);
        end
    end
end

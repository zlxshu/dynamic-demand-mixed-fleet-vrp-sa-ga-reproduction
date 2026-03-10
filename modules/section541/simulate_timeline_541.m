function timeline = simulate_timeline_541(G, detail, cfg)
% simulate_timeline_541 - 按当前模型口径仿真路线时间线（含 EV 电量/充电）
% 输出用于：
% - 冻结切分（travel/service/charge 的起止）
% - 生成方案表（节点+时间/里程）
% 修改日志
% - v1 2026-01-24: 初版：输出 steps/visits/summary，用于冻结与方案表。
% - v2 2026-01-25: 输出每个客户的服务起始/结束时间（customerServiceStartMin/EndMin），用于取消失败边界判定。
% - v3 2026-01-26: 节点标签中文化（配送中心/客户/充电站），确保图表与表格口径一致。

    if nargin < 3, cfg = struct(); end %#ok<NASGU>

    if isempty(detail)
        timeline = struct('vehicles', struct([]), 'servedCustomers', [], 'summary', struct());
        return;
    end

    n = G.n;
    E = G.E;

    vehicles = repmat(struct(), numel(detail), 1);
    servedAll = [];

    % 每个客户的服务起止时间（min）；未服务为 NaN
    customerServiceStartMin = NaN(n, 1);
    customerServiceEndMin = NaN(n, 1);
    customerServiceVehicle = strings(n, 1);
    total = struct('startCost',0,'driveCost',0,'fuelCost',0,'elecCost',0,'carbonCost',0,'totalCost',0,'distanceKm',0,'nCharge',0,'chargeE',0,'chargeTimeMin',0, ...
        'vioTw',0,'vioBat',0);

    for k = 1:numel(detail)
        isEV = false;
        try isEV = logical(G.isEV(k)); catch, end

        seq = [];
        try seq = detail(k).route; catch, end
        if isempty(seq)
            seq = [0 0];
        end
        if seq(1) ~= 0
            seq = [0 seq(:).'];
        else
            seq = seq(:).';
        end
        if seq(end) ~= 0
            seq = [seq 0];
        end

        vname = vehicle_name_(k, G);
        startTimeMin = 0;
        try
            if isfield(detail(k),'startTimeMin') && isfinite(detail(k).startTimeMin)
                startTimeMin = double(detail(k).startTimeMin);
            end
        catch
        end

        % 注意：出发时刻由上层求解器显式给出（detail(k).startTimeMin），本函数不再“自动回推”，避免冻结段时间线漂移。

        time = startTimeMin;
        dist = 0;
        loadKg = route_load_kg_(seq, G);
        battery = NaN;
        if isEV
            battery = G.B0;
        end

        steps = struct([]);
        visits = struct([]);
        nCharge = 0;
        chargeE = 0;
        chargeTimeMin = 0;
        vio = struct('tw',0,'bat',0,'unreach',0);

        % 初始 idle（0->0）
        if startTimeMin > 0
            steps = append_step_(steps, 0, 0, 'idle', 0, startTimeMin, 0, loadKg, battery, battery, 1, 1, node_label_(0,n,E), node_label_(0,n,E));
        end

        for i = 1:(numel(seq)-1)
            fromNode = seq(i);
            toNode = seq(i+1);
            fromIdx = fromNode + 1;
            toIdx = toNode + 1;

            d = 0;
            try d = G.D(fromIdx, toIdx); catch, end

            % travel
            tStart = time;
            tEnd = time + d / G.Speed(k);
            bat0 = battery;
            bat1 = battery;
            if isEV
                bat1 = bat0 - d * G.gE;
            end
            steps = append_step_(steps, fromNode, toNode, 'travel', tStart, tEnd, d, loadKg, bat0, bat1, i, i+1, node_label_(fromNode,n,E), node_label_(toNode,n,E));

            time = tEnd;
            dist = dist + d;
            battery = bat1;

            % EV 电量边界自检（不抛错，只统计；真正可行性由求解器/repair 保证）
            if isEV
                try
                    minAfter = min_soc_required(toNode, G);
                    if isfinite(minAfter) && battery < minAfter - 1e-9
                        vio.bat = vio.bat + (minAfter - battery);
                    end
                catch
                end
            end

            % arrive node
            if toNode == 0
                % depot end
                visits = append_visit_(visits, toNode, time, time, time, time, battery, battery, false, false, node_label_(toNode,n,E), i+1);
                continue;
            end

            if is_station_node_(toNode, n, E)
                % charging station
                if isEV && isfield(G,'allowCharging') && G.allowCharging
                    needE = max(G.B0 - battery, 0);
                    rate = G.rg / 60; % kWh/min
                    tChg = needE / max(rate, 1e-12);
                    if tChg > 0
                        steps = append_step_(steps, toNode, toNode, 'charge', time, time + tChg, 0, loadKg, battery, G.B0, i+1, i+1, node_label_(toNode,n,E), node_label_(toNode,n,E));
                    end
                    nCharge = nCharge + 1;
                    chargeE = chargeE + needE;
                    chargeTimeMin = chargeTimeMin + tChg;
                    battery = G.B0;
                    time = time + tChg;
                end
                visits = append_visit_(visits, toNode, time, time, time, time, battery, battery, false, true, node_label_(toNode,n,E), i+1);
                continue;
            end

            % customer: time window wait + service
            tArrive = time;
            tServiceStart = tArrive;
            try
                lt = G.LT(toNode+1);
                rt = G.RT(toNode+1);
                if isfinite(rt) && tServiceStart > rt + 1e-9
                    vio.tw = vio.tw + (tServiceStart - rt);
                end
                if isfinite(lt) && tServiceStart < lt
                    steps = append_step_(steps, toNode, toNode, 'wait', tServiceStart, lt, 0, loadKg, battery, battery, i+1, i+1, node_label_(toNode,n,E), node_label_(toNode,n,E));
                    tServiceStart = lt;
                end
            catch
            end

            tServiceEnd = tServiceStart + G.ST;
            steps = append_step_(steps, toNode, toNode, 'service', tServiceStart, tServiceEnd, 0, loadKg, battery, battery, i+1, i+1, node_label_(toNode,n,E), node_label_(toNode,n,E));
            time = tServiceEnd;

            visits = append_visit_(visits, toNode, tArrive, tServiceStart, tServiceEnd, time, battery, battery, true, false, node_label_(toNode,n,E), i+1);
            servedAll(end+1,1) = toNode; %#ok<AGROW>

            % 记录客户服务起止（用于取消/变更失败边界）；同一客户若重复出现，取最早服务起始
            if toNode >= 1 && toNode <= n
                if ~isfinite(customerServiceStartMin(toNode)) || tServiceStart < customerServiceStartMin(toNode)
                    customerServiceStartMin(toNode) = tServiceStart;
                    customerServiceEndMin(toNode) = tServiceEnd;
                    customerServiceVehicle(toNode) = string(vname);
                end
            end
        end

        cost = route_cost_breakdown_(k, isEV, dist, loadKg, nCharge, chargeE, G);

        vehicles(k).k = k;
        vehicles(k).name = vname;
        vehicles(k).isEV = isEV;
        vehicles(k).route = seq;
        vehicles(k).startTimeMin = startTimeMin;
        vehicles(k).endTimeMin = time;
        vehicles(k).distanceKm = dist;
        vehicles(k).loadKg = loadKg;
        vehicles(k).nCharge = nCharge;
        vehicles(k).chargeE = chargeE;
        vehicles(k).chargeTimeMin = chargeTimeMin;
        vehicles(k).steps = steps;
        vehicles(k).visits = visits;
        vehicles(k).cost = cost;
        vehicles(k).vio = vio;

        total.startCost = total.startCost + cost.startCost;
        total.driveCost = total.driveCost + cost.driveCost;
        total.fuelCost = total.fuelCost + cost.fuelCost;
        total.elecCost = total.elecCost + cost.elecCost;
        total.carbonCost = total.carbonCost + cost.carbonCost;
        total.totalCost = total.totalCost + cost.totalCost;
        total.distanceKm = total.distanceKm + dist;
        total.nCharge = total.nCharge + nCharge;
        total.chargeE = total.chargeE + chargeE;
        total.chargeTimeMin = total.chargeTimeMin + chargeTimeMin;
        total.vioTw = total.vioTw + vio.tw;
        total.vioBat = total.vioBat + vio.bat;
    end

    timeline = struct();
    timeline.vehicles = vehicles;
    timeline.servedCustomers = unique(servedAll(isfinite(servedAll) & servedAll>=1));
    timeline.customerServiceStartMin = customerServiceStartMin;
    timeline.customerServiceEndMin = customerServiceEndMin;
    timeline.customerServiceVehicle = customerServiceVehicle;
    timeline.summary = total;
end

% ========================= helpers =========================
function vname = vehicle_name_(k, G)
    try
        if isfield(G,'nCV') && k <= G.nCV
            vname = sprintf('CV%d', k);
            return;
        end
        if isfield(G,'nCV')
            vname = sprintf('EV%d', k - G.nCV);
            return;
        end
    catch
    end
    vname = sprintf('V%d', k);
end

function tf = is_station_node_(node, n, E)
    tf = (node >= (n+1)) && (node <= (n+E));
end

function label = node_label_(node, n, E)
    if node == 0
        label = '配送中心0';
        return;
    end
    if node >= (n+1) && node <= (n+E)
        label = sprintf('充电站R%d', node - n);
        return;
    end
    label = sprintf('客户%d', node);
end

function loadKg = route_load_kg_(seq, G)
    loadKg = 0;
    try
        cus = seq(seq>=1 & seq<=G.n);
        if isempty(cus)
            loadKg = 0;
        else
            loadKg = sum(G.q(cus+1));
        end
    catch
        loadKg = 0;
    end
end

function cost = route_cost_breakdown_(k, isEV, dist, loadKg, nCharge, chargeE, G)
    cost = struct('startCost',0,'driveCost',0,'fuelCost',0,'elecCost',0,'carbonCost',0,'totalCost',0, ...
        'nCharge', nCharge, 'chargeE', chargeE);

    used = dist > 1e-9 || loadKg > 0;
    if used
        try cost.startCost = G.c(k); catch, cost.startCost = 0; end
    end
    try cost.driveCost = G.m(k) * dist; catch, cost.driveCost = 0; end

    if isEV
        cost.elecCost = chargeE * G.elec_price;
        cost.fuelCost = 0;
        cost.carbonCost = 0;
    else
        % CV: CMEM 口径与 decode 保持一致
        fuel_L = 0;
        try
            cm = G.CMEM;
            v_km_min = G.Speed(k);
            v_mps = v_km_min * (1000/60);
            time_s = (dist / max(v_km_min, 1e-12)) * 60;

            m_total = cm.m_empty + loadKg;
            F_roll = m_total * 9.81 * cm.Cr;
            F_aero = 0.5 * cm.rho_air * cm.CdA * v_mps^2;
            P_kW = (F_roll + F_aero) * v_mps / 1000;
            P = P_kW;
            FR_gps = ( P/(cm.eta*cm.eps) + cm.lam*cm.H*cm.V ) / (cm.mu*cm.phi);
            fuel_g = FR_gps * time_s;
            fuel_L = (fuel_g/1000) / cm.rho_fuel;
        catch
            fuel_L = 0;
        end
        try cost.fuelCost = fuel_L * G.fuel_price; catch, end
        try cost.carbonCost = fuel_L * G.CMEM.eCO2 * G.carbon_price; catch, end
    end

    cost.totalCost = cost.startCost + cost.driveCost + cost.fuelCost + cost.elecCost + cost.carbonCost;
end

function steps = append_step_(steps, fromNode, toNode, phase, tStart, tEnd, distKm, loadKg, b0, b1, idxFrom, idxTo, fromLabel, toLabel)
    s = struct();
    s.fromNode = fromNode;
    s.toNode = toNode;
    s.phase = phase;
    s.tStartMin = tStart;
    s.tEndMin = tEnd;
    s.distKm = distKm;
    s.loadKg = loadKg;
    s.batStartKWh = b0;
    s.batEndKWh = b1;
    s.seqIndexFrom = idxFrom;
    s.seqIndexTo = idxTo;
    s.fromNodeLabel = fromLabel;
    s.toNodeLabel = toLabel;
    if isempty(steps)
        steps = s;
    else
        steps(end+1) = s; %#ok<AGROW>
    end
end

function visits = append_visit_(visits, node, tArrive, tStart, tEnd, tDepart, batArr, batDep, isCustomer, isStation, nodeLabel, seqIndex)
    v = struct();
    v.node = node;
    v.nodeLabel = nodeLabel;
    v.seqIndex = seqIndex;
    v.tArriveMin = tArrive;
    v.tServiceStartMin = tStart;
    v.tServiceEndMin = tEnd;
    v.tDepartMin = tDepart;
    v.batArriveKWh = batArr;
    v.batDepartKWh = batDep;
    v.isCustomer = isCustomer;
    v.isStation = isStation;
    if isempty(visits)
        visits = v;
    else
        visits(end+1) = v; %#ok<AGROW>
    end
end

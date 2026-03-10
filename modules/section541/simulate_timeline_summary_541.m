function summary = simulate_timeline_summary_541(G, detail, cfg)
% simulate_timeline_summary_541 - 轻量时间线仿真（仅用于适应度评估；不构造 steps/visits 结构）
% 说明：
% - 目标：与 simulate_timeline_541 的口径一致，但显著降低每次 fitness 调用的开销（避免 NP*MaxGen 级别结构体追加）。
% - 仅返回 summary：成本分项、总成本、里程、充电统计、时间窗/电量违规统计。
%
% 修改日志
% - v1 2026-01-27: 新增（section_541 专用）；保持 EV 逻辑顺序：先行驶→扣电→到达节点再判定/充电。

    if nargin < 3, cfg = struct(); end %#ok<NASGU>

    summary = struct('startCost',0,'driveCost',0,'fuelCost',0,'elecCost',0,'carbonCost',0,'totalCost',0,'distanceKm',0, ...
        'nCharge',0,'chargeE',0,'chargeTimeMin',0,'vioTw',0,'vioBat',0);

    if isempty(detail)
        return;
    end

    n = G.n;
    E = G.E;

    for k = 1:numel(detail)
        isEV = false;
        try isEV = logical(G.isEV(k)); catch, end

        route = [];
        try route = detail(k).route; catch, end
        if isempty(route)
            route = [0 0];
        end
        route = route(:).';
        route = route(isfinite(route));
        if isempty(route)
            route = [0 0];
        end
        if route(1) ~= 0
            route = [0 route];
        end
        if route(end) ~= 0
            route = [route 0];
        end

        startTimeMin = 0;
        try
            if isfield(detail(k),'startTimeMin') && isfinite(detail(k).startTimeMin)
                startTimeMin = double(detail(k).startTimeMin);
            end
        catch
            startTimeMin = 0;
        end

        time = startTimeMin;
        dist = 0;

        loadKg = 0;
        try
            cus = route(route>=1 & route<=n);
            if ~isempty(cus)
                loadKg = sum(G.q(cus+1));
            end
        catch
            loadKg = 0;
        end

        battery = NaN;
        if isEV
            battery = G.B0;
        end

        nCharge = 0;
        chargeE = 0;
        chargeTimeMin = 0;
        vioTw = 0;
        vioBat = 0;

        allowCharging = false;
        try
            allowCharging = isEV && isfield(G,'allowCharging') && logical(G.allowCharging);
        catch
            allowCharging = false;
        end

        for i = 1:(numel(route)-1)
            fromNode = route(i);
            toNode = route(i+1);
            if ~isfinite(fromNode) || ~isfinite(toNode)
                continue;
            end
            if fromNode < 0 || fromNode > (n+E) || toNode < 0 || toNode > (n+E)
                continue;
            end

            d = 0;
            try d = G.D(fromNode+1, toNode+1); catch, d = 0; end

            % travel: time + dist
            tTravel = 0;
            try tTravel = d / max(G.Speed(k), 1e-12); catch, tTravel = 0; end
            time = time + tTravel;
            dist = dist + d;

            % EV: discharge then check after-arrival min SOC
            if isEV
                batAfter = battery - d * G.gE;
                battery = batAfter;
                try
                    minAfter = min_soc_required(toNode, G);
                    if isfinite(minAfter) && battery < minAfter - 1e-9
                        vioBat = vioBat + (minAfter - battery);
                    end
                catch
                end
            end

            if toNode == 0
                continue;
            end

            % station: charge after arrival (if enabled)
            if is_station(toNode, G)
                if allowCharging
                    try
                        needE = max(G.B0 - battery, 0);
                        rate = G.rg / 60; % kWh/min
                        tChg = needE / max(rate, 1e-12);
                        if tChg > 0
                            nCharge = nCharge + 1;
                            chargeE = chargeE + needE;
                            chargeTimeMin = chargeTimeMin + tChg;
                            battery = G.B0;
                            time = time + tChg;
                        end
                    catch
                    end
                end
                continue;
            end

            % customer: time window + service
            try
                lt = G.LT(toNode+1);
                rt = G.RT(toNode+1);
                if isfinite(rt) && time > rt + 1e-9
                    vioTw = vioTw + (time - rt);
                end
                if isfinite(lt) && time < lt
                    time = lt;
                end
            catch
            end
            try
                time = time + G.ST;
            catch
            end
        end

        % cost breakdown (same口径 as simulate_timeline_541)
        startCost = 0; driveCost = 0; fuelCost = 0; elecCost = 0; carbonCost = 0;
        used = dist > 1e-9 || loadKg > 0;
        if used
            try startCost = G.c(k); catch, startCost = 0; end
        end
        try driveCost = G.m(k) * dist; catch, driveCost = 0; end

        if isEV
            try elecCost = chargeE * G.elec_price; catch, elecCost = 0; end
            fuelCost = 0;
            carbonCost = 0;
        else
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
            try fuelCost = fuel_L * G.fuel_price; catch, fuelCost = 0; end
            try carbonCost = fuel_L * G.CMEM.eCO2 * G.carbon_price; catch, carbonCost = 0; end
        end

        totalCost = startCost + driveCost + fuelCost + elecCost + carbonCost;

        summary.startCost = summary.startCost + startCost;
        summary.driveCost = summary.driveCost + driveCost;
        summary.fuelCost = summary.fuelCost + fuelCost;
        summary.elecCost = summary.elecCost + elecCost;
        summary.carbonCost = summary.carbonCost + carbonCost;
        summary.totalCost = summary.totalCost + totalCost;
        summary.distanceKm = summary.distanceKm + dist;
        summary.nCharge = summary.nCharge + nCharge;
        summary.chargeE = summary.chargeE + chargeE;
        summary.chargeTimeMin = summary.chargeTimeMin + chargeTimeMin;
        summary.vioTw = summary.vioTw + vioTw;
        summary.vioBat = summary.vioBat + vioBat;
    end
end


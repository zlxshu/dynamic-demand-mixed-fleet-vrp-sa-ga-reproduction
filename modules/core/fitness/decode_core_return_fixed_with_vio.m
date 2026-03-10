function [ch_fixed, ok, detail, vio] = decode_core_return_fixed_with_vio(ch, strictTW, G)
% decode_core_return_fixed_with_vio - 解码 + 违规统计
% 输入:
%   ch       - 染色体 [perm cuts]
%   strictTW - 是否严格时间窗/可行性
%   G        - 配置结构体（含 n,K,D,q,Qmax,LT,RT,ST,B0,Bchg,gE,Speed 等）
% 输出:
%   ch_fixed - 修复后的染色体
%   ok       - 是否可行（严格/松约束取决于 strictTW）
%   detail   - 每辆车的路线/成本明细
%   vio      - 违规量结构

    % ---- 可选配置字段：给默认值，避免“字段不存在”直接报错 ----
    if ~isfield(G, 'allowCharging'),      G.allowCharging = true; end
    if ~isfield(G, 'forceChargeOnce'),   G.forceChargeOnce = false; end
    if ~isfield(G, 'forceChargePolicy'), G.forceChargePolicy = 'ANY_EV'; end

    % 价格字段默认值（沿用 opt27 常用口径；不设置会在成本计算处报错）
    if ~isfield(G, 'fuel_price'),   G.fuel_price = 7.5; end
    if ~isfield(G, 'carbon_price'), G.carbon_price = 0.1; end
    if ~isfield(G, 'elec_price'),   G.elec_price = 0.8; end

    % CMEM 默认值（避免“字段不存在CMEM”，并防止缺字段如 eps 导致报错）
    if ~isfield(G, 'CMEM')
        cm = struct();
        % --- paper/opt27 常见常数（单位按原作者实现口径） ---
        cm.mu   = 44;
        cm.phi  = 1;
        cm.lam  = 0.2;
        cm.H    = 35;
        cm.V    = 5;
        cm.eta  = 0.9;
        cm.eps  = 0.4;
        cm.zeta = 737;
        cm.eCO2 = 3.09;      % kg/L

        % --- 车辆/空气阻力模型参数（若原实现未提供，给可运行默认） ---
        cm.m_empty  = 3000;     % kg（若你有车辆自重请在 G.CMEM.m_empty 里设置）
        cm.Cr       = 0.01;  % rolling resistance coefficient
        cm.rho_air  = 1.225; % kg/m^3
        cm.CdA      = 3.0;   % drag area (m^2)
        cm.rho_fuel = 0.84;  % kg/L (diesel approx)

        G.CMEM = cm;
    end

    n = G.n; K = G.K;

    % 结构修复(perm/cuts)
    ch_fixed = repair_chromosome_deterministic(ch, G);

    perm = ch_fixed(1:n);
    cuts = ch_fixed(n+1:end);
    cuts2 = [cuts, n];

    % 切分 K 段客户
    routes = cell(K,1);
    st = 1;
    for k = 1:K
        ed = cuts2(k);
        if st > ed
            routes{k} = [];
        else
            routes{k} = perm(st:ed);
        end
        st = ed + 1;
    end

    ok = true;
    vio = init_vio_struct();
    detail = struct([]);

    for k = 1:K
        path = routes{k};

        % 载重
        load = sum(G.q(path+1));
        if load > G.Qmax(k)
            if strictTW
                ok = false; vio.cap = vio.cap + (load - G.Qmax(k))/max(G.Qmax(k),1); return;
            else
                ok = false; return;
            end
        end

        seq = [0 path 0];

        % ===== 充电最优:强制至少发生一次充电事件(ANY_EV) =====
        if strictTW && G.forceChargeOnce && strcmpi(G.forceChargePolicy,'ANY_EV')
            firstEV = G.nCV + 1;
            if G.isEV(k) && k == firstEV && numel(seq) >= 3 && seq(2) ~= 0
                st0 = choose_best_station(0, seq(2), G);
                if st0 > 0
                    seq = [0 st0 seq(2:end)];
                end
            end
        end

        time = 0;
        dist = 0;
        battery = G.B0;
        nCharge = 0;
        chargeE = 0;  % total charged energy (kWh)
        insertCount = 0;
        insertMax = 80;

        i = 1;
        while i <= length(seq)-1
            fromNode = seq(i);
            toNode   = seq(i+1);

            from = fromNode + 1;
            to   = toNode   + 1;

            d = G.D(from, to);

            % ---------------- EV:必要时插站 ----------------
            if k > G.nCV && G.allowCharging
                e_kwh_km = G.gE;
                batt_after = battery - d * e_kwh_km;
                minAfter = min_soc_required(toNode, G);

                if batt_after < minAfter
                    if insertCount >= insertMax
                        ok = false; vio.unreach = vio.unreach + 1; return;
                    end
                    if is_station(fromNode, G)
                        ok = false; vio.unreach = vio.unreach + 1; return;
                    end
                    [bestStation, okStation] = choose_best_station_battery(fromNode, toNode, battery, G);
                    if ~okStation
                        ok = false; vio.unreach = vio.unreach + 1; return;
                    end
                    seq = [seq(1:i) bestStation seq(i+1:end)];
                    insertCount = insertCount + 1;
                    continue;
                end
            end

            % ---------------- 行驶时间 ----------------
            time = time + d / G.Speed(k);

            % ---------------- EV:先扣电 ----------------
            if k > G.nCV
                v_kmh = G.Speed(k)*60;  %#ok<NASGU>
                e_kwh_km = G.gE;
                battery = battery - d * e_kwh_km;
                minAfter = min_soc_required(toNode, G);

                if battery < minAfter
                    if strictTW
                        ok = false; vio.bat = vio.bat + (minAfter - battery)/max(G.B0,1); return;
                    else
                        battery = G.Bchg;
                    end
                end
            end

            dist = dist + d;

            % ---------------- 到达节点处理 ----------------
            if toNode == 0
                % depot:无
            elseif is_station(toNode, G)
                % 充电站:只有 allowCharging 才能充
                if k > G.nCV && G.allowCharging
                    needE = max(G.B0 - battery, 0);
                    chargeE = chargeE + needE;
                    charge_rate = G.rg / 60; % kWh/min
                    charge_time = needE / max(charge_rate, 1e-12);
                    time = time + charge_time;
                    battery = G.B0;
                    nCharge = nCharge + 1;
                else
                    if strictTW
                        ok = false; vio.unreach = vio.unreach + 0.5; return;
                    end
                end
            else
                % 客户:时间窗
                if strictTW
                    if time > G.RT(toNode+1)
                        ok = false; vio.tw = vio.tw + (time - G.RT(toNode+1))/max(G.RT(toNode+1),1); return;
                    end
                    if time < G.LT(toNode+1)
                        time = G.LT(toNode+1);
                    end
                end
                time = time + G.ST;
            end

            i = i + 1;
        end

        % ---------------- 充电次数约束 ----------------
        if strictTW && G.forceChargeOnce && (k > G.nCV)
            if strcmpi(G.forceChargePolicy,'EACH_EV')
                if nCharge == 0
                    ok = false; vio.charge = vio.charge + 1; return;
                end
            end
        end

        % ---------------- 成本 ----------------
        if k <= G.nCV
            fuelCost   = 0; carbonCost = 0; elecCost = 0; %#ok<NASGU>
            cm = G.CMEM;
            v_km_min = G.Speed(k);
            v_mps    = v_km_min * (1000/60);
            time_s   = (dist / v_km_min) * 60;

            % === CMEM ??????? 3.2.2 ????paper_repro ????? ===
            % ?????
            %   FR = (P/(?*?) + ?HV) / (?*?)     ? ????? (g/s)
            %   L_ij = FR * t_ij                  ? ????? (g)
            %   fuel_L = L_ij / ?_fuel            ? ????
            %
            % ??? ?=737 ? g/s?L/h ?????????????????
            %   fuel_L = (fuel_g / 1000) / rho_fuel = fuel_g / 840
            %   ?? rho_fuel = 0.84 kg/L = 840 g/L????????
            %
            % ????????5.1 CMEM ??
            %   ?(eta)=0.9, ?(eps)=0.4, ?(lam)=0.2, ?(mu)=44, ?(phi)=1
            %   H=35, V=5, e(eCO2)=3.09 kg/L
            % ============================================
            m_total = cm.m_empty + load;
            F_roll  = m_total * 9.81 * cm.Cr;         % ???? (N)
            F_aero  = 0.5 * cm.rho_air * cm.CdA * v_mps^2;  % ???? (N)
            P_kW    = (F_roll + F_aero) * v_mps / 1000;     % ?? (kW)?????? ? ? FR ???
            P       = P_kW;

            % FR: ????? (g/s)????? FR = (P/(?*?) + ?HV) / (?*?)
            FR_gps  = ( P/(cm.eta*cm.eps) + cm.lam*cm.H*cm.V ) / (cm.mu*cm.phi);
            fuel_g  = FR_gps * time_s;                      % ???? (g)
            fuel_L  = (fuel_g/1000) / cm.rho_fuel;          % ???? (L)

            fuelCost   = fuel_L * G.fuel_price;
            carbonCost = fuel_L * cm.eCO2 * G.carbon_price; % ????? = L * e * wc
            elecCost   = 0;
        else
            fuelCost   = 0;
            carbonCost = 0;
            roadE      = dist * G.gE;  %#ok<NASGU>
            elecCost   = chargeE * G.elec_price;
        end

        detail(k).vehicle    = k;
        detail(k).route      = seq;
        detail(k).distance   = dist;
        detail(k).load       = load;
        detail(k).nCharge    = nCharge;
        detail(k).chargeE    = chargeE;
        usedVeh = any((seq>=1) & (seq<=G.n));
        startC = 0;
        if usedVeh
            startC = G.c(k);
        end
        detail(k).used       = usedVeh;
        detail(k).startCost  = startC;
        detail(k).driveCost  = G.m(k) * dist;
        detail(k).fuelCost   = fuelCost;
        detail(k).elecCost   = elecCost;
        detail(k).carbonCost = carbonCost;
        detail(k).totalCost  = startC + detail(k).driveCost + fuelCost + carbonCost + elecCost;
    end
end

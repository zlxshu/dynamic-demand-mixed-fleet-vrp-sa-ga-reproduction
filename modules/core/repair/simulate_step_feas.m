function [ok, tArrive, bArrive] = simulate_step_feas(fromNode, toNode, t0, b0, k, G)
% simulate_step_feas - 单步可行性模拟 (含插站尝试)
    % 可选字段默认值（避免上层未配置时报错）
    if ~isfield(G, 'allowCharging'), G.allowCharging = true; end

    ok = true;
    tArrive = t0;
    bArrive = b0;

    d = G.D(fromNode+1, toNode+1);

    if k <= G.nCV
        tArrive = t0 + d / G.Speed(k);
        bArrive = b0;
    else
        e_kwh_km = G.gE;
        batt_after = b0 - d * e_kwh_km;
        if batt_after >= min_soc_required(toNode, G)
            tArrive = t0 + d / G.Speed(k);
            bArrive = batt_after;
        else
            if ~G.allowCharging
                ok = false; return;
            end
            [s, okS] = choose_best_station_battery(fromNode, toNode, b0, G);
            if ~okS
                ok = false; return;
            end
            % from -> station
            d1 = G.D(fromNode+1, s+1);
            b1 = b0 - d1 * G.gE;
            if b1 < min_soc_required(s, G)
                ok = false; return;
            end
            t1 = t0 + d1 / G.Speed(k);
            needE = max(G.B0 - b1, 0);
            charge_rate = G.rg / 60;
            t1 = t1 + needE / max(charge_rate, 1e-12);
            % station -> to
            d2 = G.D(s+1, toNode+1);
            b2 = G.Bchg - d2 * G.gE;
            if b2 < min_soc_required(toNode, G)
                ok = false; return;
            end
            tArrive = t1 + d2 / G.Speed(k);
            bArrive = b2;
        end
    end

    % 时间窗:仅检查迟到
    if toNode ~= 0 && ~is_station(toNode, G)
        if tArrive > G.RT(toNode+1)
            ok = false;
            return;
        end
    end
end

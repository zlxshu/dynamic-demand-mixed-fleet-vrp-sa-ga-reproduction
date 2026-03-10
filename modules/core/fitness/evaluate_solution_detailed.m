function det = evaluate_solution_detailed(ch, G)
% 修改日志
% - v1 2026-01-21: 新增 evaluate_solution_detailed(ch,G)；在不改目标函数的前提下输出成本构成与机制指标（用于 5.3.3 图解释）。
% - v1 2026-01-21: 指标口径：fixed=startCost；travel=driveCost；charge=elecCost+fuelCost；carbon=carbonCost；twCost=0(严格时间窗)。

    [fx, feasible, ch_fixed, detail] = fitness_strict_penalty(ch, G);

    det = struct();
    det.fx = fx;
    det.feasible = feasible;
    det.ch_fixed = ch_fixed;
    det.detail = detail;

    bd = struct('fixedCost', NaN, 'travelCost', NaN, 'chargeCost', NaN, 'carbonCost', NaN, 'twCost', NaN, 'totalCost', NaN);
    ops = struct('totalChargeTime_h', NaN, 'nCharges', NaN, 'totalChargedEnergy_kWh', NaN, 'totalLateness_min', NaN, 'maxLateness_min', NaN);

    if feasible && ~isempty(detail)
        try
            fixedCost = sum([detail.startCost]);
        catch
            fixedCost = 0;
        end
        try
            travelCost = sum([detail.driveCost]);
        catch
            travelCost = 0;
        end
        try
            chargeCost = sum([detail.elecCost]) + sum([detail.fuelCost]);
        catch
            chargeCost = 0;
        end
        try
            carbonCost = sum([detail.carbonCost]);
        catch
            carbonCost = 0;
        end

        twCost = 0; % 严格时间窗模型：可行解无罚成本；机制指标用 lateness 记录（可行应为 0）
        totalCost = fixedCost + travelCost + chargeCost + carbonCost + twCost;

        bd.fixedCost = fixedCost;
        bd.travelCost = travelCost;
        bd.chargeCost = chargeCost;
        bd.carbonCost = carbonCost;
        bd.twCost = twCost;
        bd.totalCost = totalCost;

        % ops
        totalChargedEnergy = 0;
        nCharges = 0;
        try
            totalChargedEnergy = sum([detail.chargeE]);
        catch
        end
        try
            nCharges = sum([detail.nCharge]);
        catch
        end

        % 充电时间（小时）：energy (kWh) / rg (kWh/h)
        rg = NaN;
        try
            rg = G.rg;
        catch
        end
        totalChargeTime_h = NaN;
        if isfinite(rg) && rg > 0
            totalChargeTime_h = totalChargedEnergy / rg;
        end

        ops.totalChargeTime_h = totalChargeTime_h;
        ops.nCharges = nCharges;
        ops.totalChargedEnergy_kWh = totalChargedEnergy;
        ops.totalLateness_min = 0;
        ops.maxLateness_min = 0;
    end

    det.breakdown = bd;
    det.ops = ops;
end



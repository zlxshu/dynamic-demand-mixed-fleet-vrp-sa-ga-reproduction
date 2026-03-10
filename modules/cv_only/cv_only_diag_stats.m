function diag = cv_only_diag_stats(detail, G)
% =========================================================================
% [模块] cv_only_diag_stats
%  功能: CV-only 诊断统计(距离/成本/碳排)
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
diag.distance = sum([detail.distance]);
diag.driveCost = sum([detail.driveCost]);
diag.energyCost = sum([detail.fuelCost]) + sum([detail.elecCost]);
diag.carbonCost = sum([detail.carbonCost]);
diag.totalCost = sum([detail.totalCost]);
diag.oilCost = sum([detail.fuelCost]);
if isfield(G,'carbon_price') && G.carbon_price > 0
    diag.carbonEmission = diag.carbonCost / G.carbon_price;
else
    diag.carbonEmission = 0;
end
diag.carbonKg = diag.carbonEmission;
end

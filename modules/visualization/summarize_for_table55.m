function summary = summarize_for_table55(detail, G, fleetLabel)
% =========================================================================
% [模块] summarize_for_table55
%  功能: 汇总表5.5所需的统计数据
%  论文对应: 第5章 表5.5
%  说明: 模块化版本,接受 G 参数.
% =========================================================================
detailUsed = filter_used_detail(detail);
summary = struct();
summary.type = fleetLabel;
summary.vehCount = numel(detailUsed);
summary.fixedCost = sum([detailUsed.startCost]);
summary.distance = sum([detailUsed.distance]);
summary.carbonCost = sum([detailUsed.carbonCost]);
if isfield(G,'carbon_price') && G.carbon_price > 0
    summary.carbonEmission = summary.carbonCost / G.carbon_price;
else
    summary.carbonEmission = 0;
end
summary.energyCost = sum([detailUsed.fuelCost]) + sum([detailUsed.elecCost]);
summary.totalCost = sum([detailUsed.totalCost]);
end

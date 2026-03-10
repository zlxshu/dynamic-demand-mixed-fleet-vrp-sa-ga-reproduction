function T55 = build_table55(customSummary, mixSummary)
% =========================================================================
% [模块] build_table55
%  功能: 构建表5.5(配送结果对比)
%  论文对应: 第5章 表5.5
%  说明: 模块化版本.
% =========================================================================
types = {customSummary.type; mixSummary.type};
vehCount = [customSummary.vehCount; mixSummary.vehCount];
fixedCost = round([customSummary.fixedCost; mixSummary.fixedCost], 2);
distance = round([customSummary.distance; mixSummary.distance], 2);
carbonEmission = round([customSummary.carbonEmission; mixSummary.carbonEmission], 2);
carbonCost = round([customSummary.carbonCost; mixSummary.carbonCost], 2);
energyCost = round([customSummary.energyCost; mixSummary.energyCost], 2);
totalCost = round([customSummary.totalCost; mixSummary.totalCost], 2);

T55 = table(types, vehCount, fixedCost, distance, carbonEmission, carbonCost, energyCost, totalCost, ...
    'VariableNames', {'类型','车辆数_辆','固定成本_元','行驶里程_km','碳排放量_kg','碳排放成本_元','能源成本_元','总成本_元'});
end

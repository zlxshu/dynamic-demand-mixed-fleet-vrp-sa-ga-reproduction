function T54 = build_table54_from_detail(detail)
% =========================================================================
% [模块] build_table54_from_detail
%  功能: 构建表5.4(燃油车队路径成本分解,含总计行)
%  论文对应: 第5章 表5.4
%  说明: 模块化版本.
% =========================================================================
detailUsed = filter_used_detail(detail);
n = numel(detailUsed);
pathName = cell(n+1,1);
startCost = zeros(n+1,1);
driveCost = zeros(n+1,1);
fuelCost = zeros(n+1,1);
carbonCost = zeros(n+1,1);
totalCost = zeros(n+1,1);

for k = 1:n
    pathName{k} = ['路径' num2str(k)];
    startCost(k) = detailUsed(k).startCost;
    driveCost(k) = detailUsed(k).driveCost;
    fuelCost(k) = detailUsed(k).fuelCost;
    carbonCost(k) = detailUsed(k).carbonCost;
    totalCost(k) = detailUsed(k).totalCost;
end

pathName{n+1} = '总计';
startCost(n+1) = sum(startCost(1:n));
driveCost(n+1) = sum(driveCost(1:n));
fuelCost(n+1) = sum(fuelCost(1:n));
carbonCost(n+1) = sum(carbonCost(1:n));
totalCost(n+1) = sum(totalCost(1:n));

T54 = table(pathName, round(startCost,2), round(driveCost,2), round(fuelCost,2), round(carbonCost,2), round(totalCost,2), ...
    'VariableNames', {'配送路径','启动成本_元','行驶成本_元','油耗成本_元','碳排放成本_元','总成本_元'});
end

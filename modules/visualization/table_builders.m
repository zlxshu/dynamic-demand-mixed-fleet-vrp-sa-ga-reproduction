function info = build_tables_from_detail(detail, n, E, nCV)
% =========================================================================
% [模块] build_tables_from_detail
%  功能: 构建表5.2/5.3(路线与成本表格)
%  论文对应: 第5章 表5.2/5.3
%  说明: 模块化版本.
% =========================================================================
veh = cell(numel(detail),1);
routeStr = cell(numel(detail),1);
dist = zeros(numel(detail),1);
loadv = zeros(numel(detail),1);
util = zeros(numel(detail),1);

for k = 1:numel(detail)
    if k <= nCV
        veh{k} = ['CV' num2str(k)];
        cap = 1500;
    else
        veh{k} = ['EV' num2str(k-nCV)];
        cap = 1000;
    end
    r = detail(k).route;

    % 显示站为 R1..RE
    rDisp = cell(1,numel(r));
    for t=1:numel(r)
        node = r(t);
        if node==0
            rDisp{t}='0';
        elseif node>=n+1 && node<=n+E
            rDisp{t}=['R' num2str(node-n)];
        else
            rDisp{t}=num2str(node);
        end
    end
    routeStr{k} = strjoin(rDisp,'-->');

    dist(k) = detail(k).distance;
    loadv(k) = detail(k).load;
    util(k) = loadv(k)/cap*100;
end

% [PAPER] 表5.2/表5.3 仅展示"实际使用车辆"(未使用车辆不计启动成本,也不输出到表中)
usedIdx = true(numel(detail),1);
if isfield(detail,'distance') && isfield(detail,'load')
    usedIdx = arrayfun(@(x) (x.distance>1e-9) || (x.load>0), detail);
end
detail  = detail(usedIdx);
veh     = veh(usedIdx);
routeStr= routeStr(usedIdx);
dist    = dist(usedIdx);
loadv   = loadv(usedIdx);
util    = util(usedIdx);

T52 = table(veh, routeStr, round(dist,2), loadv, util, ...
    'VariableNames', {'车辆','路径','里程_km','载重_kg','负载率_%'});

pathName = cell(numel(detail),1);
startCost = zeros(numel(detail),1);
driveCost = zeros(numel(detail),1);
fuelCost = zeros(numel(detail),1);
elecCost = zeros(numel(detail),1);
carbonCost = zeros(numel(detail),1);
totalCost = zeros(numel(detail),1);

for k = 1:numel(detail)
    pathName{k} = ['路径' num2str(k)];
    startCost(k) = detail(k).startCost;
    driveCost(k) = detail(k).driveCost;
    fuelCost(k)  = detail(k).fuelCost;
    elecCost(k)  = detail(k).elecCost;
    carbonCost(k)= detail(k).carbonCost;
    totalCost(k) = detail(k).totalCost;
end

T53 = table(pathName, startCost, driveCost, fuelCost, elecCost, carbonCost, totalCost, ...
    'VariableNames', {'路径','启动成本','行驶成本','燃油成本','电能成本','碳排成本','总成本'});

info = struct();
info.table52 = T52;
info.table53 = T53;
info.detail = detail;
end

function detailUsed = filter_used_detail(detail)
% =========================================================================
% [模块] filter_used_detail
%  功能: 过滤出实际使用的车辆详情
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
detailUsed = detail;
if isempty(detail)
    return;
end
usedIdx = true(numel(detail),1);
if isfield(detail,'distance') && isfield(detail,'load')
    usedIdx = arrayfun(@(x) (x.distance > 1e-9) || (x.load > 0), detail);
end
detailUsed = detail(usedIdx);
end

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

function legendMode = legend_mode_for_fleet(nCV, nEV)
% =========================================================================
% [模块] legend_mode_for_fleet
%  功能: 根据车队配置确定图例模式
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
if nCV == 2 && nEV == 2
    legendMode = 'nodes';
else
    legendMode = 'paths';
end
end

function titleText = title_for_fleet(nCV, nEV)
% =========================================================================
% [模块] title_for_fleet
%  功能: 根据车队配置确定图表标题
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
if nCV > 0 && nEV == 0
    titleText = '燃油车队配送路径示意图';
elseif nCV == 0 && nEV > 0
    titleText = '纯电车队配送路径示意图';
elseif nCV == 2 && nEV == 2
    titleText = '混合车队配送路径示意图';
else
    titleText = '配送路径示意图';
end
end

function label = fleet_type_label(nCV, nEV, isCustom)
% =========================================================================
% [模块] fleet_type_label
%  功能: 返回车队类型标签
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
if nargin < 3
    isCustom = false;
end
if isCustom
    if nCV > 0 && nEV == 0
        label = '燃油车队';
    elseif nCV == 0 && nEV > 0
        label = '纯电车队';
    else
        label = '自定义车队';
    end
else
    if nCV > 0 && nEV > 0
        label = '混合车队';
    elseif nCV > 0
        label = '燃油车队';
    elseif nEV > 0
        label = '纯电车队';
    else
        label = '自定义车队';
    end
end
end

function tag = fleet_tag(nCV, nEV, tagIn)
% =========================================================================
% [模块] fleet_tag
%  功能: 返回车队标签(用于输出目录等)
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
if nargin >= 3 && ~isempty(tagIn)
    tag = tagIn;
else
    tag = sprintf('FLEET_%d_%d', nCV, nEV);
end
end

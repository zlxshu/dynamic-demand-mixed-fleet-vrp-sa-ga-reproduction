function info = build_tables_from_detail(detail, n, E, nCV)
% =========================================================================
% [ģ��] build_tables_from_detail
%  ����: ������5.2/5.3(·����ɱ�����)
%  ���Ķ�Ӧ: ��5�� ��5.2/5.3
%  ˵��: ģ�黯�汾.
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

    % ��ʾվΪ R1..RE
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
    routeStr{k} = strjoin(rDisp,'-');

    dist(k) = detail(k).distance;
    loadv(k) = detail(k).load;
    util(k) = loadv(k)/cap*100;
end

% [PAPER] ��5.2/��5.3 ��չʾ"ʵ��ʹ�ó���"(δʹ�ó������������ɱ�,Ҳ�����������)
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
    'VariableNames', {'车辆','路径','距离_km','载重_kg','装载率_%'});

pathName = cell(numel(detail),1);
startCost = zeros(numel(detail),1);
driveCost = zeros(numel(detail),1);
fuelCost = zeros(numel(detail),1);
elecCost = zeros(numel(detail),1);
carbonCost = zeros(numel(detail),1);
totalCost = zeros(numel(detail),1);

for k = 1:numel(detail)
    pathName{k} = sprintf('路径%d', k);
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

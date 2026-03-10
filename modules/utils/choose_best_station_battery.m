function [bestStation, ok] = choose_best_station_battery(fromNode, toNode, batteryNow, G)
% choose_best_station_battery - 选站策略: from->station->to 均可达，优先绕行距离小

stations = (G.n+1):(G.n+G.E);
from = fromNode + 1;
to   = toNode   + 1;

bestVal = inf;
bestStation = [];
ok = false;

needAfterTo = min_soc_required(toNode, G);  % 到达 toNode 后的最低SOC需求

for s = stations
    if s == fromNode
        continue;
    end
    si = s + 1;

    d1 = G.D(from, si);
    d2 = G.D(si, to);

    % from -> station:用当前电量判断
    batt_after_1 = batteryNow - d1 * G.gE;
    if batt_after_1 < min_soc_required(s, G)
        continue;
    end

    % station -> to:假设在站充满后出站
    batt_after_2 = G.Bchg - d2 * G.gE;
    if batt_after_2 < needAfterTo
        continue;
    end

    % 成本近似：绕行距离 + 本次充电能量
    mEV = 10;
    try
        if isfield(G,'m') && isfield(G,'nCV') && numel(G.m) >= G.nCV+1
            mEV = G.m(G.nCV+1);
        elseif isfield(G,'m') && ~isempty(G.m)
            mEV = G.m(end);
        end
    catch
    end
    needE = max(G.B0 - batt_after_1, 0);
    val = (d1 + d2) * mEV + needE * G.elec_price;
    if val < bestVal
        bestVal = val;
        bestStation = s;
        ok = true;
    end
end
end

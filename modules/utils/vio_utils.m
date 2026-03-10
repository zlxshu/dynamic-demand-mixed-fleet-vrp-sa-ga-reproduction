function vio = init_vio_struct()
% init_vio_struct - 初始化违规统计结构体
% 输出: vio = struct('unreach',0,'tw',0,'cap',0,'bat',0,'charge',0)

    vio = struct('unreach',0,'tw',0,'cap',0,'bat',0,'charge',0);
end

function tf = is_station(node, G)
% is_station - 判断节点是否为充电站
% 输入: node (从0开始)，G 需包含 n, E
    tf = (node >= (G.n+1)) & (node <= (G.n+G.E));
end

function minAfter = min_soc_required(node, G)
% min_soc_required - 到达节点后允许的最低 SOC
% 逻辑与原脚本一致:
%  - 客户: 至少保留到最近充电站的能量 reserveE
%  - 站/仓库: 允许降到 0

    % Depot
    if node == 0
        minAfter = 0;
        return;
    end

    % Charging station
    if is_station(node, G)
        minAfter = 0;
        return;
    end

    % Customer: reserveE 已在 G 预计算
    if isfield(G,'reserveE') && numel(G.reserveE) >= (node+1)
        minAfter = G.reserveE(node+1);  % node 从0开始
    else
        % 兜底: 动态计算最近站距离
        from = node + 1;
        stIdx = (G.n+1):(G.n+G.E);
        dmin = min(G.D(from, stIdx+1)); % km
        minAfter = dmin * G.gE;
    end

    % 数值保护
    if ~isfinite(minAfter) || minAfter < 0
        minAfter = 0;
    end
end

function [bestStation, ok] = choose_best_station_battery(fromNode, toNode, batteryNow, G)
% choose_best_station_battery - 选站策略: from->station->to 均可达，优先绕行距离小
% 与原脚本逻辑一致，显式传参 G。

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

function st = choose_best_station(fromNode, toNode, G)
% choose_best_station - 简化接口，使用当前满电 B0 评估 from->station->to 可达性
    [st, ok] = choose_best_station_battery(fromNode, toNode, G.B0, G);
    if ~ok
        st = -1;
    end
end

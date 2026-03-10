function minAfter = min_soc_required(node, G)
% min_soc_required - 到达节点后允许的最低 SOC
% 逻辑:
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

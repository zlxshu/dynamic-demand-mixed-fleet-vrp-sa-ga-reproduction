function tf = is_station(node, G)
% is_station - 判断节点是否为充电站
% 输入: node (从0开始)，G 需包含 n, E
tf = (node >= (G.n+1)) & (node <= (G.n+G.E));
end

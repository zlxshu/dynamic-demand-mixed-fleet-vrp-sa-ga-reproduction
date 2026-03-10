function st = choose_best_station(fromNode, toNode, G)
% choose_best_station - 简化接口，使用当前满电 B0 评估 from->station->to 可达性
[st, ok] = choose_best_station_battery(fromNode, toNode, G.B0, G);
if ~ok
    st = -1;
end
end

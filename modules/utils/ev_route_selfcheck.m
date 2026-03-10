function [minB, roadE, chargeE] = ev_route_selfcheck(route, n, E, G)
% =========================================================================
% [模块] ev_route_selfcheck
%  功能: EV自检:输出每条EV路线的里程,路耗,充电量,最小SOC
%  论文对应: 第5章 结果诊断(实现层)
%  说明: 模块化版本,接受 G 参数.
% =========================================================================
B = G.B0;
minB = B;
roadE = 0;
chargeE = 0;

if isempty(route) || numel(route) < 2
    return;
end

for ii = 1:(numel(route)-1)
    a = route(ii);
    b = route(ii+1);
    d = G.D(a+1, b+1);  % km
    e = d * G.gE;       % kWh
    roadE = roadE + e;
    B = B - e;
    if B < minB, minB = B; end
    % 到达充电站:按论文假设"每次充电充满"
    if b > n && b <= n+E
        need = G.B0 - B;
        if need < 0, need = 0; end
        chargeE = chargeE + need;
        B = G.B0;
    end
end
end

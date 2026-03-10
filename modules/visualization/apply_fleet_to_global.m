function G = apply_fleet_to_global(G, nCV, nEV, K, Qmax, Speed, c, m)
% =========================================================================
% [模块] apply_fleet_to_global
%  功能: 将车队参数应用到 G 结构体
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
G.K = K;
G.nCV = nCV;
G.nEV = nEV;
G.isEV = false(1, K);
if nEV > 0
    G.isEV(nCV+1:end) = true;
end
G.Qmax = Qmax;
G.Speed = Speed;
G.c = c;
G.m = m;
end

function [K, Qmax, Speed, c, m] = build_fleet_arrays(nCV, nEV, baseFleet)
% =========================================================================
% [模块] build_fleet_arrays
%  功能: 根据车队配置构建车辆参数数组
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
K = nCV + nEV;
Qmax = [baseFleet.QCV*ones(1,nCV), baseFleet.QEV*ones(1,nEV)];
Speed = baseFleet.speed * ones(1, K);
c = [baseFleet.cCV*ones(1,nCV), baseFleet.cEV*ones(1,nEV)];
m = [baseFleet.mCV*ones(1,nCV), baseFleet.mEV*ones(1,nEV)];
end

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

function validate_fleet_counts(nCV, nEV, maxFleet)
% =========================================================================
% [模块] validate_fleet_counts
%  功能: 验证车队数量参数有效性
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
if ~isscalar(nCV) || ~isscalar(nEV)
    error('fleet counts must be scalars.');
end
if nCV < 0 || nEV < 0 || nCV > maxFleet || nEV > maxFleet
    error('fleet counts out of range: nCV=%d nEV=%d (allowed 0..%d)', nCV, nEV, maxFleet);
end
if (nCV + nEV) < 1
    error('fleet counts invalid: total vehicles must be >= 1.');
end
end

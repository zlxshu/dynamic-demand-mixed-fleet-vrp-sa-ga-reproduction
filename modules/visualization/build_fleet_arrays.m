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

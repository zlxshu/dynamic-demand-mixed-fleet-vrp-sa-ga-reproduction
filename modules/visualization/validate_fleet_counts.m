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

function detailUsed = filter_used_detail(detail)
% =========================================================================
% [模块] filter_used_detail
%  功能: 过滤出实际使用的车辆详情
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
detailUsed = detail;
if isempty(detail)
    return;
end
usedIdx = true(numel(detail),1);
if isfield(detail,'distance') && isfield(detail,'load')
    usedIdx = arrayfun(@(x) (x.distance > 1e-9) || (x.load > 0), detail);
end
detailUsed = detail(usedIdx);
end

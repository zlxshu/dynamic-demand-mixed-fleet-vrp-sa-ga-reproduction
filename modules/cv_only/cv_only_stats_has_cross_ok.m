function tf = cv_only_stats_has_cross_ok(stats)
% =========================================================================
% [模块] cv_only_stats_has_cross_ok
%  功能: 判断 CV-only 统计中是否存在跨路径改进成功
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
tf = false;
if ~isfield(stats,'fail')
    return;
end
opList = {'exch21','exch12','swap22','kick','lns','chain'};
for i = 1:numel(opList)
    op = opList{i};
    if isfield(stats.fail, op) && isfield(stats.fail.(op), 'ok') && stats.fail.(op).ok > 0
        tf = true;
        return;
    end
end
end

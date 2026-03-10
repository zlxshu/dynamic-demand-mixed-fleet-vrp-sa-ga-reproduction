function tf = cv_only_enhance_enabled(G)
% =========================================================================
% [模块] cv_only_enhance_enabled
%  功能: 判断是否启用 CV-only 增强优化.
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
tf = cv_only_case(G) && isfield(G,'cvOnlyOpt') && isfield(G.cvOnlyOpt,'enableCVOnlyImprove') && ...
    G.cvOnlyOpt.enableCVOnlyImprove;
end

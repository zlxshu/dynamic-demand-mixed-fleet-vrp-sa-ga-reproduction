function tag = fleet_tag(nCV, nEV, tagIn)
% =========================================================================
% [模块] fleet_tag
%  功能: 返回车队标签(用于输出目录等)
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
if nargin >= 3 && ~isempty(tagIn)
    tag = tagIn;
else
    tag = sprintf('FLEET_%d_%d', nCV, nEV);
end
end

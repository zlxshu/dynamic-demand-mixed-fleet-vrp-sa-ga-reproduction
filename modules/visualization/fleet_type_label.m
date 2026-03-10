function label = fleet_type_label(nCV, nEV, isCustom)
% =========================================================================
% [模块] fleet_type_label
%  功能: 返回车队类型标签
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
if nargin < 3
    isCustom = false;
end
if isCustom
    if nCV > 0 && nEV == 0
        label = '燃油车队';
    elseif nCV == 0 && nEV > 0
        label = '纯电车队';
    else
        label = '自定义车队';
    end
else
    if nCV > 0 && nEV > 0
        label = '混合车队';
    elseif nCV > 0
        label = '燃油车队';
    elseif nEV > 0
        label = '纯电车队';
    else
        label = '自定义车队';
    end
end
end

function [fx, feasible, ch_fixed] = fitness_relaxed(ch, G)
% fitness_relaxed - 松约束/带罚评价（不可行返回 inf）
% 输入:
%   ch - 染色体
%   G  - 配置结构体
% 输出:
%   fx        - 目标值（可行=真实成本，不可行=inf）
%   feasible  - 可行性标记
%   ch_fixed  - 修复后的染色体

    [ch_fixed, ok, detail, ~] = decode_core_return_fixed_with_vio(ch, false, G);
    if ok
        fx = sum([detail.totalCost]);
        feasible = true;
    else
        fx = inf;
        feasible = false;
    end
end

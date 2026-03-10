function s = fmt_best(bestCost)
% fmt_best - 格式化最优值
% 输入: bestCost - 数值或 Inf
% 输出: 字符串

    if isfinite(bestCost)
        s = sprintf('%.6f', bestCost);
    else
        s = '无';
    end
end

function out = ternary(cond, a, b)
% ternary - 三目选择
    if cond, out = a; else, out = b; end
end

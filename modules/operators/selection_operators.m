function w = selection_weight_penalty(fx, feasible)
% selection_weight_penalty - 轮盘赌权重（可行优先，带罚）
% 与原脚本一致：可行解按 1/f，加基线；不可行解给极小权重。

    w = zeros(size(fx));
    if any(feasible)
        f = fx(feasible);
        f = f - min(f) + 1e-6;
        w(feasible) = 1 ./ f;
        base = mean(w(feasible));
        w(~feasible) = 0.01 * base;
    else
        f = fx - min(fx) + 1e-6;
        w = 1 ./ f;
    end
    if all(w==0), w(:)=1; end
end

function Xsel = roulette_selection_fast(X, w)
% roulette_selection_fast - 轮盘赌选择（向量化）

    s = sum(w);
    if s <= 0
        w(:)=1;
        s = sum(w);
    end
    P = cumsum(w(:)/s);
    N = size(X,1);
    r = rand(N,1);
    idx = arrayfun(@(x) find(P>=x,1,'first'), r);
    Xsel = X(idx,:);
end

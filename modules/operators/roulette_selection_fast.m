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


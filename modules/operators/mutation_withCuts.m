function Xm = mutation_withCuts(X, Pm, n, K)
% mutation_withCuts - 多点变异并修复 cuts（与原脚本一致）

    Xm = X;
    N = size(X,1);
    for i = 1:N
        if rand < Pm
            m = randi([3, min(6,n)]);           % 多点数
            pos = randperm(n, m);
            tmp = Xm(i,1:n);
            vals = tmp(pos);
            vals = vals(randperm(m));          % 多点重排
            tmp(pos) = vals;
            Xm(i,1:n) = tmp;
        end
        Xm(i,n+1:end) = fixCuts_deterministic(Xm(i,n+1:end), n, K);
    end
end


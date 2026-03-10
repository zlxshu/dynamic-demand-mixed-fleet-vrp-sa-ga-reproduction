function chBest = or_opt_within_routes_rs(ch, n, K, maxTrials, ~, G)
% =========================================================================
% [模块] or_opt_within_routes_rs
%  功能: Or-opt:从同一路径中取一个客户,插入到另一个位置(轻量)
%  论文对应: 实现层
%  说明: 模块化版本,接受 G 参数而非 global.
% =========================================================================
chBest = ch;
[fBest, feBest, chBest, ~] = fitness_strict_penalty(chBest, G);
if ~feBest
    return;
end

for t = 1:maxTrials
    perm = chBest(1:n);
    cuts = chBest(n+1:n+K-1);
    routes = split_perm_by_cuts_pub(perm, cuts, n, K);

    k = randi(K);
    r = routes{k};
    if numel(r) < 2
        continue;
    end
    i = randi(numel(r));
    node = r(i);
    r(i) = [];
    j = randi(numel(r)+1); % insertion position
    r2 = [r(1:j-1) node r(j:end)];
    routes{k} = r2;

    [perm2, cuts2] = merge_routes_to_perm_pub(routes, n, K);
    cand = [perm2 cuts2];
    cand = repair_chromosome_deterministic(cand, n, K, G);

    [f2, fe2, cand, ~] = fitness_strict_penalty(cand, G);
    if fe2 && (f2 < fBest)
        chBest = cand;
        fBest = f2;
    end
end
end

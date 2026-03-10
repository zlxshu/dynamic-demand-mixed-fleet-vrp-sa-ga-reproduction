function chBest = two_opt_within_routes_rs(ch, n, K, maxIter, G, rs)
% =========================================================================
% [模块] two_opt_within_routes_rs
%  功能: 2-opt:单路径内做边交换,降低路径长度.
%  论文对应: 实现层(局部搜索)
%  说明: 模块化版本,接受 G 参数而非 global.
% =========================================================================
% 修改日志
% - v3 2026-01-27: section_541 的 FitnessFcn 适配已迁移到 modules/section541/*_541.m；本文件保持通用实现（并统一为 UTF-8 编码）。

chBest = ch;
[fBest, feBest, chBest, ~] = fitness_strict_penalty(chBest, G);
if ~feBest
    return;
end

for iter = 1:maxIter
    perm = chBest(1:n);
    cuts = chBest(n+1:n+K-1);
    routes = split_perm_by_cuts_pub(perm, cuts, n, K);

    k = randi(rs, K);
    r = routes{k};
    if numel(r) < 3
        continue;
    end

    % 2-opt: 选两个位置做反转
    i = randi(rs, numel(r)-1);
    j = randi(rs, [i+1, numel(r)]);

    r(i:j) = r(j:-1:i);

    routes{k} = r;
    [perm2, cuts2] = merge_routes_to_perm_pub(routes, n, K);
    candCh = [perm2 cuts2];

    [f2, fe2, candCh, ~] = fitness_strict_penalty(candCh, G);
    if fe2 && f2 < fBest
        fBest = f2;
        chBest = candCh;
    end
end
end

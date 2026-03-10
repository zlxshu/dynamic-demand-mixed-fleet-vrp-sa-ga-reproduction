function chBest = or_opt_within_routes_rs(ch, n, K, maxTrials, ~, G)
% =========================================================================
% [模块] or_opt_within_routes_rs
%  功能: Or-opt:从同一路径中取一个客户,插入到另一个位置(轻量)
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

    if j == 1
        r = [node r];
    elseif j > numel(r)
        r = [r node];
    else
        r = [r(1:j-1) node r(j:end)];
    end

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

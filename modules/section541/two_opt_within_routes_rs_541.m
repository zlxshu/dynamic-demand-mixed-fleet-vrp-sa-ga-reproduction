function chBest = two_opt_within_routes_rs_541(ch, n, K, maxIter, G, rs)
% =========================================================================
% [模块] two_opt_within_routes_rs
%  功能: 2-opt:单路径内做边交换,降低路径长度.
%  论文对应: 实现层(局部搜索)
%  说明: 模块化版本,接受 G 参数而非 global.
% =========================================================================
% 修改日志
% - v541 2026-01-27: 从 core/gsaa 拷贝到 section541，仅供 section_541 使用；保持逻辑不变，仅改函数名（支持 FitnessFcn 由 G.fitnessFcn 提供）。
% - v2 2026-01-27: 支持自定义适应度函数句柄（从 G.fitnessFcn 读取，默认 strict penalty）。

chBest = ch;
fitnessFcn = get_fitness_fcn_(G);
[fBest, feBest, chBest, ~] = fitnessFcn(chBest, G);
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

    [f2, fe2, candCh, ~] = fitnessFcn(candCh, G);
    if fe2 && f2 < fBest
        fBest = f2;
        chBest = candCh;
    end
end
end

function f = get_fitness_fcn_(G)
    f = @fitness_strict_penalty;
    try
        if isfield(G,'fitnessFcn') && isa(G.fitnessFcn,'function_handle')
            f = G.fitnessFcn;
        end
    catch
        f = @fitness_strict_penalty;
    end
end


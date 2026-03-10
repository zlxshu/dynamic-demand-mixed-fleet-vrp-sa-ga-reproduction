function routes = split_perm_by_cuts_pub(perm, cuts, n, K)
% split_perm_by_cuts_pub - perm+cuts -> routes
    cuts = sort(cuts(:))';
    cuts = max(0, min(n, cuts));
    b = [0 cuts n];
    routes = cell(1, K);
    for k = 1:K
        s = b(k) + 1;
        e = b(k+1);
        if s > e
            routes{k} = [];
        else
            routes{k} = perm(s:e);
        end
    end
end

function [perm, cuts] = merge_routes_to_perm_pub(routes, n, K)
% merge_routes_to_perm_pub - routes -> perm+cuts
    perm = [];
    cuts = zeros(1, K-1);
    cnt = 0;
    for k = 1:K
        perm = [perm, routes{k}]; %#ok<AGROW>
        cnt = cnt + numel(routes{k});
        if k <= K-1
            cuts(k) = cnt;
        end
    end
    perm = perm(1:min(n, numel(perm)));
    if numel(perm) < n
        miss = setdiff(1:n, perm, 'stable');
        perm = [perm, miss(:)'];
    end
    cuts = sort(max(0, min(n, cuts)));
end

function routes = split_perm_by_cuts(perm, cuts, n, K)
% split_perm_by_cuts - 内部版本
    routes = split_perm_by_cuts_pub(perm, cuts, n, K);
end

function [perm, cuts] = merge_routes_to_perm(routes, n, K)
% merge_routes_to_perm - 内部版本
    [perm, cuts] = merge_routes_to_perm_pub(routes, n, K);
end

function ch2 = cv_only_apply_capacity_cuts(ch, n, K, G)
% cv_only_apply_capacity_cuts - Re-split perm into K routes by capacity (CV-only).

perm = ch(1:n);
routes = cv_only_split_by_capacity_(perm, G, K);
[perm2, cuts2] = merge_routes_to_perm_pub(routes, n, K);
ch2 = [perm2 cuts2];
ch2 = repair_chromosome_deterministic(ch2, n, K, G);
end

function routes = cv_only_split_by_capacity_(order, G, K)
routes = cell(1, K);
cur = 1;
load = 0;
for ii = 1:numel(order)
    cust = order(ii);
    demand = G.q(cust+1);
    if cur < K && (load + demand > G.Qmax(cur))
        cur = cur + 1;
        load = 0;
    end
    routes{cur}(end+1) = cust; %#ok<AGROW>
    load = load + demand;
end
end


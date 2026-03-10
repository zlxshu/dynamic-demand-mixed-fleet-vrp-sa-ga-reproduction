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

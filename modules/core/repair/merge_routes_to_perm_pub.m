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

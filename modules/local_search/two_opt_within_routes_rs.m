function ch2 = two_opt_within_routes_rs(ch, n, K, maxIter, G, rs)
% =========================================================================
% [???] two_opt_within_routes_rs
%  ????: ???????:?????????????2-opt?????(???????)
%  ??????: ????(???????,???????)
%  ???: ???????,???? G ???????? global.
% =========================================================================
% ?? opt4/5 ????,????????????? rs,????????? rng
perm = ch(1:n);
cuts = sort(ch(n+1:end));
cuts = max(1, min(n-1, cuts));
cuts = unique(cuts,'stable');
while numel(cuts) < (K-1)
    cand = randi(rs, [1,n-1]);
    if ~ismember(cand,cuts), cuts(end+1)=cand; cuts=sort(cuts); end
end
cuts = cuts(1:K-1);

bounds = [0 cuts n];
bestPerm = perm;
bestCh = [bestPerm cuts];
[bestFit, bestFe] = fitness_strict_penalty(bestCh, G);
if ~bestFe
    ch2 = ch;
    return;
end

iter = 0;
while iter < maxIter
    iter = iter + 1;
    improved = false;

    for r = 1:K
        a = bounds(r)+1; b = bounds(r+1);
        if b - a + 1 < 4, continue; end
        route = bestPerm(a:b);
        i = randi(rs, [1, numel(route)-2]);
        j = randi(rs, [i+1, numel(route)-1]);
        newRoute = route;
        newRoute(i:j) = route(j:-1:i);

        candPerm = bestPerm;
        candPerm(a:b) = newRoute;
        candCh = [candPerm cuts];
        [f2, fe2] = fitness_strict_penalty(candCh, G);
        if fe2 && f2 + 1e-9 < bestFit
            bestFit = f2;
            bestPerm = candPerm;
            improved = true;
        end
    end

    if ~improved
        break;
    end
end

% 3) ????"????? EV"????????????(???????????????,??????????)
[bestPerm, cuts, ~] = try_empty_ev_route(bestPerm, cuts, bestFit, n, K, G, rs);
ch2 = [bestPerm cuts];
end

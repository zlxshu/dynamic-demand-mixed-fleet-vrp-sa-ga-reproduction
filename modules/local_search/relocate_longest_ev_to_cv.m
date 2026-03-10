function [chBest, costBest] = relocate_longest_ev_to_cv(ch0, cost0, n, K, G, rs, maxMoves)
% =========================================================================
% [???] relocate_longest_ev_to_cv
%  ????: ???????:??"??EV¡¤??"?????,???????CV?????¦Ë??(?????????+?????)
%  ??????: ????(???EV2????????)
%  ???: ??÷ö?·Ú,???? G ???????? global.
% =========================================================================
% ??"??EV¡¤??"?§Ö??????? CV ??(relocate),????? EV ¡¤??????/?????,?????????.
% - ???????????/??????,?????????????????.
% - ?????:?????? && ??????.

chBest   = ch0;
costBest = cost0;

if ~isfield(G,'nEV') || G.nEV <= 0 || ~isfield(G,'nCV') || G.nCV <= 0
    return;
end

noImp = 0;

for it = 1:maxMoves
    perm = chBest(1:n);
    cuts = sort(chBest(n+1:n+K-1));
    routes = split_perm_by_cuts_pub(perm, cuts, n, K);

    % ???"??"?? EV(?? depot->???????->depot ???????????;???????????)
    evIdxs = (G.nCV+1):K;
    if isempty(evIdxs)
        return;
    end

    distEv = -inf(1, numel(evIdxs));
    for ii = 1:numel(evIdxs)
        r = routes{evIdxs(ii)};
        if isempty(r)
            distEv(ii) = -inf;
            continue;
        end
        seq = [0 r 0];
        d = 0;
        for jj = 1:(numel(seq)-1)
            d = d + G.D(seq(jj)+1, seq(jj+1)+1);
        end
        distEv(ii) = d;
    end

    [~, mx] = max(distEv);
    evIdx = evIdxs(mx);

    if isempty(routes{evIdx})
        break;
    end

    % ??? EV ??????"???????"??????????(?????????????? EV ¡¤??)
    rEV   = routes{evIdx};
    seqEV = [0 rEV 0];
    bestGain = -inf;
    pos = 1;
    for pp = 1:numel(rEV)
        prev = seqEV(pp);
        cur  = rEV(pp);
        nxt  = seqEV(pp+2);
        gain = G.D(prev+1,cur+1) + G.D(cur+1,nxt+1) - G.D(prev+1,nxt+1);
        if gain > bestGain
            bestGain = gain;
            pos = pp;
        end
    end
    cust = rEV(pos);

    baseRoutes = routes;
    baseRoutes{evIdx}(pos) = []; % ?? EV ???

    bestLocalCost   = costBest;
    bestLocalRoutes = routes;
    improved = false;

    for cvIdx = 1:G.nCV
        L = numel(baseRoutes{cvIdx});
        posList = unique(round(linspace(0, L, min(8, L+1)))); % ?????¦Ë??,??????? <=8 ????
        for p = posList
            candRoutes = baseRoutes;
            if p == 0
                candRoutes{cvIdx} = [cust, candRoutes{cvIdx}];
            elseif p >= L
                candRoutes{cvIdx} = [candRoutes{cvIdx}, cust];
            else
                candRoutes{cvIdx} = [candRoutes{cvIdx}(1:p), cust, candRoutes{cvIdx}(p+1:end)];
            end

            [perm2, cuts2] = merge_routes_to_perm_pub(candRoutes, n, K);
            candCh = [perm2, cuts2];

            [f2, fe2, candFixed] = fitness_strict_penalty(candCh, G);
            if fe2 && (f2 < bestLocalCost - 1e-6)
                permF = candFixed(1:n);
                cutsF = sort(candFixed(n+1:n+K-1));
                bestLocalRoutes = split_perm_by_cuts_pub(permF, cutsF, n, K);
                bestLocalCost   = f2;
                improved = true;
            end
        end
    end

    if improved
        costBest = bestLocalCost;
        [perm3, cuts3] = merge_routes_to_perm_pub(bestLocalRoutes, n, K);
        chBest = [perm3, cuts3];
        noImp = 0;
    else
        noImp = noImp + 1;
        if noImp >= 20
            break;
        end
    end
end
end

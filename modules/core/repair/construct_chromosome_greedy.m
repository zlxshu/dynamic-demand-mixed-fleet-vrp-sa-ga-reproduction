function ch = construct_chromosome_greedy(n, K, G)
% construct_chromosome_greedy - 启发式构造初始个体

    remaining = 1:n;
    routes = cell(1,K);

    for k = 1:K
        cur = 0; t = 0; load = 0;
        battery = G.B0;
        route = [];

        while ~isempty(remaining)
            bestIdx = 0;
            bestScore = inf;
            bestNextT = NaN;
            bestNextB = NaN;

            for ii = 1:numel(remaining)
                cand = remaining(ii);

                if load + G.q(cand+1) > G.Qmax(k)
                    continue;
                end

                [okStep, tArr, bArr] = simulate_step_feas(cur, cand, t, battery, k, G);
                if ~okStep
                    continue;
                end

                score = tArr + 0.001 * G.RT(cand+1);
                if score < bestScore
                    bestScore = score;
                    bestIdx = ii;
                    bestNextT = tArr;
                    bestNextB = bArr;
                end
            end

            if bestIdx == 0
                break;
            end

            nxt = remaining(bestIdx);
            remaining(bestIdx) = [];

            route(end+1) = nxt; %#ok<AGROW>
            load = load + G.q(nxt+1);

            t = bestNextT;
            if t < G.LT(nxt+1), t = G.LT(nxt+1); end
            t = t + G.ST;
            battery = bestNextB;
            cur = nxt;
        end

        routes{k} = route;
    end

    while ~isempty(remaining)
        lens = cellfun(@numel, routes);
        [~, kk] = min(lens);
        routes{kk} = [routes{kk}, remaining(1)];
        remaining(1) = [];
    end

    [perm, cuts] = merge_routes_to_perm_pub(routes, n, K);
    ch = [perm cuts];
    ch = repair_all_constraints(ch, n, K, 2, G);
end

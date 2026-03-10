function [bestCh, bestCost, stats] = post_improve_cv_only(ch0, cost0, G, opts)
% =========================================================================
% [模块] post_improve_cv_only
%  功能: CV-only 后处理优化入口
%  论文对应: 实现层
%  说明: 模块化版本,接受 G 参数而非 global.
% =========================================================================
stats = cv_only_init_stats();
bestCh = ch0;
bestCost = cost0;
if ~cv_only_enhance_enabled(G)
    return;
end
if nargin < 4 || isempty(opts)
    opts = struct();
end
if ~isfield(opts,'maxIter2optCVOnly'), opts.maxIter2optCVOnly = 2000; end
if ~isfield(opts,'cvOnlyCrossIters'), opts.cvOnlyCrossIters = 1000; end
if ~isfield(opts,'lnsIters'), opts.lnsIters = 120; end
if ~isfield(opts,'lnsDestroyMin'), opts.lnsDestroyMin = 3; end
if ~isfield(opts,'lnsDestroyMax'), opts.lnsDestroyMax = 7; end
if ~isfield(opts,'chainIters'), opts.chainIters = 120; end
if ~isfield(opts,'chainLenMin'), opts.chainLenMin = 2; end
if ~isfield(opts,'chainLenMax'), opts.chainLenMax = 4; end

% 1) 路内2-opt, 仅CV-only, 严格可行且降成本才接受
[bestCh, bestCost, stats] = cv_only_2opt_full(bestCh, bestCost, G, opts.maxIter2optCVOnly, stats);

% 2) 跨路径交换与kick
[bestCh, bestCost, stats] = cv_only_cross_improve(bestCh, bestCost, G, opts, stats);

% 3) LNS destroy-repair
[bestCh, bestCost, stats] = cv_only_lns_improve(bestCh, bestCost, G, opts, stats);

% 4) 多步链式重排
[bestCh, bestCost, stats] = cv_only_chain_improve(bestCh, bestCost, G, opts, stats);

stats = cv_only_stats_sync(stats);
end

% =========================================================================
% CV-only helper functions
% =========================================================================
function [bestCh, bestCost, stats] = cv_only_2opt_full(ch0, cost0, G, maxIter, stats)
n = G.n;
K = G.K;
bestCh = ch0;
bestCost = cost0;

perm = bestCh(1:n);
cuts = sort(bestCh(n+1:n+K-1));
cuts = max(1, min(n-1, cuts));
routes = split_perm_by_cuts_pub(perm, cuts, n, K);

for r = 1:K
    if numel(routes{r}) < 4
        continue;
    end
    iter = 0;
    improved = true;
    while improved && iter < maxIter
        improved = false;
        route = routes{r};
        for i = 1:(numel(route)-2)
            for j = (i+1):(numel(route)-1)
                newRoute = route;
                newRoute(i:j) = route(j:-1:i);
                stats.fail.twoOpt.try = stats.fail.twoOpt.try + 1;
                if cv_only_route_load(newRoute, G) > G.Qmax(r)
                    stats.fail.twoOpt.capacity = stats.fail.twoOpt.capacity + 1;
                    continue;
                end
                if ~cv_only_route_time_feasible(newRoute, G, r)
                    stats.fail.twoOpt.timewindow = stats.fail.twoOpt.timewindow + 1;
                    continue;
                end
                candRoutes = routes;
                candRoutes{r} = newRoute;
                [okImp, reason, f2, candFixed] = cv_only_eval_routes(candRoutes, G, bestCost);
                if okImp
                    bestCost = f2;
                    bestCh = candFixed;
                    permF = candFixed(1:n);
                    cutsF = sort(candFixed(n+1:n+K-1));
                    routes = split_perm_by_cuts_pub(permF, cutsF, n, K);
                    improved = true;
                    stats.fail.twoOpt.ok = stats.fail.twoOpt.ok + 1;
                    break;
                else
                    stats = cv_only_stats_add_reason(stats, 'twoOpt', reason);
                end
            end
            if improved, break; end
        end
        iter = iter + 1;
    end
end
end

function [bestCh, bestCost, stats] = cv_only_cross_improve(ch0, cost0, G, opts, stats)
bestCh = ch0;
bestCost = cost0;
if opts.cvOnlyCrossIters <= 0
    return;
end

n = G.n;
K = G.K;
perm = bestCh(1:n);
cuts = sort(bestCh(n+1:n+K-1));
routes = split_perm_by_cuts_pub(perm, cuts, n, K);

rs = RandStream('mt19937ar', 'Seed', 20260111);
stats.trials = 0;
for t = 1:opts.cvOnlyCrossIters
    nonEmpty = find(~cellfun(@isempty, routes));
    if numel(nonEmpty) < 2
        break;
    end
    r1 = nonEmpty(randi(rs, numel(nonEmpty)));
    r2 = nonEmpty(randi(rs, numel(nonEmpty)));
    if r1 == r2
        continue;
    end
    stats.trials = stats.trials + 1;

    opRoll = rand(rs);
    candRoutes = routes;
    opType = '';
    okGen = false;
    reasonGen = 'invalid';
    idxList = [r1 r2];

    if opRoll < 0.34
        opType = 'exch21';
        stats.fail.exch21.try = stats.fail.exch21.try + 1;
        [candRoutes, okGen, reasonGen] = cv_only_exchange_2_1(routes, r1, r2, G, rs);
    elseif opRoll < 0.68
        opType = 'exch12';
        stats.fail.exch12.try = stats.fail.exch12.try + 1;
        [candRoutes, okGen, reasonGen] = cv_only_exchange_2_1(routes, r2, r1, G, rs);
    elseif opRoll < 0.93
        opType = 'swap22';
        stats.fail.swap22.try = stats.fail.swap22.try + 1;
        [candRoutes, okGen, reasonGen] = cv_only_swap_2_2(routes, r1, r2, G, rs);
    else
        opType = 'kick';
        stats.fail.kick.try = stats.fail.kick.try + 1;
        [candRoutes, okGen, reasonGen, idxList] = cv_only_kick_chain(routes, r1, r2, G, rs);
    end

    if ~okGen
        stats = cv_only_stats_add_reason(stats, opType, reasonGen);
        continue;
    end

    localIter = min(opts.maxIter2optCVOnly, 200);
    [candRoutes, cnt2opt] = cv_only_2opt_routes_local(candRoutes, idxList, G, localIter);
    if cnt2opt > 0
        stats.fail.twoOpt.ok = stats.fail.twoOpt.ok + cnt2opt;
        stats.fail.twoOpt.try = stats.fail.twoOpt.try + cnt2opt;
    end

    [okImp, reason, f2, candFixed] = cv_only_eval_routes(candRoutes, G, bestCost);
    if okImp
        bestCost = f2;
        bestCh = candFixed;
        permF = candFixed(1:n);
        cutsF = sort(candFixed(n+1:n+K-1));
        routes = split_perm_by_cuts_pub(permF, cutsF, n, K);
        switch opType
            case 'exch21'
                stats.fail.exch21.ok = stats.fail.exch21.ok + 1;
            case 'exch12'
                stats.fail.exch12.ok = stats.fail.exch12.ok + 1;
            case 'swap22'
                stats.fail.swap22.ok = stats.fail.swap22.ok + 1;
            case 'kick'
                stats.fail.kick.ok = stats.fail.kick.ok + 1;
        end
    else
        stats = cv_only_stats_add_reason(stats, opType, reason);
    end
end
end

function [bestCh, bestCost, stats] = cv_only_lns_improve(bestCh, bestCost, G, opts, stats)
if ~isfield(opts,'lnsIters') || opts.lnsIters <= 0
    return;
end
n = G.n;
K = G.K;
perm = bestCh(1:n);
cuts = sort(bestCh(n+1:n+K-1));
routes = split_perm_by_cuts_pub(perm, cuts, n, K);
rs = RandStream('mt19937ar', 'Seed', 20260118);
localIter = min(opts.maxIter2optCVOnly, 200);
for t = 1:opts.lnsIters
    stats.fail.lns.try = stats.fail.lns.try + 1;
    numDestroy = randi(rs, [opts.lnsDestroyMin, opts.lnsDestroyMax]);
    [routes2, removed, affected] = cv_only_destroy_random(routes, numDestroy, rs);
    if isempty(removed)
        stats.fail.lns.invalid = stats.fail.lns.invalid + 1;
        continue;
    end
    [routes3, okRep, reasonRep, affected2] = cv_only_repair_cheapest_insertion(routes2, removed, G, rs);
    if ~okRep
        stats = cv_only_stats_add_reason(stats, 'lns', reasonRep);
        continue;
    end
    affectedAll = unique([affected affected2]);
    if ~isempty(affectedAll)
        [routes3, cnt2opt] = cv_only_2opt_routes_local(routes3, affectedAll, G, localIter);
        if cnt2opt > 0
            stats.fail.twoOpt.ok = stats.fail.twoOpt.ok + cnt2opt;
            stats.fail.twoOpt.try = stats.fail.twoOpt.try + cnt2opt;
        end
    end
    [okImp, reason, f2, candFixed] = cv_only_eval_routes(routes3, G, bestCost);
    if okImp
        bestCost = f2;
        bestCh = candFixed;
        perm = bestCh(1:n);
        cuts = sort(bestCh(n+1:n+K-1));
        routes = split_perm_by_cuts_pub(perm, cuts, n, K);
        stats.fail.lns.ok = stats.fail.lns.ok + 1;
    else
        stats = cv_only_stats_add_reason(stats, 'lns', reason);
    end
end
end

function [bestCh, bestCost, stats] = cv_only_chain_improve(bestCh, bestCost, G, opts, stats)
if ~isfield(opts,'chainIters') || opts.chainIters <= 0
    return;
end
n = G.n;
K = G.K;
perm = bestCh(1:n);
cuts = sort(bestCh(n+1:n+K-1));
routes = split_perm_by_cuts_pub(perm, cuts, n, K);
rs = RandStream('mt19937ar', 'Seed', 20260119);
localIter = min(opts.maxIter2optCVOnly, 200);
for t = 1:opts.chainIters
    stats.fail.chain.try = stats.fail.chain.try + 1;
    lenMin = max(1, opts.chainLenMin);
    lenMax = max(lenMin, opts.chainLenMax);
    chainLen = randi(rs, [lenMin lenMax]);
    [routes2, removed, affected] = cv_only_remove_chain(routes, chainLen, rs);
    if isempty(removed)
        stats.fail.chain.invalid = stats.fail.chain.invalid + 1;
        continue;
    end
    [routes3, okRep, reasonRep, affected2] = cv_only_repair_cheapest_insertion(routes2, removed, G, rs);
    if ~okRep
        stats = cv_only_stats_add_reason(stats, 'chain', reasonRep);
        continue;
    end
    affectedAll = unique([affected affected2]);
    if ~isempty(affectedAll)
        [routes3, cnt2opt] = cv_only_2opt_routes_local(routes3, affectedAll, G, localIter);
        if cnt2opt > 0
            stats.fail.twoOpt.ok = stats.fail.twoOpt.ok + cnt2opt;
            stats.fail.twoOpt.try = stats.fail.twoOpt.try + cnt2opt;
        end
    end
    [okImp, reason, f2, candFixed] = cv_only_eval_routes(routes3, G, bestCost);
    if okImp
        bestCost = f2;
        bestCh = candFixed;
        perm = bestCh(1:n);
        cuts = sort(bestCh(n+1:n+K-1));
        routes = split_perm_by_cuts_pub(perm, cuts, n, K);
        stats.fail.chain.ok = stats.fail.chain.ok + 1;
    else
        stats = cv_only_stats_add_reason(stats, 'chain', reason);
    end
end
end

% =========================================================================
% Stats & Helper functions
% =========================================================================
function stats = cv_only_init_stats()
stats = struct();
stats.fail = struct();
opList = {'twoOpt','exch21','exch12','swap22','kick','lns','chain'};
for i = 1:numel(opList)
    stats.fail.(opList{i}) = cv_only_init_fail();
end
stats.trials = 0;
stats.exch21Tried = 0; stats.exch21Accepted = 0;
stats.exch12Tried = 0; stats.exch12Accepted = 0;
stats.swap22Tried = 0; stats.swap22Accepted = 0;
stats.kickTried = 0; stats.kickAccepted = 0;
stats.lnsTried = 0; stats.lnsAccepted = 0;
stats.chainTried = 0; stats.chainAccepted = 0;
stats.twoOptAccepted = 0;
end

function s = cv_only_init_fail()
s = struct('try',0,'ok',0,'duplicate',0,'missing',0, ...
    'capacity',0,'timewindow',0,'invalid',0,'noImprove',0);
end

function stats = cv_only_stats_sync(stats)
stats.exch21Tried = stats.fail.exch21.try;
stats.exch21Accepted = stats.fail.exch21.ok;
stats.exch12Tried = stats.fail.exch12.try;
stats.exch12Accepted = stats.fail.exch12.ok;
stats.swap22Tried = stats.fail.swap22.try;
stats.swap22Accepted = stats.fail.swap22.ok;
stats.kickTried = stats.fail.kick.try;
stats.kickAccepted = stats.fail.kick.ok;
stats.lnsTried = stats.fail.lns.try;
stats.lnsAccepted = stats.fail.lns.ok;
stats.chainTried = stats.fail.chain.try;
stats.chainAccepted = stats.fail.chain.ok;
stats.twoOptAccepted = stats.fail.twoOpt.ok;
end

function stats = cv_only_stats_add_reason(stats, opName, reason)
if nargin < 3 || isempty(reason)
    return;
end
if strcmpi(reason, 'ok')
    return;
end
if ~isfield(stats.fail, opName)
    return;
end
if ~isfield(stats.fail.(opName), reason)
    reason = 'invalid';
end
stats.fail.(opName).(reason) = stats.fail.(opName).(reason) + 1;
end

function load = cv_only_route_load(route, G)
if isempty(route)
    load = 0;
    return;
end
load = sum(G.q(route+1));
end

function ok = cv_only_route_time_feasible(route, G, k)
ok = true;
if isempty(route)
    return;
end
time = 0;
cur = 0;
for ii = 1:numel(route)
    toNode = route(ii);
    d = G.D(cur+1, toNode+1);
    time = time + d / G.Speed(k);
    if time > G.RT(toNode+1)
        ok = false;
        return;
    end
    if time < G.LT(toNode+1)
        time = G.LT(toNode+1);
    end
    time = time + G.ST;
    cur = toNode;
end
end

function [okImp, reason, f2, candFixed] = cv_only_eval_routes(routes, G, bestCost)
okImp = false;
reason = 'invalid';
f2 = inf;
candFixed = [];
[okFeas, reasonFeas] = cv_only_check_routes(routes, G);
n = G.n; K = G.K;
[perm2, cuts2] = merge_routes_to_perm_pub(routes, n, K);
[f2, fe2, candFixed] = fitness_strict_penalty([perm2 cuts2], G);
if ~fe2
    candRepair = repair_all_constraints([perm2 cuts2], n, K, 2, G);
    [f2, fe2, candFixed] = fitness_strict_penalty(candRepair, G);
end
if fe2 && (f2 < bestCost - 1e-9)
    okImp = true;
    reason = 'ok';
else
    if ~fe2
        if okFeas
            reason = 'invalid';
        else
            reason = reasonFeas;
        end
    else
        reason = 'noImprove';
    end
end
end

function [ok, reason] = cv_only_check_routes(routes, G)
ok = false;
reason = 'invalid';
n = G.n;
K = G.K;
if ~iscell(routes) || numel(routes) ~= K
    return;
end
allCust = [];
for k = 1:K
    route = routes{k};
    if isempty(route)
        continue;
    end
    if any(~isfinite(route)) || any(route < 1) || any(route > n) || any(mod(route,1) ~= 0)
        return;
    end
    if any(route == 0)
        return;
    end
    allCust = [allCust route(:)']; %#ok<AGROW>
end
if numel(allCust) ~= numel(unique(allCust))
    reason = 'duplicate';
    return;
end
if numel(allCust) ~= n
    reason = 'missing';
    return;
end
for k = 1:K
    route = routes{k};
    if cv_only_route_load(route, G) > G.Qmax(k)
        reason = 'capacity';
        return;
    end
    if ~cv_only_route_time_feasible(route, G, k)
        reason = 'timewindow';
        return;
    end
end
ok = true;
reason = 'ok';
end

function [routes, cnt2opt] = cv_only_2opt_routes_local(routes, idxList, G, maxIter)
idxList = unique(idxList);
cnt2opt = 0;
for ii = 1:numel(idxList)
    r = idxList(ii);
    [routes{r}, cntR] = cv_only_2opt_route_det(routes{r}, G, maxIter, r);
    cnt2opt = cnt2opt + cntR;
end
end

function [route2, improveCount] = cv_only_2opt_route_det(route, G, maxIter, rIdx)
route2 = route;
improveCount = 0;
if numel(route2) < 4 || maxIter <= 0
    return;
end
iter = 0;
while iter < maxIter
    iter = iter + 1;
    improved = false;
    for i = 1:(numel(route2)-2)
        for j = (i+1):(numel(route2)-1)
            cand = route2;
            cand(i:j) = route2(j:-1:i);
            if cv_only_route_len(cand, G) + 1e-9 < cv_only_route_len(route2, G) && ...
                    cv_only_route_time_feasible(cand, G, rIdx)
                route2 = cand;
                improved = true;
                improveCount = improveCount + 1;
                break;
            end
        end
        if improved, break; end
    end
    if ~improved
        break;
    end
end
end

function L = cv_only_route_len(route, G)
if isempty(route)
    L = 0;
    return;
end
seq = [0 route(:)' 0];
L = route_len(seq, G.coord);
end

% =========================================================================
% Exchange operators
% =========================================================================
function [routesOut, ok, reason] = cv_only_exchange_2_1(routesIn, rA, rB, G, rs)
routesOut = routesIn;
ok = false;
reason = 'invalid';
ra = routesIn{rA};
rb = routesIn{rB};
if numel(ra) < 2 || numel(rb) < 1
    return;
end
permA = randperm(rs, numel(ra));
idxA = sort(permA(1:2));
permB = randperm(rs, numel(rb));
idxB = permB(1);
custA = ra(idxA);
custB = rb(idxB);
loadA = cv_only_route_load(ra, G);
loadB = cv_only_route_load(rb, G);
needA = sum(G.q(custA+1));
needB = G.q(custB+1);
newLoadA = loadA - needA + needB;
newLoadB = loadB - needB + needA;
if newLoadA > G.Qmax(rA) || newLoadB > G.Qmax(rB)
    reason = 'capacity';
    return;
end
ra = cv_only_remove_indices(ra, idxA);
rb = cv_only_remove_indices(rb, idxB);
ra = cv_only_insert_items(ra, custB, randi(rs, numel(ra)+1)-1);
rb = cv_only_insert_items(rb, custA, randi(rs, numel(rb)+1)-1);
routesOut{rA} = ra;
routesOut{rB} = rb;
ok = true;
reason = 'ok';
end

function [routesOut, ok, reason] = cv_only_swap_2_2(routesIn, rA, rB, G, rs)
routesOut = routesIn;
ok = false;
reason = 'invalid';
ra = routesIn{rA};
rb = routesIn{rB};
if numel(ra) < 2 || numel(rb) < 2
    return;
end
permA = randperm(rs, numel(ra));
idxA = sort(permA(1:2));
permB = randperm(rs, numel(rb));
idxB = sort(permB(1:2));
custA = ra(idxA);
custB = rb(idxB);
loadA = cv_only_route_load(ra, G);
loadB = cv_only_route_load(rb, G);
needA = sum(G.q(custA+1));
needB = sum(G.q(custB+1));
newLoadA = loadA - needA + needB;
newLoadB = loadB - needB + needA;
if newLoadA > G.Qmax(rA) || newLoadB > G.Qmax(rB)
    reason = 'capacity';
    return;
end
ra = cv_only_remove_indices(ra, idxA);
rb = cv_only_remove_indices(rb, idxB);
ra = cv_only_insert_items(ra, custB, randi(rs, numel(ra)+1)-1);
rb = cv_only_insert_items(rb, custA, randi(rs, numel(rb)+1)-1);
routesOut{rA} = ra;
routesOut{rB} = rb;
ok = true;
reason = 'ok';
end

function [routesOut, ok, reason, idxList] = cv_only_kick_chain(routesIn, rA, rB, G, rs)
routesOut = routesIn;
ok = false;
reason = 'invalid';
idxList = [rA rB];
nonEmpty = find(~cellfun(@isempty, routesIn));
if numel(nonEmpty) < 3
    return;
end
ra = routesIn{rA};
rb = routesIn{rB};
if isempty(ra) || isempty(rb)
    return;
end
rcIdx = nonEmpty(randi(rs, numel(nonEmpty)));
while rcIdx == rA || rcIdx == rB
    rcIdx = nonEmpty(randi(rs, numel(nonEmpty)));
end
rc = routesIn{rcIdx};
if isempty(rc)
    return;
end

posA = randi(rs, numel(ra));
posB = randi(rs, numel(rb));
custA = ra(posA);
custB = rb(posB);
loadA = cv_only_route_load(ra, G) - G.q(custA+1);
loadB = cv_only_route_load(rb, G) - G.q(custB+1) + G.q(custA+1);
loadC = cv_only_route_load(rc, G) + G.q(custB+1);
if loadA > G.Qmax(rA) || loadB > G.Qmax(rB) || loadC > G.Qmax(rcIdx)
    reason = 'capacity';
    return;
end

ra = cv_only_remove_indices(ra, posA);
rb = cv_only_remove_indices(rb, posB);
rb = cv_only_insert_items(rb, custA, randi(rs, numel(rb)+1)-1);
rc = cv_only_insert_items(rc, custB, randi(rs, numel(rc)+1)-1);

routesOut{rA} = ra;
routesOut{rB} = rb;
routesOut{rcIdx} = rc;
idxList = [rA rB rcIdx];
ok = true;
reason = 'ok';
end

function route2 = cv_only_insert_items(route, items, pos)
items = items(:).';
if isempty(items)
    route2 = route;
    return;
end
if pos <= 0
    route2 = [items route];
elseif pos >= numel(route)
    route2 = [route items];
else
    route2 = [route(1:pos) items route(pos+1:end)];
end
end

function route2 = cv_only_remove_indices(route, idx)
if isempty(idx)
    route2 = route;
    return;
end
idx = sort(idx(:).', 'descend');
route2 = route;
route2(idx) = [];
end

% =========================================================================
% Destroy/Repair for LNS
% =========================================================================
function [routes2, removed, affected] = cv_only_destroy_random(routes, numDestroy, rs)
routes2 = routes;
removed = [];
affected = [];
K = numel(routes);
allCust = [];
for k = 1:K
    allCust = [allCust routes{k}(:)']; %#ok<AGROW>
end
if numel(allCust) < numDestroy
    numDestroy = numel(allCust);
end
if numDestroy <= 0
    return;
end
perm = randperm(rs, numel(allCust));
removed = allCust(perm(1:numDestroy));
for k = 1:K
    r = routes2{k};
    mask = ismember(r, removed);
    if any(mask)
        routes2{k} = r(~mask);
        affected(end+1) = k; %#ok<AGROW>
    end
end
affected = unique(affected);
end

function [routes2, removed, affected] = cv_only_remove_chain(routes, chainLen, rs)
routes2 = routes;
removed = [];
affected = [];
K = numel(routes);
nonEmpty = find(~cellfun(@isempty, routes));
if isempty(nonEmpty)
    return;
end
kStart = nonEmpty(randi(rs, numel(nonEmpty)));
r = routes{kStart};
if numel(r) < chainLen
    chainLen = numel(r);
end
if chainLen <= 0
    return;
end
startPos = randi(rs, numel(r) - chainLen + 1);
removed = r(startPos:(startPos + chainLen - 1));
routes2{kStart} = r([1:(startPos-1), (startPos+chainLen):end]);
affected = kStart;
end

function [routes3, ok, reason, affected2] = cv_only_repair_cheapest_insertion(routes2, removed, G, ~)
routes3 = routes2;
ok = true;
reason = 'ok';
affected2 = [];
for ii = 1:numel(removed)
    cust = removed(ii);
    bestK = 0;
    bestPos = 0;
    bestDelta = inf;
    for k = 1:numel(routes3)
        r = routes3{k};
        load = cv_only_route_load(r, G);
        demand = G.q(cust+1);
        if load + demand > G.Qmax(k)
            continue;
        end
        for p = 0:numel(r)
            cand = cv_only_insert_items(r, cust, p);
            if ~cv_only_route_time_feasible(cand, G, k)
                continue;
            end
            delta = cv_only_route_len(cand, G) - cv_only_route_len(r, G);
            if delta < bestDelta
                bestDelta = delta;
                bestK = k;
                bestPos = p;
            end
        end
    end
    if bestK > 0
        routes3{bestK} = cv_only_insert_items(routes3{bestK}, cust, bestPos);
        affected2(end+1) = bestK; %#ok<AGROW>
    else
        ok = false;
        reason = 'capacity';
        return;
    end
end
affected2 = unique(affected2);
end

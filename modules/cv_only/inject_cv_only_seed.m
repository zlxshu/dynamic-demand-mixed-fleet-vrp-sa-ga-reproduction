function PopSeed = inject_cv_only_seed(n, K, G, injectCount)
% inject_cv_only_seed - Generate CV-only seed population (opt27-style).
% Returns PopSeed: [injectCount x (n+K-1)] chromosomes.

PopSeed = [];
if injectCount <= 0 || n <= 0 || K <= 0
    return;
end

custCoords = G.coord(2:n+1, :);
depot = G.coord(1, :);
ang = atan2(custCoords(:,2) - depot(2), custCoords(:,1) - depot(1));
[~, baseOrder] = sort(ang);

PopSeed = zeros(injectCount, n + (K-1));
stride = max(1, floor(n / max(1, injectCount)));

seed2optIter = 200;
try
    if isfield(G,'cvOnlyOpt') && isfield(G.cvOnlyOpt,'seed2optIter')
        seed2optIter = G.cvOnlyOpt.seed2optIter;
    end
catch
end

for s = 1:injectCount
    shift = mod((s-1) * stride, n);
    order = circshift(baseOrder, -shift);

    [routes, okGreedy] = cv_only_build_routes_greedy_(order, G, K);
    if ~okGreedy
        routes = cv_only_split_by_capacity_(order, G, K);
        for k = 1:K
            routes{k} = cv_only_nearest_neighbor_(routes{k}, G);
        end
    end

    if seed2optIter > 0
        routes = cv_only_2opt_routes_dist_(routes, G, seed2optIter);
    end

    [perm, cuts] = merge_routes_to_perm_pub(routes, n, K);
    ch = [perm cuts];
    ch = repair_chromosome_deterministic(ch, n, K, G);
    PopSeed(s,:) = ch;
end
end

% ======================== local helpers ========================
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

function route2 = cv_only_nearest_neighbor_(route, G)
route2 = route;
if numel(route2) <= 2
    return;
end
unvisited = route2(:)';
route2 = [];
cur = 0; % depot
while ~isempty(unvisited)
    d = G.D(cur+1, unvisited+1);
    [~, idx] = min(d);
    nxt = unvisited(idx);
    route2(end+1) = nxt; %#ok<AGROW>
    cur = nxt;
    unvisited(idx) = [];
end
end

function [routes, ok] = cv_only_build_routes_greedy_(order, G, K)
routes = cell(1, K);
Qmax = G.Qmax;
load = zeros(1, K);
ok = true;

for ii = 1:numel(order)
    cust = order(ii);
    demand = G.q(cust+1);
    placed = false;

    bestK = 0;
    bestDelta = inf;
    for k = 1:K
        if load(k) + demand <= Qmax(k)
            r = routes{k};
            if isempty(r)
                delta = 2 * G.D(1, cust+1); % depot-cust-depot
            else
                delta = G.D(r(end)+1, cust+1) + G.D(cust+1, 1) - G.D(r(end)+1, 1);
            end
            if delta < bestDelta
                bestDelta = delta;
                bestK = k;
            end
        end
    end

    if bestK > 0
        routes{bestK}(end+1) = cust; %#ok<AGROW>
        load(bestK) = load(bestK) + demand;
        placed = true;
    end

    if ~placed
        ok = false;
        [~, minK] = min(load);
        routes{minK}(end+1) = cust; %#ok<AGROW>
        load(minK) = load(minK) + demand;
    end
end
end

function routes2 = cv_only_2opt_routes_dist_(routes, G, localIter)
routes2 = routes;
K = numel(routes2);
for k = 1:K
    route = routes2{k};
    if numel(route) < 4
        continue;
    end
    iter = 0;
    improved = true;
    while improved && iter < localIter
        improved = false;
        for i = 1:(numel(route)-2)
            for j = (i+1):(numel(route)-1)
                cand = route;
                cand(i:j) = route(j:-1:i);
                if route_dist_(cand, G) + 1e-9 < route_dist_(route, G)
                    route = cand;
                    improved = true;
                    break;
                end
            end
            if improved, break; end
        end
        iter = iter + 1;
    end
    routes2{k} = route;
end
end

function d = route_dist_(route, G)
if isempty(route)
    d = 0;
    return;
end
idx = [0 route(:)' 0];
d = 0;
for t = 1:(numel(idx)-1)
    d = d + G.D(idx(t)+1, idx(t+1)+1);
end
end


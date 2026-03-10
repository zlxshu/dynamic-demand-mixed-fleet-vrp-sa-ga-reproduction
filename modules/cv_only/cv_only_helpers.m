function tf = cv_only_case(G)
% =========================================================================
% [模块] cv_only_case
%  功能: 判断是否为 CV-only 场景(无EV).
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
tf = isfield(G,'nEV') && isfield(G,'nCV') && (G.nEV == 0) && (G.nCV > 0);
end

function tf = cv_only_enhance_enabled(G)
% =========================================================================
% [模块] cv_only_enhance_enabled
%  功能: 判断是否启用 CV-only 增强优化.
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
tf = cv_only_case(G) && isfield(G,'cvOnlyOpt') && isfield(G.cvOnlyOpt,'enableCVOnlyImprove') && ...
    G.cvOnlyOpt.enableCVOnlyImprove;
end

function ch2 = cv_only_apply_capacity_cuts(ch, n, K, G)
% =========================================================================
% [模块] cv_only_apply_capacity_cuts
%  功能: 根据容量约束重新切分 CV-only 染色体.
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
perm = ch(1:n);
routes = cv_only_split_by_capacity(perm, G, K);
[perm2, cuts2] = merge_routes_to_perm_pub(routes, n, K);
ch2 = [perm2 cuts2];
ch2 = repair_chromosome_deterministic(ch2, n, K, G);
end

function routes = cv_only_split_by_capacity(order, G, K)
% =========================================================================
% [模块] cv_only_split_by_capacity
%  功能: 按容量切分 order 为 K 条路线.
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
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

function route2 = cv_only_nearest_neighbor(route, G)
% =========================================================================
% [模块] cv_only_nearest_neighbor
%  功能: 最近邻启发式重排单条路线.
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
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

function PopSeed = inject_cv_only_seed(n, K, G, injectCount)
% =========================================================================
% [模块] inject_cv_only_seed
%  功能: 生成 CV-only 种子个体(基于角度排序+贪心).
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
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
if isfield(G,'cvOnlyOpt') && isfield(G.cvOnlyOpt,'seed2optIter')
    seed2optIter = G.cvOnlyOpt.seed2optIter;
end
for s = 1:injectCount
    shift = mod((s-1) * stride, n);
    order = circshift(baseOrder, -shift);
    [routes, okGreedy] = cv_only_build_routes_greedy(order, G);
    if ~okGreedy
        routes = cv_only_split_by_capacity(order, G, K);
        for k = 1:K
            routes{k} = cv_only_nearest_neighbor(routes{k}, G);
        end
    end
    if seed2optIter > 0
        [routes, ~] = cv_only_2opt_routes(routes, 1:K, G, seed2optIter);
    end
    [perm, cuts] = merge_routes_to_perm_pub(routes, n, K);
    PopSeed(s,:) = [perm cuts];
end
end

function [routes, ok] = cv_only_build_routes_greedy(order, G)
% =========================================================================
% [模块] cv_only_build_routes_greedy
%  功能: CV-only 贪心建路.
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
K = G.K;
routes = cell(1, K);
Qmax = G.Qmax;
load = zeros(1, K);
ok = true;

for ii = 1:numel(order)
    cust = order(ii);
    demand = G.q(cust+1);
    placed = false;
    
    % 找容量允许的最优路线
    bestK = 0;
    bestDelta = inf;
    for k = 1:K
        if load(k) + demand <= Qmax(k)
            r = routes{k};
            if isempty(r)
                delta = 2 * G.D(1, cust+1); % depot-cust-depot
            else
                % 插入末尾
                delta = G.D(r(end)+1, cust+1) + G.D(cust+1, 1) - G.D(r(end)+1, 1);
            end
            if delta < bestDelta
                bestDelta = delta;
                bestK = k;
            end
        end
    end
    
    if bestK > 0
        routes{bestK}(end+1) = cust;
        load(bestK) = load(bestK) + demand;
        placed = true;
    end
    
    if ~placed
        ok = false;
        % fallback: 放入负载最少的路线
        [~, minK] = min(load);
        routes{minK}(end+1) = cust;
        load(minK) = load(minK) + demand;
    end
end
end

function [routes2, cnt2opt] = cv_only_2opt_routes(routes, affected, G, localIter)
% =========================================================================
% [模块] cv_only_2opt_routes
%  功能: 对 affected 中指定的路线做 2-opt 局部搜索.
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
routes2 = routes;
cnt2opt = 0;
for k = affected
    r = routes2{k};
    if numel(r) < 3
        continue;
    end
    
    improved = true;
    iter = 0;
    while improved && iter < localIter
        improved = false;
        iter = iter + 1;
        
        n_r = numel(r);
        for i = 1:(n_r-2)
            for j = (i+2):n_r
                % 计算反转增益
                if i == 1
                    a_prev = 0;
                else
                    a_prev = r(i-1);
                end
                a = r(i);
                b = r(j);
                if j == n_r
                    b_next = 0;
                else
                    b_next = r(j+1);
                end
                
                oldCost = G.D(a_prev+1, a+1) + G.D(b+1, b_next+1);
                newCost = G.D(a_prev+1, b+1) + G.D(a+1, b_next+1);
                
                if newCost < oldCost - 1e-9
                    r(i:j) = r(j:-1:i);
                    improved = true;
                    cnt2opt = cnt2opt + 1;
                    break;
                end
            end
            if improved
                break;
            end
        end
    end
    routes2{k} = r;
end
end

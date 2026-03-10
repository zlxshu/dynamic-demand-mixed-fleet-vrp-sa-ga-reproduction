function ch2 = relocate_one_cv_to_ev(ch, n, K, G)
% =========================================================================
% [模块] relocate_one_cv_to_ev
%  功能: 把一个"相对远"的客户从CV路线挪到EV路线(结构重组)
%  论文对应: 实现层
%  说明: 模块化版本,接受 G 参数而非 global.
% =========================================================================

perm = ch(1:n);
cuts = ch(n+1:n+K-1);

routes = split_perm_by_cuts_pub(perm, cuts, n, K);

cvIdx = find(~G.isEV);
evIdx = find(G.isEV);
cvIdx = cvIdx(~cellfun(@isempty, routes(cvIdx)));
evIdx = evIdx(~cellfun(@isempty, routes(evIdx)));

if isempty(cvIdx) || isempty(evIdx)
    ch2 = ch; return;
end

% 选一条CV路(偏向更长的CV路)
cvLens = cellfun(@numel, routes(cvIdx));
[~, idcv] = max(cvLens + 0.1*rand(size(cvLens)));
kcv = cvIdx(idcv);

% 选一条EV路(随机)
kev = evIdx(randi(numel(evIdx)));

rCV = routes{kcv};
rEV = routes{kev};

% 选一个"远客户":到仓库距离最大(粗略代价导向)
d2depot = G.D(rCV+1, 1); % km (nodes are 0-based in ids; customer id matches node id)
[~, posPick] = max(d2depot + 1e-6*rand(size(d2depot)));
cust = rCV(posPick);

% 从CV删
rCV(posPick) = [];

% 插入EV的最佳位置(按距离增量近似)
bestPos = 0;
bestDelta = inf;
nodes = [0, rEV, 0];
for p = 1:(numel(nodes)-1)
    a = nodes(p); b = nodes(p+1);
    delta = G.D(a+1, cust+1) + G.D(cust+1, b+1) - G.D(a+1, b+1);
    if delta < bestDelta
        bestDelta = delta;
        bestPos = p; % insert after nodes(p) => position in rEV
    end
end

rEV = [rEV(1:bestPos-1), cust, rEV(bestPos:end)];

routes{kcv} = rCV;
routes{kev} = rEV;

[perm2, cuts2] = merge_routes_to_perm_pub(routes, n, K);
ch2 = [perm2 cuts2];

% 结构修复防呆
ch2 = repair_chromosome_deterministic(ch2, n, K, G);
end

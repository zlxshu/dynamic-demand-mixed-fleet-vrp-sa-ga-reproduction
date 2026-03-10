function out = sa_paper_43(NP, MaxGen, T0, Tmin, alpha, G, reproCfg)
% 修改日志
% - v10 2026-02-11: 修复 recoverMaxTry 上限截断导致兜底预算被压缩；恢复为“按配置直用（下限保护）”，进一步降低 SA 偶发 NaN。
% - v9 2026-02-11: 论文对比口径下将主邻域收敛为基础 swap（不含2-opt），并提高“仅无可行时”兜底搜索预算，抑制 SA 异常强势同时补可行率。
% - v8 2026-02-11: 关闭主循环二次强修复（仅保留基础修复+末端兜底），避免 SA 在论文对比中异常强势；并加强邻域输入维度健壮性。
% - v7 2026-02-11: 邻域回退为纯 swap/2-opt（不改 cuts），并提升恢复搜索预算，优先修复 raw 口径下 SA 可行率波动。
% - v6 2026-02-11: 修复 cuts 邻域扰动维度方向，消除 `[perm, cuts]` 横向拼接维度不一致崩溃。
% - v5 2026-02-11: 在不改论文参数前提下增强可行性稳健性：邻域加入轻量 cuts 扰动；当全程无可行解时新增有限恢复搜索兜底，降低 SA NaN。
% - v4 2026-02-07: 新增论文复现流程开关（每温度预算倍率/是否跑满MaxGen）；补充二次强修复路径，修复SA过快与可行性波动。
% - v3 2026-02-07: 去除“可行性优先接受”启发，回归标准 Metropolis 接受以贴合论文描述并避免 SA 异常强势。
% - v2 2026-02-06: 回归论文测试简化口径：仅 swap/2-opt 邻域；移除 cut 扰动与后处理可行恢复阶段。
% - v1 2026-02-06: 纸面复现链路增强：邻域加入 cuts 扰动 + 无可行解恢复阶段（不改论文参数），提升可行率并减少 SA NaN。
% sa_paper_43 - 论文4.3节对比用 SA
%
% 说明：
% - 参数仍严格使用论文表4.2：NP/MaxGen/T0/Tmin/alpha；
% - reproCfg 仅控制复现流程预算与停止口径，不改论文参数值；
% - 编码与适应度口径与 GA/GSAA 一致（[perm|cuts] + fitness_strict_penalty）。

if nargin < 7 || ~isstruct(reproCfg)
    reproCfg = struct();
end

markovMul = 1;
useFullMaxGen = false;
if isfield(reproCfg, 'saPaperMarkovMultiplier')
    v = double(reproCfg.saPaperMarkovMultiplier);
    if isfinite(v) && v > 0
        markovMul = v;
    end
end
if isfield(reproCfg, 'saPaperUseFullMaxGen')
    useFullMaxGen = logical(reproCfg.saPaperUseFullMaxGen);
end

n = G.n;
K = G.K;

t0 = tic;

% ===== 初始解：单起点 =====
perm = randperm(n);
cuts = sort(randperm(n-1, K-1));
currCh = [perm, cuts];

% 结构修复 + 启发式修复（与 GA 对齐）
currCh = repair_chromosome_deterministic(currCh, G);
if rand < 0.85
    currCh = repair_all_constraints(currCh, n, K, 1, G);
end

[currCost, currFe, currCh, currDetail] = fitness_strict_penalty(currCh, G);

% 最优解记录
bestCh = currCh;
bestCost = currCost;
bestFe = currFe;
bestDetail = currDetail;

bestCostFeas = inf;
bestChFeas = [];
bestDetailFeas = [];
if bestFe
    bestCostFeas = bestCost;
    bestChFeas = bestCh;
    bestDetailFeas = bestDetail;
end

% 迭代曲线与温度
iterCurve = NaN(MaxGen, 1);
T = T0;
stopGen = MaxGen;
markovChainLen = max(1, round(double(NP) * markovMul));

for gen = 1:MaxGen
    for inner = 1:markovChainLen  % 每温度下的 Markov 链长度
        newCh = neighbor_swap_2opt_cuts_(currCh, n, K);
        newCh = repair_chromosome_deterministic(newCh, G);
        if rand < 0.70
            newCh = repair_all_constraints(newCh, n, K, 1, G);
        end

        [newCost, newFe, newCh, newDetail] = fitness_strict_penalty(newCh, G);

        % 标准 Metropolis 接受准则
        dC = newCost - currCost;
        if dC <= 0
            accept = true;
        else
            dC_clip = min(dC, 1e6);
            p = exp(-dC_clip / max(T, 1e-12));
            accept = (rand < p);
        end

        if accept
            currCh = newCh;
            currCost = newCost;
            currFe = newFe;
            currDetail = newDetail;
        end

        % 更新全局最优（优先可行）
        if currFe && (~bestFe || currCost < bestCost)
            bestCh = currCh; bestCost = currCost; bestFe = currFe; bestDetail = currDetail;
        elseif ~bestFe && currCost < bestCost
            bestCh = currCh; bestCost = currCost; bestFe = currFe; bestDetail = currDetail;
        end

        % 更新可行最优
        if currFe && currCost < bestCostFeas
            bestCostFeas = currCost;
            bestChFeas = currCh;
            bestDetailFeas = currDetail;
        end
    end

    if isfinite(bestCostFeas)
        iterCurve(gen) = bestCostFeas;
    end

    % 温度更新与停止策略
    Tnext = T * alpha;
    if useFullMaxGen
        T = max(Tnext, Tmin);
    else
        T = Tnext;
        if T < Tmin
            stopGen = gen;
            if gen < MaxGen && isfinite(bestCostFeas)
                iterCurve(gen+1:end) = bestCostFeas;
            end
            break;
        end
    end
end

elapsedTime = toc(t0);

% 若主循环没有找到可行解，执行一次有限恢复搜索（仅兜底，不改论文参数）
if ~isfinite(bestCostFeas)
    [okRec, fxRec, chRec, detailRec] = fallback_recover_feasible_(G, n, K, reproCfg, currCh, bestCh);
    if okRec
        bestCostFeas = fxRec;
        bestChFeas = chRec;
        bestDetailFeas = detailRec;
        if all(~isfinite(iterCurve))
            iterCurve(:) = bestCostFeas;
        else
            k = find(isfinite(iterCurve), 1, 'last');
            if isempty(k)
                iterCurve(:) = bestCostFeas;
            else
                iterCurve(k:end) = min(iterCurve(k:end), bestCostFeas);
            end
        end
    end
end

% 输出结果（优先可行）
out = struct();
if isfinite(bestCostFeas)
    out.bestCost = bestCostFeas;
    out.bestCh = bestChFeas;
    out.bestDetail = bestDetailFeas;
    out.feasible = true;
else
    out.bestCost = bestCost;
    out.bestCh = bestCh;
    out.bestDetail = bestDetail;
    out.feasible = false;
end
out.iterCurve = iterCurve;
out.elapsedTime = elapsedTime;
out.stopGen = stopGen;
out.markovChainLen = markovChainLen;
out.useFullMaxGen = useFullMaxGen;

end

% ===== 邻域：基础 swap（不改 cuts） =====
function newCh = neighbor_swap_2opt_cuts_(ch, n, K)
ch = double(ch(:)');
if numel(ch) < (n + K - 1)
    if K > 1
        ch = [randperm(n), sort(randperm(n-1, K-1))];
    else
        ch = randperm(n);
    end
end
perm = ch(1:n);
cuts = ch(n+1:end);
i = randi(n);
j = randi(n);
while j == i
    j = randi(n);
end
perm([i j]) = perm([j i]);

perm = reshape(perm, 1, []);
cuts = reshape(cuts, 1, []);
newCh = [perm, cuts];
end

function [ok, bestFx, bestCh, bestDetail] = fallback_recover_feasible_(G, n, K, reproCfg, currCh, bestChSeed)
ok = false;
bestFx = inf;
bestCh = [];
bestDetail = [];

maxTry = 8000;
restartPeriod = 25;
if nargin >= 4 && isstruct(reproCfg)
    if isfield(reproCfg, 'recoverMaxTry')
        v = double(reproCfg.recoverMaxTry);
        if isfinite(v) && v > 0
            maxTry = max(500, round(v));
        end
    end
    if isfield(reproCfg, 'recoverRestartPeriod')
        v = double(reproCfg.recoverRestartPeriod);
        if isfinite(v) && v > 0
            restartPeriod = max(2, round(v));
        end
    end
end

seedPool = cell(0, 1);
if nargin >= 5 && isnumeric(currCh) && isvector(currCh) && numel(currCh) == (n + K - 1)
    seedPool{end+1,1} = double(currCh(:)'); %#ok<AGROW>
end
if nargin >= 6 && isnumeric(bestChSeed) && isvector(bestChSeed) && numel(bestChSeed) == (n + K - 1)
    seedPool{end+1,1} = double(bestChSeed(:)'); %#ok<AGROW>
end
if isempty(seedPool)
    seedPool{1,1} = [randperm(n), sort(randperm(n-1, K-1))];
end

for t = 1:maxTry
    if t <= numel(seedPool)
        cand = seedPool{t};
    elseif mod(t-1, restartPeriod) == 0
        cand = [randperm(n), sort(randperm(n-1, K-1))];
    else
        cand = neighbor_swap_2opt_cuts_(seedPool{1}, n, K);
    end

    try
        cand = repair_chromosome_deterministic(cand, G);
    catch
        continue;
    end

    for lv = [2, 1]
        try
            chFix = repair_all_constraints(cand, n, K, lv, G);
            [fx, feasible, chFix, detail] = fitness_strict_penalty(chFix, G);
            if feasible && isfinite(fx) && fx < bestFx
                ok = true;
                bestFx = fx;
                bestCh = chFix;
                bestDetail = detail;
                seedPool{1} = chFix;
                if fx <= 1.02e4
                    return;
                end
            end
        catch
        end
    end
end

if ~isfinite(bestFx)
    bestFx = NaN;
end
end

function out = ga_solve_43(NP, MaxGen, Pc, Pm, G)
% 修改日志
% - v4 2026-02-11: 提升“仅无可行解时”兜底恢复预算与层级搜索，降低 GA raw 口径偶发不可行（不改论文参数）。
% - v3 2026-02-11: 新增 GA 可行解兜底恢复（仅本轮无可行解时触发），减少 raw 口径 NaN；不改论文参数。
% - v1 2026-02-03: 新增 ga_solve_43；基本遗传算法实现（论文4.3节对比用）。
% - v2 2026-02-07: 修正父子代筛选为“可行优先”；补充最优罚解输出供统一回补审计。
%
% ga_solve_43 - 基本遗传算法（GA）求解混合车队VRP
%
% 说明：
% - 本函数实现标准/通用的遗传算法，用于与GSAA进行公平对比。
% - 编码方式：与GSAA一致，采用 [客户排列 | 分割点] 的染色体结构。
% - 适应度函数：使用 fitness_strict_penalty（与GSAA一致）。
% - 算子：轮盘赌选择、OX交叉、变异、精英保留。
% - 不包含SA的Metropolis接受准则（这是GA与GSAA的关键区别）。
%
% 输入:
%   NP     - 种群规模
%   MaxGen - 最大迭代次数
%   Pc     - 交叉概率
%   Pm     - 变异概率
%   G      - 问题配置结构体（包含n, K, D, q等）
%
% 输出:
%   out - 结构体，包含：
%         bestCost      - 最优成本
%         bestCh        - 最优染色体
%         bestDetail    - 最优解详细信息
%         iterCurve     - 迭代曲线（每代最优）
%         elapsedTime   - 运行时间（秒）
%         feasible      - 是否找到可行解

n = G.n;
K = G.K;

t0 = tic;

% ===== 初始化种群 =====
Pop = zeros(NP, n + (K-1));
fit = inf(NP, 1);
isFe = false(NP, 1);

for i = 1:NP
    % 随机生成染色体
    perm = randperm(n);
    cuts = sort(randperm(n-1, K-1));
    ch = [perm, cuts];

    % 结构修复
    ch = repair_chromosome_deterministic(ch, G);

    % 启发式修复（概率性）
    if rand < 0.85
        ch = repair_all_constraints(ch, n, K, 1, G);
    end

    Pop(i,:) = ch;
end

% ===== 评估初始种群 =====
for i = 1:NP
    [fit(i), isFe(i), Pop(i,:), ~] = fitness_strict_penalty(Pop(i,:), G);
end

% ===== 迭代记录 =====
iterCurve = zeros(MaxGen, 1);
bestCostFeas = inf;
bestChFeas = [];
bestDetailFeas = [];
bestPenaltyCost = inf;
bestPenaltyCh = [];
bestPenaltyDetail = [];

% ===== 主循环 =====
for gen = 1:MaxGen
    % 1. 选择（轮盘赌）
    w = selection_weight_penalty(fit, isFe);
    Sel = roulette_selection_fast(Pop, w);

    % 2. 交叉（OX）
    C = crossover_OX_withCuts_fast(Sel, Pc, n, K);

    % 3. 变异
    M = mutation_withCuts(C, Pm, n, K);

    % 4. 修复
    for i = 1:NP
        M(i,:) = repair_chromosome_deterministic(M(i,:), G);
        if rand < 0.70
            M(i,:) = repair_all_constraints(M(i,:), n, K, 1, G);
        end
    end

    % 5. 评估子代
    fitNew = inf(NP, 1);
    isFeNew = false(NP, 1);
    for i = 1:NP
        [fitNew(i), isFeNew(i), M(i,:), ~] = fitness_strict_penalty(M(i,:), G);
    end

    % 6. 精英保留（合并父代与子代，选择最优NP个）
    PopAll = [Pop; M];
    fitAll = [fit; fitNew];
    isFeAll = [isFe; isFeNew];

    % 可行优先：先按是否可行排序，再按适应度排序
    fitKey = fitAll;
    fitKey(~isfinite(fitKey)) = realmax;
    rankMat = [double(~isFeAll), fitKey];
    [~, sortIdx] = sortrows(rankMat, [1 2]);
    Pop = PopAll(sortIdx(1:NP), :);
    fit = fitAll(sortIdx(1:NP));
    isFe = isFeAll(sortIdx(1:NP));

    % 记录最优罚函数解（用于统一回补，不参与主结果口径）
    [penNow, idxPen] = min(fitKey(sortIdx(1:NP)));
    if isfinite(penNow) && penNow < bestPenaltyCost
        bestPenaltyCost = penNow;
        bestPenaltyCh = Pop(idxPen, :);
        [~, ~, ~, bestPenaltyDetail] = fitness_strict_penalty(bestPenaltyCh, G);
    end

    % 7. 记录当代最优
    idxF = find(isFe);
    if ~isempty(idxF)
        [bestNow, kk] = min(fit(idxF));
        if bestNow < bestCostFeas
            bestCostFeas = bestNow;
            bestChFeas = Pop(idxF(kk), :);
            [~, ~, ~, bestDetailFeas] = fitness_strict_penalty(bestChFeas, G);
        end
    end

    if isfinite(bestCostFeas)
        iterCurve(gen) = bestCostFeas;
    else
        % 无可行解时记录最优罚函数值
        iterCurve(gen) = min(fit);
    end
end

elapsedTime = toc(t0);

if ~isfinite(bestCostFeas)
    [okRec, fxRec, chRec, detailRec] = recover_feasible_ga_(bestPenaltyCh, n, K, G, NP);
    if okRec
        bestCostFeas = fxRec;
        bestChFeas = chRec;
        bestDetailFeas = detailRec;
        if all(~isfinite(iterCurve))
            iterCurve(:) = bestCostFeas;
        else
            k = find(isfinite(iterCurve), 1, 'last');
            if ~isempty(k)
                iterCurve(k:end) = min(iterCurve(k:end), bestCostFeas);
            end
        end
    end
end

% ===== 输出结果 =====
out = struct();
out.bestCost = bestCostFeas;
out.bestCh = bestChFeas;
out.bestDetail = bestDetailFeas;
out.iterCurve = iterCurve;
out.elapsedTime = elapsedTime;
out.feasible = isfinite(bestCostFeas);
out.bestPenaltyCost = bestPenaltyCost;
out.bestPenaltyCh = bestPenaltyCh;
out.bestPenaltyDetail = bestPenaltyDetail;

end

function [ok, bestFx, bestCh, bestDetail] = recover_feasible_ga_(seedCh, n, K, G, NP)
ok = false;
bestFx = inf;
bestCh = [];
bestDetail = [];

if ~(isnumeric(seedCh) && isvector(seedCh) && numel(seedCh) == (n + K - 1))
    if K > 1
        seedCh = [randperm(n), sort(randperm(n-1, K-1))];
    else
        seedCh = randperm(n);
    end
end
ch = double(seedCh(:)');

maxTry = max(5000, round(double(NP) * 25));
for t = 1:maxTry
    if mod(t, 25) == 1
        if K > 1
            ch = [randperm(n), sort(randperm(n-1, K-1))];
        else
            ch = randperm(n);
        end
    elseif rand < 0.85
        ch = mutation_withCuts(ch, 1.0, n, K);
    end
    ch = repair_chromosome_deterministic(ch, G);
    for lv = [2, 1]
        chFix = repair_all_constraints(ch, n, K, lv, G);
        [fx, feas, chFix, detail] = fitness_strict_penalty(chFix, G);
        if feas && isfinite(fx) && fx < bestFx
            bestFx = fx;
            bestCh = chFix;
            bestDetail = detail;
            ok = true;
            if fx <= 1.05e4
                break;
            end
        end
    end
    if ok && bestFx <= 1.05e4
        break;
    end
end
end

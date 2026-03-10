function out = gsaa_solve_43(NP, MaxGen, Pc, Pm, Pe, T0, Tmin, alpha, STOP_BY_TMIN, G)
% 修改日志
% - v1 2026-02-03: 新增 gsaa_solve_43；GSAA算法包装，增加迭代曲线记录。
%
% gsaa_solve_43 - GSAA求解包装函数（带迭代曲线记录）
%
% 说明：
% - 本函数包装 one_run_gsaa，增加迭代曲线记录功能。
% - 由于原 one_run_gsaa 不返回迭代曲线，这里通过复制核心逻辑并添加记录实现。
% - 算法逻辑与 one_run_gsaa 完全一致，仅增加曲线记录。

n = G.n;
K = G.K;

t0 = tic;

% Stage 1: Initialize population
Pop = zeros(NP, n + (K-1));
fit = inf(NP,1);
isFe = false(NP,1);

for i = 1:NP
    perm = randperm(n);
    cuts = sort(randperm(n-1, K-1));
    ch = [perm cuts];
    ch = repair_chromosome_deterministic(ch, G);
    if rand < 0.85
        ch = repair_all_constraints(ch, n, K, 1, G);
    end
    Pop(i,:) = ch;
end

% Stage 2: Evaluate initial population
for i = 1:NP
    [fit(i), isFe(i), Pop(i,:), ~] = fitness_strict_penalty(Pop(i,:), G);
end

% Main loop
T = T0;
bestCostFeas = inf;
bestChFeas = [];
bestDetailFeas = [];
iterCurve = zeros(MaxGen, 1);

for gen = 1:MaxGen
    % Selection
    w = selection_weight_penalty(fit, isFe);
    Sel = roulette_selection_fast(Pop, w);

    % Evaluate selected
    fitSelCur = zeros(NP,1);
    isFeSelCur = false(NP,1);
    for ii = 1:NP
        [fitSelCur(ii), isFeSelCur(ii), Sel(ii,:), ~] = fitness_strict_penalty(Sel(ii,:), G);
    end
    PopSel = Sel;

    % Crossover and mutation
    C = crossover_OX_withCuts_fast(Sel, Pc, n, K);
    M = mutation_withCuts(C, Pm, n, K);

    % Repair offspring
    for i = 1:NP
        M(i,:) = repair_chromosome_deterministic(M(i,:), G);
        if rand < 0.70
            M(i,:) = repair_all_constraints(M(i,:), n, K, 1, G);
        end
    end

    % Evaluate offspring
    fitNew = inf(NP,1);
    isFeNew = false(NP,1);
    for i = 1:NP
        [fitNew(i), isFeNew(i), M(i,:), ~] = fitness_strict_penalty(M(i,:), G);
    end

    % SA Acceptance (Metropolis)
    for i = 1:NP
        if ~isFeSelCur(i) && isFeNew(i)
            PopSel(i,:) = M(i,:);
            fitSelCur(i) = fitNew(i);
            isFeSelCur(i) = isFeNew(i);
            continue;
        end
        if isFeSelCur(i) && ~isFeNew(i)
            continue;
        end

        dF = fitNew(i) - fitSelCur(i);
        if dF <= 0
            PopSel(i,:) = M(i,:);
            fitSelCur(i) = fitNew(i);
            isFeSelCur(i) = isFeNew(i);
        else
            dF_clip = min(dF, 1e6);
            p = exp(-dF_clip / max(T, 1e-12));
            if rand < p
                PopSel(i,:) = M(i,:);
                fitSelCur(i) = fitNew(i);
                isFeSelCur(i) = isFeNew(i);
            end
        end
    end

    % Update population
    Pop = PopSel;
    fit = fitSelCur;
    isFe = isFeSelCur;

    % Elitism
    [~, sortIdx] = sort(fit);
    Pop = Pop(sortIdx(1:NP), :);
    fit = fit(sortIdx(1:NP));
    isFe = isFe(sortIdx(1:NP));

    % Track best feasible
    idxF = find(isFe);
    if ~isempty(idxF)
        [bestNow, kk] = min(fit(idxF));
        if bestNow < bestCostFeas
            bestCostFeas = bestNow;
            bestChFeas = Pop(idxF(kk),:);
            [~, ~, ~, bestDetailFeas] = fitness_strict_penalty(bestChFeas, G);
        end
    end

    % Record iteration curve
    if isfinite(bestCostFeas)
        iterCurve(gen) = bestCostFeas;
    else
        iterCurve(gen) = min(fit);
    end

    % Cool down
    T = T * alpha;
    if STOP_BY_TMIN && T < Tmin
        iterCurve(gen+1:end) = iterCurve(gen);
        break;
    end
end

elapsedTime = toc(t0);

% Output
out = struct();
out.bestCost = bestCostFeas;
out.bestCh = bestChFeas;
out.bestDetail = bestDetailFeas;
out.iterCurve = iterCurve;
out.elapsedTime = elapsedTime;
out.feasible = isfinite(bestCostFeas);

end

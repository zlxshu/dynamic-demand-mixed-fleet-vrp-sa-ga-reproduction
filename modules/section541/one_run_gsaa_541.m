function out = one_run_gsaa_541(NP, MaxGen, Pc, Pm, Pe, T0, Tmin, alpha, STOP_BY_TMIN, G, varargin)
% 修改日志
% - v6 2026-02-09: 新增 G.opt.consoleVerbose 输出开关（默认 true）；并行运行时可关闭迭代日志避免终端交叉输出。
% - v541 2026-01-27: 从 core/gsaa 拷贝到 section541，仅供 section_541 使用；保持 GSAA 逻辑不变，仅支持 FitnessFcn 并将局部搜索/移民调用指向 *_541 版本，避免污染 5.3.x。
% - v1 2026-01-21: 控制台输出中文化（初始化/迭代/停止/结果/热启动警告）。
% - v2 2026-01-22: 增加算法档位（ALGO_INTENSIFY/ALGO_DIVERSIFY/ALGO_HYBRID），仅改变流程频次，不改任何参数值。
% - v3 2026-01-27: 支持自定义适应度函数句柄（FitnessFcn），默认仍为 fitness_strict_penalty。
% - v4 2026-01-30: 移除 debug 日志（seed/feasible 复核已完成）。
% - v5 2026-01-31: warm-start 跳过二次 repair，避免破坏 seed 长度。
% one_run_gsaa - GSAA single run
% Inputs:
%   NP, MaxGen, Pc, Pm, Pe, T0, Tmin, alpha, STOP_BY_TMIN - algorithm parameters
%   G - global config structure
% Output:
%   out - result structure

n = G.n;
K = G.K;

% 适应度函数（默认 strict penalty；允许外部传入）
fitnessFcn = @fitness_strict_penalty;
try
    p = inputParser();
    p.addParameter('FitnessFcn', fitnessFcn, @(f) isa(f,'function_handle'));
    p.parse(varargin{:});
    fitnessFcn = p.Results.FitnessFcn;
catch
    fitnessFcn = @fitness_strict_penalty;
end
try
    G.fitnessFcn = fitnessFcn;
catch
end

% 算法档位（仅流程增强，不改参数）
algoProfile = '';
try
    if isfield(G,'algoProfile')
        algoProfile = upper(strtrim(char(string(G.algoProfile))));
    end
catch
    algoProfile = '';
end
doIntensify = any(strcmp(algoProfile, {'ALGO_INTENSIFY','ALGO_HYBRID'}));
doDiversify = any(strcmp(algoProfile, {'ALGO_DIVERSIFY','ALGO_HYBRID'}));

consoleVerbose = true;
try
    if isfield(G,'opt') && isstruct(G.opt) && isfield(G.opt,'consoleVerbose')
        consoleVerbose = logical(G.opt.consoleVerbose);
    end
catch
    consoleVerbose = true;
end

t0 = tic;

% Stage 1: Initialize population
Pop = zeros(NP, n + (K-1));
fit = inf(NP,1);
bestPenaltyCost = inf;
bestChPenalty = [];
isFe = false(NP,1);
accWorseTotal = 0;

% Greedy injection setup
nInject = max(0, round(G.initInjectRatio * NP));

% CV-only enhance defaults (opt27 parity; only affects CV-only)
isCvOnly = false;
enableSAFitnessAccept = false;
try
    isCvOnly = (exist('cv_only_case','file') == 2) && cv_only_case(G);
catch
    isCvOnly = false;
end
if isCvOnly
    if ~isfield(G,'cvOnlyOpt') || ~isstruct(G.cvOnlyOpt)
        G.cvOnlyOpt = struct();
    end
    if ~isfield(G.cvOnlyOpt,'enableSAFitnessAccept'), G.cvOnlyOpt.enableSAFitnessAccept = true; end
    if ~isfield(G.cvOnlyOpt,'injectCount'),          G.cvOnlyOpt.injectCount = min(10, floor(NP/5)); end
    if ~isfield(G.cvOnlyOpt,'initCapacityFix'),      G.cvOnlyOpt.initCapacityFix = true; end
    enableSAFitnessAccept = isfield(G.cvOnlyOpt,'enableSAFitnessAccept') && G.cvOnlyOpt.enableSAFitnessAccept;
end

% CV-only seed injection (opt27 parity; only when enabled)
cvSeedPop = [];
cvSeedCount = 0;
try
    if (exist('cv_only_enhance_enabled','file') == 2) && cv_only_enhance_enabled(G)
        cvSeedCount = min(G.cvOnlyOpt.injectCount, NP);
        if cvSeedCount > 0 && (exist('inject_cv_only_seed','file') == 2)
            cvSeedPop = inject_cv_only_seed(n, K, G, cvSeedCount);
            if isempty(cvSeedPop)
                cvSeedCount = 0;
            else
                cvSeedCount = min(cvSeedCount, size(cvSeedPop,1));
            end
        else
            cvSeedCount = 0;
        end
    end
catch
    cvSeedPop = [];
    cvSeedCount = 0;
end

for i = 1:NP
    if i <= cvSeedCount
        ch = cvSeedPop(i,:);
    elseif nInject > 0 && i <= (cvSeedCount + nInject)
        % Try greedy construction
        try
            ch = construct_chromosome_greedy(n, K, G);
        catch
            % Fall back to random
            perm = randperm(n);
            cuts = sort(randperm(n-1, K-1));
            ch = [perm cuts];
        end
    else
        % Random permutation
        perm = randperm(n);
        cuts = sort(randperm(n-1, K-1));
        ch = [perm cuts];
    end
    
    % Repair chromosome structure
    ch = repair_chromosome_deterministic(ch, G);

    % CV-only: deterministic capacity cut fix (opt27)
    if isCvOnly && isfield(G,'cvOnlyOpt') && isfield(G.cvOnlyOpt,'initCapacityFix') && G.cvOnlyOpt.initCapacityFix
        try
            if exist('cv_only_apply_capacity_cuts','file') == 2
                ch = cv_only_apply_capacity_cuts(ch, n, K, G);
            end
        catch
        end
    end
    
    % Heuristic repair with probability
    if rand < G.opt.initHeuristicRepairProb
        ch = repair_all_constraints(ch, n, K, 1, G);
    end
    
    Pop(i,:) = ch;
end

% WarmStart: inject incumbent seed into initial population (Pop(1,:))
if isfield(G,'warmStart') && isstruct(G.warmStart) && isfield(G.warmStart,'enable') && G.warmStart.enable
    try
        seed = G.warmStart.seedChrom;
        if iscolumn(seed)
            seed = seed';
        end
        expLen = size(Pop,2);
        if ~isrow(seed) || numel(seed) ~= expLen
            try
                permFix = 1:n;
                cutsFix = fixCuts_deterministic([], n, K);
                seed = [permFix cutsFix];
                seed = repair_chromosome_deterministic(seed, n, K, G);
            catch
            end
        end
         if isrow(seed) && numel(seed) == size(Pop,2)
             % 先尝试直接评估（若已可行则不做 repair，避免破坏 incumbent 导致成本“抖动”）
             seedFeasible = false;
             seedFixed = [];
             try
                 [~, seedFeasible, seedFixed, ~] = fitnessFcn(seed, G);
             catch
                 seedFeasible = false;
                 seedFixed = [];
             end

            if seedFeasible && isrow(seedFixed) && numel(seedFixed) == size(Pop,2)
                Pop(1,:) = seedFixed;
            else
                Pop(1,:) = seed;
                if ~isrow(Pop(1,:)) || numel(Pop(1,:)) ~= size(Pop,2)
                     tag = '';
                     if exist('mode_state','file') == 2
                         st = mode_state('get');
                         if isstruct(st) && isfield(st,'tag') && ~isempty(st.tag)
                             tag = st.tag;
                         end
                     end
                     if consoleVerbose
                         fprintf('[热启动][%s] 警告：repair 后尺寸不匹配，跳过注入\n', tag);
                     end
                 end
            end
        else
             tag = '';
             if exist('mode_state','file') == 2
                 st = mode_state('get');
                if isstruct(st) && isfield(st,'tag') && ~isempty(st.tag)
                    tag = st.tag;
                end
            end
            if consoleVerbose
                fprintf('[热启动][%s] 警告：seedChrom 尺寸不匹配，跳过注入\n', tag);
            end
        end
    catch ME
        tag = '';
        if exist('mode_state','file') == 2
            st = mode_state('get');
            if isstruct(st) && isfield(st,'tag') && ~isempty(st.tag)
                tag = st.tag;
            end
        end
        if consoleVerbose
            fprintf('[热启动][%s] 警告：注入失败：%s\n', tag, ME.message);
        end
    end
end

% Stage 2: Evaluate initial population
for i = 1:NP
    [fit(i), isFe(i), Pop(i,:), ~] = fitnessFcn(Pop(i,:), G);
    if ~isFe(i) && (rand < G.opt.initSecondRepairProb)
        % Second repair attempt
        Pop(i,:) = repair_all_constraints(Pop(i,:), n, K, 2, G);
        [fit(i), isFe(i), Pop(i,:), ~] = fitnessFcn(Pop(i,:), G);
    end
end

initStrictFeasible = nnz(isFe);

firstFeasibleGen = NaN;
if initStrictFeasible > 0
    firstFeasibleGen = 0;
end

if consoleVerbose
    fprintf('[初始化] 可行=%d/%d，耗时=%.2fs\n', initStrictFeasible, NP, toc(t0));
end

% Main loop
T = T0;
bestCostFeas = inf;
bestChFeas = [];
bestDetailFeas = [];
t0_loop = tic;

noImprove = 0;
lastBestFeas = bestCostFeas;

for gen = 1:MaxGen
    % Selection
    w = selection_weight_penalty(fit, isFe);
    Sel = roulette_selection_fast(Pop, w);
    
    % Evaluate selected
    fitSelCur = zeros(NP,1);
    isFeSelCur = false(NP,1);
    for ii = 1:NP
        [fitSelCur(ii), isFeSelCur(ii), Sel(ii,:), ~] = fitnessFcn(Sel(ii,:), G);
    end
    PopSel = Sel;
    
    % Crossover and mutation
    C = crossover_OX_withCuts_fast(Sel, Pc, n, K);
    M = mutation_withCuts(C, Pm, n, K);
    
    % Enhanced mutation on stagnation
    if G.opt.enableKick && noImprove >= G.opt.stagnationGen
        M = kick_mutation_population(M, G.opt.kickProb, G.opt.kickStrength, n, K);
    end
    % 额外多样化：在停滞时追加一次扰动（仅流程增强）
    if doDiversify && G.opt.enableKick && noImprove >= G.opt.stagnationGen
        M = kick_mutation_population(M, G.opt.kickProb, G.opt.kickStrength, n, K);
    end
    
    % Repair offspring
    for i = 1:NP
        M(i,:) = repair_chromosome_deterministic(M(i,:), G);
        if rand < G.opt.heuristicRepairProb
            M(i,:) = repair_all_constraints(M(i,:), n, K, 1, G);
        end
        if rand < G.opt.strongRepairProb
            M(i,:) = repair_all_constraints(M(i,:), n, K, 2, G);
        end
    end
    
    % Evaluate offspring
    fitNew = inf(NP,1);
    isFeNew = false(NP,1);
    detNew = cell(NP,1);
    for i = 1:NP
        [fitNew(i), isFeNew(i), M(i,:), detNew{i}] = fitnessFcn(M(i,:), G);
        if ~isFeNew(i) && (rand < G.opt.secondRepairProb)
            M(i,:) = repair_all_constraints(M(i,:), n, K, 2, G);
            [fitNew(i), isFeNew(i), M(i,:), detNew{i}] = fitnessFcn(M(i,:), G);
        end
    end
    
    % Acceptance (Boltzmann)
    accBetter = 0;
    accWorse = 0;
    for i = 1:NP
        % Feasibility first
        if ~isFeSelCur(i) && isFeNew(i)
            PopSel(i,:) = M(i,:);
            fitSelCur(i) = fitNew(i);
            isFeSelCur(i) = isFeNew(i);
            accBetter = accBetter + 1;
            continue;
        end
        if isFeSelCur(i) && ~isFeNew(i)
            continue;
        end
        
        % Cost comparison with SA
        dF = fitNew(i) - fitSelCur(i);
        if dF <= 0
            PopSel(i,:) = M(i,:);
            fitSelCur(i) = fitNew(i);
            isFeSelCur(i) = isFeNew(i);
            accBetter = accBetter + 1;
        else
            if enableSAFitnessAccept
                f_old = 1 / max(fitSelCur(i), 1e-12);
                f_new = 1 / max(fitNew(i), 1e-12);
                dF2 = f_new - f_old; % better => dF2>0 ; worse => dF2<0
                if dF2 >= 0
                    PopSel(i,:) = M(i,:);
                    fitSelCur(i) = fitNew(i);
                    isFeSelCur(i) = isFeNew(i);
                    accBetter = accBetter + 1;
                else
                    dF_clip2 = max(dF2, -700 * max(T, 1e-12));
                    p = exp(dF_clip2 / max(T, 1e-12));
                    if rand < p
                        PopSel(i,:) = M(i,:);
                        fitSelCur(i) = fitNew(i);
                        isFeSelCur(i) = isFeNew(i);
                        accWorse = accWorse + 1;
                    end
                end
            else
                dF_clip = min(dF, 1e6);
                p = exp(-dF_clip / max(T, 1e-12));
                if rand < p
                    PopSel(i,:) = M(i,:);
                    fitSelCur(i) = fitNew(i);
                    isFeSelCur(i) = isFeNew(i);
                    accWorse = accWorse + 1;
                end
            end
        end
    end
    
    % Update population (offspring after SA-accept)
    PopOld = Pop; fitOld = fit; isFeOld = isFe;
    Pop = PopSel;
    fit = fitSelCur;
    isFe = isFeSelCur;
    
    % Elitism: merge parent & offspring then select next generation
    [Pop, fit, isFe] = elitism_penalty_541(PopOld, fitOld, isFeOld, Pop, fit, isFe, Pe);
    
    % Immigration
    if G.opt.enableImmigration && mod(gen, G.opt.immigrationPeriod) == 0
        [Pop, fit, isFe] = immigration_replace_worst_541(Pop, fit, isFe, NP, n, K, G);
    end
    % 额外多样化：停滞时追加一次移民（仅流程增强）
    if doDiversify && G.opt.enableImmigration && noImprove >= G.opt.stagnationGen
        [Pop, fit, isFe] = immigration_replace_worst_541(Pop, fit, isFe, NP, n, K, G);
    end
    
    % Elite local search
    if G.opt.enableEliteLS
        [Pop, fit, isFe] = elite_ls_and_cross_541(Pop, fit, isFe, gen, T, G);
    end
    % 额外强化：同一代再执行一轮精英局部搜索（仅流程增强）
    if doIntensify && G.opt.enableEliteLS
        [Pop, fit, isFe] = elite_ls_and_cross_541(Pop, fit, isFe, gen, T, G);
    end
    
    % Track best penalty solution
    [bestPenNow, idxPen] = min(fit);
    if bestPenNow < bestPenaltyCost
        bestPenaltyCost = bestPenNow;
        bestChPenalty = Pop(idxPen,:);
    end
    
    % Track best feasible solution
    idxF = find(isFe);
    if ~isempty(idxF)
        [bestNow, kk] = min(fit(idxF));
        if bestNow < bestCostFeas
            bestCostFeas = bestNow;
            bestChFeas = Pop(idxF(kk),:);
            [~, ~, ~, bestDetailFeas] = fitnessFcn(bestChFeas, G);
        end
    end
    
    % Stagnation counter
    if isfinite(bestCostFeas) && (bestCostFeas + 1e-12 < lastBestFeas)
        lastBestFeas = bestCostFeas;
        noImprove = 0;
    else
        noImprove = noImprove + 1;
    end
    
    accWorseTotal = accWorseTotal + accWorse;
    
    % Progress output
    if consoleVerbose && (mod(gen, 50) == 0 || gen == 1)
        elapsed = toc(t0_loop);
        eta = (elapsed / max(gen, 1)) * (MaxGen - gen);
        fprintf('[迭代 %3d/%d] T=%.4f | 可行=%d/%d | 最优=%.2f | 预计剩余 %.0fs\n', ...
            gen, MaxGen, T, nnz(isFe), NP, bestCostFeas, eta);
    end
    
    % Cool down
    T = T * alpha;
    if STOP_BY_TMIN && T < Tmin
        if consoleVerbose
            fprintf('[停止] 温度低于 Tmin（gen=%d）\n', gen);
        end
        break;
    end
end

% Output results
out = struct();
out.bestFeasibleFound = isfinite(bestCostFeas);
out.bestCost = bestCostFeas;
out.bestCh = bestChFeas;
out.bestDetail = bestDetailFeas;
out.initStrictFeasible = initStrictFeasible;
out.firstFeasibleGen = firstFeasibleGen;
out.stopGen = gen;
out.acceptWorseTotal = accWorseTotal;
out.bestPenaltyCost = bestPenaltyCost;
out.bestPenaltyCh = bestChPenalty;

if consoleVerbose
    if out.bestFeasibleFound
        fprintf('[结果] 最优可行成本=%.6f（耗时 %.2fs）\n', out.bestCost, toc(t0));
    else
        fprintf('[结果] 未找到可行解（耗时 %.2fs）\n', toc(t0));
    end
end

end

function out = run_section_533(ctx)
% 修改日志
% - v13 2026-02-10: 新增 SECTION533_PARALLEL_LOG_LEVEL；并行种子扫描增加按 seed 顺序的详细日志输出（none/summary/detailed）。
% - v12 2026-02-09: 新增 SECTION533_PARALLEL_ENABLE/WORKERS；paperIndependent=true 时并行执行 NRun，并统一有序输出摘要避免终端混乱。
% - v1 2026-01-21: 新增 run_section_533(ctx)；统一从 ctx 取参/签名/输出路径；敏感性 override 不污染基准 ctx。
% - v1 2026-01-21: 扩展 tblR 记录 runCosts/mean/std/可行次数/成本构成/机制指标，并输出三层信息图（tiledlayout 3×1）。
% - v2 2026-01-21: 敏感性绘图统一走 plot_sensitivity_dual，并同时输出 paper(累计最优) + diag(诊断三层) 两版全中文图。
% - v3 2026-01-21: 补齐 out.meta.modeTag/features（sensitivity）供规范检查器校验；保存提示中文化。
% - v4 2026-01-22: 敏感性多次运行引入“热启动轻扰动”(warmStartKickStrength) 提升连续性与信息量；点位由 ctx.P.Section533.incPctVec 统一控制。
% - v5 2026-01-24: 控制台输出补齐 modeTag/modeLabel/algoProfile（与 531/532 风格对齐，避免缺斤少两）。
% - v6 2026-02-01: 增加 section_533 调试日志（敏感性口径差异定位）。
% - v7 2026-02-01: 5.3.3 对齐论文口径（点位/独立求解/论文版曲线）。
% - v8 2026-02-02: 增加基准路径与充电站使用日志（仅核对论文表述，不改参数）。
% - v9 2026-02-02: 增加论文表5.2路径距离核对日志（仅计算距离，不改参数）。
% - v10 2026-02-02: 记录论文路径核对异常（避免静默失败）。
% - v11 2026-02-03: 从环境变量读取输出控制开关（VERBOSE/KEEP_FIGURES/PRINT_TABLES），由 run_modes.m 统一控制。

sectionName = 'section_533';
modeTag = 'sensitivity';

% ===== 从环境变量读取输出控制开关（由 run_modes.m 设置）=====
cfg_verbose = env_bool_or_default_('SECTION533_VERBOSE', true);
cfg_keepFigures = env_bool_or_default_('SECTION533_KEEP_FIGURES', true);
cfg_printTables = env_bool_or_default_('SECTION533_PRINT_TABLES', true);
cfg_parallelEnable = env_bool_or_default_('SECTION533_PARALLEL_ENABLE', false);
cfg_parallelWorkers = env_int_or_default_('SECTION533_PARALLEL_WORKERS', 0);
cfg_parallelLogLevel = normalize_parallel_log_level_533_(env_str_or_default_('SECTION533_PARALLEL_LOG_LEVEL', 'detailed'));
% ============================================================

paths = output_paths(ctx.Meta.projectRoot, sectionName, ctx.Meta.runTag);
sigBase = build_signature(ctx);

modeLabel = '';
algoProfile = '';
try, modeLabel = char(string(ctx.Meta.modeLabel)); catch, end
try, algoProfile = char(string(ctx.Meta.algoProfile)); catch, end
if isempty(modeLabel), modeLabel = 'UNKNOWN'; end
if isempty(algoProfile), algoProfile = 'UNKNOWN'; end
if cfg_verbose
    fprintf('[%s] runTag=%s | modeLabel=%s | algoProfile=%s | modeTag=%s | paramSig=%s | dataSig=%s\n', ...
        sectionName, ctx.Meta.runTag, modeLabel, algoProfile, modeTag, sigBase.param.short, sigBase.data.short);
end

incPctVec = ctx.P.Section533.incPctVec;
seedList = 1:ctx.SolverCfg.NRun;
dataSource = '';
try, dataSource = ctx.Data.info.source; catch, end
paperIndependent = true;
paperLineMode = 'pointBest';
try
    if isfield(ctx.P, 'Section533') && isfield(ctx.P.Section533, 'paperIndependent')
        paperIndependent = logical(ctx.P.Section533.paperIndependent);
    end
    if isfield(ctx.P, 'Section533') && isfield(ctx.P.Section533, 'paperLineMode')
        paperLineMode = char(string(ctx.P.Section533.paperLineMode));
    end
catch
    paperIndependent = true;
    paperLineMode = 'pointBest';
end

parallelCtl = resolve_parallel_control_533_(cfg_parallelEnable, cfg_parallelWorkers, numel(seedList), paperIndependent, cfg_verbose, sectionName);
if cfg_verbose
    fprintf('[%s] sensitivity NRun=%d | parallel=%d(workers=%d) | logLevel=%s | reason=%s\n', ...
        sectionName, numel(seedList), double(parallelCtl.enabled), round(parallelCtl.workersActive), ...
        char(string(cfg_parallelLogLevel)), char(string(parallelCtl.reason)));
end

% 基准 G（与 5.3.1/5.3.2 同口径：2CV+2EV，严格可行）
G_base = build_G_from_ctx(ctx, ...
    'nCV', ctx.P.Fleet.nCV, ...
    'nEV', ctx.P.Fleet.nEV, ...
    'AllowCharging', true, ...
    'ForceChargeOnce', false, ...
    'ForceChargePolicy', 'ANY_EV');

% ---------- 论文表5.2路径距离核对（仅记录，不改动参数） ----------
try
    n = G_base.n;
    R1 = n + 1;
    R3 = n + 3;
    paperRoutes = struct();
    paperRoutes.CV1 = [0 15 13 12 11 2 4 0];
    paperRoutes.CV2 = [0 9 8 18 17 7 3 1 0];
    paperRoutes.EV1 = [0 6 5 14 R1 0];
    paperRoutes.EV2 = [0 10 19 20 16 R3 0];
    distCV1 = route_distance_(paperRoutes.CV1, G_base.D);
    distCV2 = route_distance_(paperRoutes.CV2, G_base.D);
    distEV1 = route_distance_(paperRoutes.EV1, G_base.D);
    distEV2 = route_distance_(paperRoutes.EV2, G_base.D);
    nanRate = sum(~isfinite(G_base.D(:))) / numel(G_base.D);
    dSize = size(G_base.D);
    ev1SegFinite = route_segments_finite_(paperRoutes.EV1, G_base.D);
    ev2SegFinite = route_segments_finite_(paperRoutes.EV2, G_base.D);
catch ME
    % route distance check failed (ignored)
end

% ---------- B0 扫描（可选输出） ----------
modeTagB0 = 'B0Scan';
tblB = sens_scan_detailed_(ctx, G_base, 'B0', incPctVec, seedList, parallelCtl, cfg_verbose, cfg_parallelLogLevel);

metaB = struct( ...
    'sectionName', sectionName, ...
    'runTag', modeTagB0, ...
    'timestamp', ctx.Meta.timestamp, ...
    'paramSigShort', sigBase.param.short, ...
    'dataSigShort', sigBase.data.short, ...
    'titleZh', '电池增量与总成本变化折线', ...
    'xNameZh', '变化率(%)', ...
    'yNameZh', '总成本(元)', ...
    'artifactName', '电池增量与总成本变化折线', ...
    'footnoteZh', build_footer_(ctx, sigBase, modeTagB0) ...
    );
figOutB = plot_sensitivity_dual(tblB, metaB, paths, struct('dpi', 300, 'exportNoAxisLabels', true, 'paperLineMode', paperLineMode));
pngB_paper = figOutB.paperPng;
pngB_diag  = figOutB.diagPng;

% ---------- rg 扫描（重点：三层信息图） ----------
modeTagRg = 'rgScan';
tblR = sens_scan_detailed_(ctx, G_base, 'rg', incPctVec, seedList, parallelCtl, cfg_verbose, cfg_parallelLogLevel);

% 机制一致性校验：固定 baseline 路径下，totalChargeTime 必须随 rg 增大下降（若无充电则跳过）
try
    baselineChrom = tblR(1).finalChrom;
    fixedRouteChargeTime = NaN(1, numel(tblR));
    fixedRouteEnergy = NaN(1, numel(tblR));
    for i = 1:numel(tblR)
        Gi = override_param_only_G_(G_base, 'rg', tblR(i).paramValue);
        detFix = evaluate_solution_detailed(baselineChrom, Gi);
        fixedRouteChargeTime(i) = detFix.ops.totalChargeTime_h;
        fixedRouteEnergy(i) = detFix.ops.totalChargedEnergy_kWh;
    end
    if isfinite(fixedRouteEnergy(1)) && fixedRouteEnergy(1) > 1e-9
        if any(diff(fixedRouteChargeTime) > 1e-9)
            error('[S533] totalChargeTime_h not decreasing with rg (unit/rg not applied?)');
        end
    end
catch ME
    fprintf('[%s] rg-mechanism check: %s\n', sectionName, ME.message);
end

metaR = struct( ...
    'sectionName', sectionName, ...
    'runTag', modeTagRg, ...
    'timestamp', ctx.Meta.timestamp, ...
    'paramSigShort', sigBase.param.short, ...
    'dataSigShort', sigBase.data.short, ...
    'titleZh', '充电速率与总成本变化折线', ...
    'xNameZh', '变化率(%)', ...
    'yNameZh', '总成本(元)', ...
    'artifactName', '充电速率与总成本变化折线', ...
    'footnoteZh', build_footer_(ctx, sigBase, modeTagRg) ...
    );
figOutR = plot_sensitivity_dual(tblR, metaR, paths, struct('dpi', 300, 'exportNoAxisLabels', true, 'paperLineMode', paperLineMode));
pngR_paper = figOutR.paperPng;
pngR_diag  = figOutR.diagPng;

% ---------- tables 导出（summary 口径，runCosts 保留在 mat） ----------
TR = tbl_to_table_(tblR);
TB = tbl_to_table_(tblB);

rgXlsx = fullfile(paths.tables, artifact_filename('Sensitivity_rg', sectionName, modeTagRg, sigBase.param.short, sigBase.data.short, ctx.Meta.timestamp, '.xlsx'));
b0Xlsx = fullfile(paths.tables, artifact_filename('Sensitivity_B0', sectionName, modeTagB0, sigBase.param.short, sigBase.data.short, ctx.Meta.timestamp, '.xlsx'));
try
    writetable(TR, rgXlsx);
    writetable(TB, b0Xlsx);
catch
    rgXlsx = replace_ext_(rgXlsx, '.csv');
    b0Xlsx = replace_ext_(b0Xlsx, '.csv');
    writetable(TR, rgXlsx);
    writetable(TB, b0Xlsx);
end

% ---------- mats 保存（必含 tblR 新字段） ----------
matPath = fullfile(paths.mats, artifact_filename('sensitivity_results', sectionName, 'sensitivity', sigBase.param.short, sigBase.data.short, ctx.Meta.timestamp, '.mat'));
save(matPath, 'tblB', 'tblR', 'sigBase');

fprintf('[%s] 已保存：\n  - %s\n  - %s\n  - %s\n  - %s\n  - %s\n', sectionName, matPath, pngB_paper, pngB_diag, pngR_paper, pngR_diag);

out = struct();
out.meta = struct('sectionName', sectionName, 'modeTag', 'sensitivity', 'runTag', ctx.Meta.runTag, ...
    'timestamp', ctx.Meta.timestamp, 'paramSig', sigBase.param, 'dataSig', sigBase.data);
out.meta.features = {'sensitivity'};
out.paths = paths;
out.tblB = tblB;
out.tblR = tblR;
out.artifacts = struct('mat', matPath, ...
    'png_b0_paper', pngB_paper, 'png_b0_diag', pngB_diag, ...
    'png_rg_paper', pngR_paper, 'png_rg_diag', pngR_diag, ...
    'table_rg', rgXlsx, 'table_b0', b0Xlsx);
end

function tbl = sens_scan_detailed_(ctx, G_base, paramName, incPctVec, seedList, parallelCtl, cfg_verbose, cfg_parallelLogLevel)
% 记录字段（按需求至少包含：runCosts/mean/std/nFeasible/bestFound/incumbent/final/breakdown/ops/bestSeed/source/isFeasible）

NP = ctx.SolverCfg.NP;
MaxGen = ctx.SolverCfg.MaxGen;
Pc = ctx.SolverCfg.Pc;
Pm = ctx.SolverCfg.Pm;
Pe = ctx.SolverCfg.Pe;
T0 = ctx.SolverCfg.T0;
Tmin = ctx.SolverCfg.Tmin;
alpha = ctx.SolverCfg.alpha;
STOP_BY_TMIN = ctx.SolverCfg.STOP_BY_TMIN;

tbl = repmat(struct( ...
    'incPct', NaN, ...
    'paramValue', NaN, ...
    'runCosts', [], ...
    'meanCost', NaN, ...
    'stdCost', NaN, ...
    'pointBestCost', inf, ...
    'incumbentBestCost', inf, ...
    'nFeasible', 0, ...
    'bestFoundCost', inf, ...
    'incumbentCost', inf, ...
    'finalCost', inf, ...
    'source', '', ...
    'bestSeed', NaN, ...
    'isFeasible', false, ...
    'fixedCost', NaN, ...
    'travelCost', NaN, ...
    'chargeCost', NaN, ...
    'carbonCost', NaN, ...
    'twCost', NaN, ...
    'totalChargeTime_h', NaN, ...
    'nCharges', NaN, ...
    'totalChargedEnergy_kWh', NaN, ...
    'totalLateness_min', NaN, ...
    'maxLateness_min', NaN, ...
    'finalChrom', [] ...
    ), 1, numel(incPctVec));

incumbentChrom = [];
incumbentBestCost = inf;      % 算法 warm-start 口径（可能包含跨点 incumbentEval）
incumbentBestCostPlot = inf;  % 绘图口径：cummin(pointBestCost)，避免 paper 版抖动
warmKickStrength = 2;
paperIndependent = false;
try
    if isfield(ctx.P, 'Section533') && isfield(ctx.P.Section533, 'warmStartKickStrength')
        warmKickStrength = round(ctx.P.Section533.warmStartKickStrength);
    end
    if isfield(ctx.P, 'Section533') && isfield(ctx.P.Section533, 'paperIndependent')
        paperIndependent = logical(ctx.P.Section533.paperIndependent);
    end
catch
    warmKickStrength = 2;
    paperIndependent = false;
end

for i = 1:numel(incPctVec)
    inc = incPctVec(i);
    Gi = override_param_only_G_(G_base, paramName, base_value_(G_base, paramName) * (1 + inc/100));
    if paperIndependent
        incumbentChrom = [];
    end
    useParallelSeeds = false;
    try
        useParallelSeeds = logical(isstruct(parallelCtl) && isfield(parallelCtl, 'enabled') && parallelCtl.enabled ...
            && paperIndependent && numel(seedList) > 1);
    catch
        useParallelSeeds = false;
    end

    runCosts = NaN(1, numel(seedList));
    bestFoundCost = inf;
    bestFoundChrom = [];
    bestSeed = NaN;

    if useParallelSeeds
        runBestChrom = cell(1, numel(seedList));
        runInitStrictFeasible = NaN(1, numel(seedList));
        runFirstFeasibleGen = NaN(1, numel(seedList));
        runStopGen = NaN(1, numel(seedList));
        runElapsedSec = NaN(1, numel(seedList));
        parfor si = 1:numel(seedList)
            seed = seedList(si);
            rng(seed, 'twister');
            GiRun = Gi;
            GiRun.warmStart = struct('enable', false);
            try
                if ~isfield(GiRun, 'opt') || ~isstruct(GiRun.opt)
                    GiRun.opt = struct();
                end
                GiRun.opt.consoleVerbose = false;
            catch
            end
            t0 = tic;
            outRun = one_run_gsaa(NP, MaxGen, Pc, Pm, Pe, T0, Tmin, alpha, STOP_BY_TMIN, GiRun);
            runElapsedSec(si) = toc(t0);
            if isfield(outRun, 'initStrictFeasible')
                runInitStrictFeasible(si) = outRun.initStrictFeasible;
            end
            if isfield(outRun, 'firstFeasibleGen')
                runFirstFeasibleGen(si) = outRun.firstFeasibleGen;
            end
            if isfield(outRun, 'stopGen')
                runStopGen(si) = outRun.stopGen;
            end
            if outRun.bestFeasibleFound
                runCosts(si) = outRun.bestCost;
                runBestChrom{si} = outRun.bestCh;
            end
        end
        if cfg_verbose
            emit_parallel_seed_logs_533_(paramName, inc, seedList, runCosts, runInitStrictFeasible, runFirstFeasibleGen, runStopGen, runElapsedSec, cfg_parallelLogLevel);
        end
        [minCost, minIdx] = min(runCosts);
        if isfinite(minCost)
            bestFoundCost = minCost;
            bestFoundChrom = runBestChrom{minIdx};
            bestSeed = seedList(minIdx);
        end
    else
        for si = 1:numel(seedList)
            seed = seedList(si);
            rng(seed, 'twister');

            GiRun = Gi;
            GiRun.warmStart = struct('enable', false);
            if ~isempty(incumbentChrom)
                if si == 1
                    % 第 1 次运行：精确热启动，保证 pointBest 不会“变差”（至少能复用上一个点的可行解）
                    GiRun.warmStart = struct('enable', true, 'seedChrom', incumbentChrom);
                else
                    % 其余运行：对热启动做轻扰动，提升多次运行的信息量与“继续变优”的概率
                    seedChrom = incumbentChrom;
                    try
                        if exist('kick_mutation_population', 'file') == 2 && warmKickStrength > 0
                            seedChrom = kick_mutation_population(seedChrom, 1.0, warmKickStrength, Gi.n, Gi.K);
                        end
                    catch
                        seedChrom = incumbentChrom;
                    end
                    GiRun.warmStart = struct('enable', true, 'seedChrom', seedChrom);
                end
            end
            try
                if ~isfield(GiRun, 'opt') || ~isstruct(GiRun.opt)
                    GiRun.opt = struct();
                end
                GiRun.opt.consoleVerbose = logical(cfg_verbose);
            catch
            end

            outRun = one_run_gsaa(NP, MaxGen, Pc, Pm, Pe, T0, Tmin, alpha, STOP_BY_TMIN, GiRun);
            if outRun.bestFeasibleFound
                runCosts(si) = outRun.bestCost;
                if outRun.bestCost < bestFoundCost
                    bestFoundCost = outRun.bestCost;
                    bestFoundChrom = outRun.bestCh;
                    bestSeed = seed;
                end
            end
        end
    end

    nFeasible = sum(isfinite(runCosts));
    meanCost = mean(runCosts, 'omitnan');
    stdCost = std(runCosts, 0, 'omitnan');
    if nFeasible == 0
        meanCost = NaN;
        stdCost = NaN;
    end

    % 绘图口径：累计最优 = cummin(当点最优)
    if ~paperIndependent
        if bestFoundCost < incumbentBestCostPlot
            incumbentBestCostPlot = bestFoundCost;
        end
    end

    if paperIndependent
        finalCost = bestFoundCost;
        finalChrom = bestFoundChrom;
        source = 'found';
        [~, isFeasible] = fitness_strict_penalty(finalChrom, Gi);
        incumbentBestCost = finalCost;
        incumbentBestCostPlot = finalCost;
    else
        % incumbent 评估（同一 cost 口径；rg/B0 不进入成本，仅影响可行性/路径）
        incumbentCostEval = inf;
        incumbentFeasible = false;
        incumbentChromEval = incumbentChrom;
        if ~isempty(incumbentChrom)
            [incumbentCostEval, incumbentFeasible, ch_fixed, ~] = fitness_strict_penalty(incumbentChrom, Gi);
            incumbentChromEval = ch_fixed;
            if ~incumbentFeasible
                % 尝试 repair 后再评估（不污染基准 ctx）
                try
                    chRepaired = repair_all_constraints(incumbentChrom, Gi.n, Gi.K, 2, Gi);
                    [incumbentCostEval, incumbentFeasible, ch_fixed2, ~] = fitness_strict_penalty(chRepaired, Gi);
                    incumbentChromEval = ch_fixed2;
                catch
                end
            end
        end

        % final = min(incumbentEval, bestFound)
        if incumbentCostEval <= bestFoundCost
            finalCost = incumbentCostEval;
            finalChrom = incumbentChromEval;
            source = 'incumbent';
            isFeasible = incumbentFeasible;
        else
            finalCost = bestFoundCost;
            finalChrom = bestFoundChrom;
            source = 'found';
            [~, isFeasible] = fitness_strict_penalty(finalChrom, Gi);
        end

        % 累计最优（单调不增）
        if finalCost < incumbentBestCost
            incumbentBestCost = finalCost;
        end

        if i > 1 && incumbentBestCost > tbl(i-1).finalCost + 1e-9
            error('[S533] monotonicity violation: inc=%d%% finalCost=%.6f > prev=%.6f', inc, incumbentBestCost, tbl(i-1).finalCost);
        end

        incumbentChrom = finalChrom;
    end

    det = evaluate_solution_detailed(finalChrom, Gi);

    % ---------- 基准路径核对：仅记录，不改动参数 ----------
    if inc == 0 && (strcmpi(paramName, 'B0') || strcmpi(paramName, 'rg'))
        try
            evIdx = find(Gi.isEV);
            evDist = NaN(1, numel(evIdx));
            evCharge = NaN(1, numel(evIdx));
            evUsed = false(1, numel(evIdx));
            evHasStation = false(1, numel(evIdx));
            evRoutes = cell(1, numel(evIdx));
            for kk = 1:numel(evIdx)
                k = evIdx(kk);
                if k <= numel(det.detail)
                    route = det.detail(k).route;
                    evDist(kk) = det.detail(k).distance;
                    evCharge(kk) = det.detail(k).nCharge;
                    evUsed(kk) = logical(det.detail(k).used);
                    evHasStation(kk) = any(route >= (Gi.n+1) & route <= (Gi.n+Gi.E));
                    evRoutes{kk} = route_to_str_(route);
                end
            end
        catch
        end
    end

    tbl(i).incPct = inc;
    tbl(i).paramValue = base_value_(Gi, paramName);
    tbl(i).runCosts = runCosts;
    tbl(i).meanCost = meanCost;
    tbl(i).stdCost = stdCost;
    tbl(i).pointBestCost = bestFoundCost;
    tbl(i).incumbentBestCost = incumbentBestCostPlot;
    tbl(i).nFeasible = nFeasible;
    tbl(i).bestFoundCost = bestFoundCost;
    tbl(i).incumbentCost = incumbentBestCost;
    tbl(i).finalCost = incumbentBestCost;
    tbl(i).source = source;
    tbl(i).bestSeed = bestSeed;
    tbl(i).isFeasible = logical(det.feasible) && logical(isFeasible);

    tbl(i).fixedCost = det.breakdown.fixedCost;
    tbl(i).travelCost = det.breakdown.travelCost;
    tbl(i).chargeCost = det.breakdown.chargeCost;
    tbl(i).carbonCost = det.breakdown.carbonCost;
    tbl(i).twCost = det.breakdown.twCost;

    tbl(i).totalChargeTime_h = det.ops.totalChargeTime_h;
    tbl(i).nCharges = det.ops.nCharges;
    tbl(i).totalChargedEnergy_kWh = det.ops.totalChargedEnergy_kWh;
    tbl(i).totalLateness_min = det.ops.totalLateness_min;
    tbl(i).maxLateness_min = det.ops.maxLateness_min;

    tbl(i).finalChrom = finalChrom;

    if cfg_verbose
        fprintf('[S533] param=%s inc=%d%% val=%.3f bestFound=%.6f incumbent=%.6f mean=%.6f±%.6f nFeas=%d source=%s\n', ...
            paramName, inc, tbl(i).paramValue, bestFoundCost, incumbentBestCost, meanCost, stdCost, nFeasible, source);
    end
end
end

function foot = build_footer_(ctx, sigBase, modeTag)
foot = sprintf('NP=%d MaxGen=%d NRun=%d T0=%g alpha=%g Tmin=%g | B0=%.1f Bmin=%.1f Bchg=%.1f gE=%.3f rg0=%.1f | 参数签名=%s 数据签名=%s | 运行标签=%s | 模式=%s', ...
    round(ctx.SolverCfg.NP), round(ctx.SolverCfg.MaxGen), round(ctx.SolverCfg.NRun), ctx.SolverCfg.T0, ctx.SolverCfg.alpha, ctx.SolverCfg.Tmin, ...
    ctx.P.EV.B0_kWh, ctx.P.EV.Bmin_kWh, ctx.P.EV.Bchg_kWh, ctx.P.EV.gE_kWh_per_km, ctx.P.EV.rg_kWh_per_h, ...
    sigBase.param.short, sigBase.data.short, ctx.Meta.runTag, char(string(modeTag)));
end

function G2 = override_param_only_G_(G, paramName, newVal)
G2 = G;
switch lower(paramName)
    case 'b0'
        G2.B0 = newVal;
        if isfield(G2,'Bchg')
            G2.Bchg = newVal;
        end
    case 'rg'
        G2.rg = newVal;
    otherwise
        error('override_param_only_G_: only supports B0/rg');
end
end

function v = base_value_(G, paramName)
switch lower(paramName)
    case 'b0'
        v = G.B0;
    case 'rg'
        v = G.rg;
    otherwise
        v = NaN;
end
end

function T = tbl_to_table_(tbl)
% 扁平化导出：runCosts 保留在 mat；表格输出以 summary 字段为主
T = table();
T.incPct = [tbl.incPct]';
T.paramValue = [tbl.paramValue]';
T.nFeasible = [tbl.nFeasible]';
T.meanCost = [tbl.meanCost]';
T.stdCost = [tbl.stdCost]';
if isfield(tbl, 'pointBestCost')
    T.pointBestCost = [tbl.pointBestCost]';
end
if isfield(tbl, 'incumbentBestCost')
    T.incumbentBestCost = [tbl.incumbentBestCost]';
end
T.bestFoundCost = [tbl.bestFoundCost]';
T.incumbentCost = [tbl.incumbentCost]';
T.finalCost = [tbl.finalCost]';
T.fixedCost = [tbl.fixedCost]';
T.travelCost = [tbl.travelCost]';
T.chargeCost = [tbl.chargeCost]';
T.carbonCost = [tbl.carbonCost]';
T.twCost = [tbl.twCost]';
T.totalChargeTime_h = [tbl.totalChargeTime_h]';
T.nCharges = [tbl.nCharges]';
T.totalChargedEnergy_kWh = [tbl.totalChargedEnergy_kWh]';
T.totalLateness_min = [tbl.totalLateness_min]';
T.maxLateness_min = [tbl.maxLateness_min]';
T.bestSeed = [tbl.bestSeed]';
T.source = string({tbl.source})';
T.isFeasible = logical([tbl.isFeasible])';

try
    m = { ...
        'incPct','变化率_百分比'; ...
        'paramValue','参数值'; ...
        'nFeasible','可行次数'; ...
        'meanCost','均值成本'; ...
        'stdCost','标准差成本'; ...
        'pointBestCost','当点最优成本'; ...
        'incumbentBestCost','累计最优成本'; ...
        'bestFoundCost','找到最优成本'; ...
        'incumbentCost','基准成本'; ...
        'finalCost','最终成本'; ...
        'fixedCost','固定成本'; ...
        'travelCost','行驶成本'; ...
        'chargeCost','充电成本'; ...
        'carbonCost','碳排成本'; ...
        'twCost','时间窗成本'; ...
        'totalChargeTime_h','总充电时间_h'; ...
        'nCharges','充电次数'; ...
        'totalChargedEnergy_kWh','充电总电量_kWh'; ...
        'totalLateness_min','总迟到_min'; ...
        'maxLateness_min','最大迟到_min'; ...
        'bestSeed','最佳种子'; ...
        'source','来源'; ...
        'isFeasible','是否可行' ...
        };
    old = T.Properties.VariableNames;
    from = {};
    to = {};
    for i = 1:size(m,1)
        if any(strcmp(old, m{i,1}))
            from{end+1,1} = m{i,1}; %#ok<AGROW>
            to{end+1,1} = m{i,2}; %#ok<AGROW>
        end
    end
    if ~isempty(from)
        T = renamevars(T, from, to);
    end
catch
end
end

function p = replace_ext_(p, newExt)
[d, n] = fileparts(p);
if newExt(1) ~= '.', newExt = ['.' newExt]; end
p = fullfile(d, [n newExt]);
end

function s = route_to_str_(route)
if isempty(route)
    s = '';
    return;
end
try
    s = sprintf('%d->', route);
    if numel(s) >= 3
        s = s(1:end-2);
    end
catch
    s = '';
end
end

function d = route_distance_(route, D)
d = 0;
if isempty(route) || numel(route) < 2
    return;
end
for i = 1:(numel(route)-1)
    d = d + D(route(i)+1, route(i+1)+1);
end
end

function v = route_segments_finite_(route, D)
v = [];
if isempty(route) || numel(route) < 2
    return;
end
v = true(1, numel(route)-1);
for i = 1:(numel(route)-1)
    v(i) = isfinite(D(route(i)+1, route(i+1)+1));
end
end

function v = env_bool_or_default_(name, def)
% 从环境变量读取布尔值（由 run_modes.m 设置）
v = def;
try
    s = getenv(name);
    s = lower(strtrim(char(string(s))));
    if any(strcmp(s, {'1','true','on','yes'}))
        v = true;
    elseif any(strcmp(s, {'0','false','off','no'}))
        v = false;
    end
catch
    v = def;
end
end

function v = env_int_or_default_(name, def)
v = def;
try
    s = getenv(name);
    s = strtrim(char(string(s)));
    if isempty(s)
        return;
    end
    x = str2double(s);
    if isfinite(x)
        v = round(x);
    end
catch
    v = def;
end
end

function v = env_str_or_default_(name, def)
v = def;
try
    s = getenv(name);
    s = strtrim(char(string(s)));
    if ~isempty(s)
        v = s;
    end
catch
    v = def;
end
end

function lv = normalize_parallel_log_level_533_(lvRaw)
lv = lower(strtrim(char(string(lvRaw))));
if ~any(strcmp(lv, {'none', 'summary', 'detailed'}))
    lv = 'detailed';
end
end

function emit_parallel_seed_logs_533_(paramName, incPct, seedList, runCosts, runInitStrictFeasible, runFirstFeasibleGen, runStopGen, runElapsedSec, logLevel)
if strcmp(logLevel, 'none')
    return;
end
nRun = numel(seedList);
for i = 1:nRun
    feas = isfinite(runCosts(i));
    if strcmp(logLevel, 'summary')
        fprintf('[S533][%s][inc=%d%%][run %d/%d] seed=%d | feasible=%d | best=%s | stopGen=%s | elapsed=%ss\n', ...
            paramName, incPct, i, nRun, round(seedList(i)), double(feas), ...
            fmt_num_533_(runCosts(i)), fmt_num_533_(runStopGen(i)), fmt_num_533_(runElapsedSec(i)));
    else
        fprintf('[S533][%s][inc=%d%%][run %d/%d] seed=%d\n', paramName, incPct, i, nRun, round(seedList(i)));
        fprintf('  [初始化] strictFeasible=%s | firstFeasibleGen=%s | stopGen=%s\n', ...
            fmt_num_533_(runInitStrictFeasible(i)), fmt_num_533_(runFirstFeasibleGen(i)), fmt_num_533_(runStopGen(i)));
        fprintf('  [结果] feasible=%d | best=%s | elapsed=%ss\n', ...
            double(feas), fmt_num_533_(runCosts(i)), fmt_num_533_(runElapsedSec(i)));
    end
end
end

function s = fmt_num_533_(v)
if ~isfinite(v)
    s = 'NA';
else
    s = sprintf('%.6f', v);
end
end

function ctl = resolve_parallel_control_533_(requested, workersRequested, nRun, paperIndependent, cfg_verbose, sectionName)
ctl = struct('requested', logical(requested), 'enabled', false, 'workersRequested', round(double(workersRequested)), ...
    'workersActive', 1, 'reason', 'parallel_disabled');
if ~ctl.requested
    ctl.reason = 'parallel_disabled';
    return;
end
if nRun <= 1
    ctl.reason = 'single_run_no_parallel';
    return;
end
if ~paperIndependent
    ctl.reason = 'paper_independent_false_keep_serial';
    return;
end
if exist('parpool', 'file') ~= 2
    ctl.reason = 'parpool_not_available';
    return;
end
try
    hasPct = license('test', 'Distrib_Computing_Toolbox');
catch
    hasPct = false;
end
if ~hasPct
    ctl.reason = 'parallel_license_unavailable';
    return;
end
try
    pool = gcp('nocreate');
    if isempty(pool)
        if ctl.workersRequested > 0
            pool = parpool('local', ctl.workersRequested);
        else
            pool = parpool('local');
        end
    end
    ctl.enabled = true;
    ctl.workersActive = pool.NumWorkers;
    ctl.reason = 'parallel_pool_ready';
catch ME
    ctl.enabled = false;
    ctl.reason = ['parallel_fallback_serial:' char(string(ME.identifier))];
    if cfg_verbose
        warning('run_section_533:parallelFallback', '[%s] 并行初始化失败，回退串行：%s', sectionName, ME.message);
    end
end
end

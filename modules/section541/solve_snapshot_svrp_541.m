function [planNow, solveInfo] = solve_snapshot_svrp_541(ctx, instanceNow, stateBefore, cfg, planPrev)
% 修改日志
% - v16 2026-02-11: 修复并行控制函数作用域错位（get_cfg_value_541_ 被错误嵌套导致运行期未识别）；仅重排本地函数边界，不改求解逻辑。
% - v15 2026-02-10: 新增并行顺序日志级别（none/summary/detailed）；并行模式下输出按 run 序的详细阶段日志并写入 log 文件。
% - v14 2026-02-09: run_gsaa_candidate_541_ 支持 NRun 并行执行（由 cfg.Solver.parallelEnable/workers 控制），并将输出改为有序汇总防止并行日志交叉。
% - v7 2026-01-27: 删除“候选车队枚举”，改为有限车队池（base+maxExtra）并由 GSAA 自然选择是否派车（满足论文机制且降低耗时）。
% - v8 2026-01-27: 快照求解调用 one_run_gsaa_541（GSAA 副本隔离在 section541 内部），避免修改 core/gsaa 影响 5.3.x。
% - v9 2026-01-27: 修复 baseCV/baseEV 随 planPrev 膨胀导致车队池逐轮放大；固定 pool=ctxBase+maxExtra（保持有限上界）。
% - v10 2026-01-29: 为 pendingIds 追加 NaN dummy 槽位：用于表达“未派车/空任务”，避免 core 的 cuts 修复强制每车至少分到 1 个客户而导致不可行/无法体现派车选择。
% - v11 2026-01-30: 移除 debug 日志（seed/feasible 复核已完成）。
% - v12 2026-01-31: warm-start seedChrom 长度校正。
% - v13 2026-01-31: 增加 5 车排查日志（debug）。
% solve_snapshot_svrp_541 - 动态快照 SVRP 求解（冻结段不变；重排待配送段）
% 修改日志
% - v6 2026-01-27: 切换为 GSAA 主程序求解；删除启发式构造；参数与 5.3.x 保持一致；保留候选车队审计。
    if nargin < 5, planPrev = struct(); end

    [logPath, printToConsole] = log_cfg_541_(cfg);
    tNow = NaN;
    try tNow = stateBefore.tNow; catch, end
    tag = sprintf('[t=%s]', min_to_hhmm_541_(tNow));

    baseCV = ctx.P.Fleet.nCV;
    baseEV = ctx.P.Fleet.nEV;

    maxExtraCV = cfg.CandidateFleet.maxExtraCV;
    maxExtraEV = cfg.CandidateFleet.maxExtraEV;

    [pendingIds, activeIds] = pending_customers_541_(instanceNow, stateBefore);
    if isempty(pendingIds)
        [planNow, solveInfo] = build_plan_no_pending_541_(ctx, instanceNow, stateBefore, cfg, planPrev, baseCV, baseEV, activeIds);
        return;
    end

    % ---- 有限车队池：base + maxExtra（不做候选枚举） ----
    nCV = baseCV + maxExtraCV;
    nEV = baseEV + maxExtraEV;
    K = nCV + nEV;

    log_append_541_(logPath, sprintf('%s[fleet_pool] base=CV%d_EV%d | maxExtraCV=%d maxExtraEV=%d -> pool=CV%d_EV%d', ...
        tag, baseCV, baseEV, maxExtraCV, maxExtraEV, nCV, nEV));
    if printToConsole
        fprintf('%s[fleet_pool] base=CV%d_EV%d | maxExtraCV=%d maxExtraEV=%d -> pool=CV%d_EV%d\n', ...
            tag, baseCV, baseEV, maxExtraCV, maxExtraEV, nCV, nEV);
    end

    % NOTE:
    % - core 的 repair_chromosome_deterministic / fixCuts_deterministic 会强制 cuts 落在 [1..n-1] 且长度为 K-1，
    %   这意味着“每辆车至少分到 1 个 index”。
    % - 为了在“车队池”场景下表达“未派车”（以及避免 done/不可用车辆被迫分配真实客户导致永远不可行），
    %   这里人为追加 NaN dummy 槽位；NaN 会在 fitness_snapshot_541 中被过滤，不会进入真实路线。
    nDummy = max(0, K);
    pendingIdsCand = [pendingIds(:); NaN(nDummy, 1)];
    [Gsnap, Gfull, pendingIndex] = build_snapshot_G_541_(ctx, instanceNow, pendingIdsCand, nCV, nEV);
    vehInfo = build_vehicle_info_541_(stateBefore, instanceNow, Gfull, planPrev, cfg, nCV, nEV, K);

    Gsnap.snapshot = struct();
    Gsnap.snapshot.fullG = Gfull;
    Gsnap.snapshot.pendingIds = pendingIdsCand;
    Gsnap.snapshot.pendingIndex = pendingIndex;
    Gsnap.snapshot.vehInfo = vehInfo;
    Gsnap.snapshot.tNow = tNow;
    Gsnap.snapshot.cfg = cfg;
    Gsnap.snapshot.instanceNow = instanceNow;

    if isfield(cfg,'Solver') && isfield(cfg.Solver,'warmStart') && cfg.Solver.warmStart
        seedChrom = build_seed_chrom_541_(vehInfo, pendingIndex, numel(pendingIdsCand), K);
        if ~isempty(seedChrom)
            Gsnap.warmStart = struct('enable', true, 'seedChrom', seedChrom);
        end
    end

    [planNow, solveInfo] = run_gsaa_candidate_541_(ctx, Gsnap, cfg, logPath, printToConsole, tag);
    solveInfo.extraCV = maxExtraCV;
    solveInfo.extraEV = maxExtraEV;
    solveInfo.nCV = nCV;
    solveInfo.nEV = nEV;
    solveInfo.fleetTag = sprintf('CV%d_EV%d', nCV, nEV);
    solveInfo = fill_candidate_metrics_541_(solveInfo, planNow, Gfull, pendingIds, vehInfo, cfg);

    [usedCV, usedEV] = used_fleet_from_plan_541_(planNow, nCV, nEV, Gfull.n);
    solveInfo.usedCV = usedCV;
    solveInfo.usedEV = usedEV;
    solveInfo.usedFleetTag = sprintf('CV%d_EV%d', usedCV, usedEV);

    log_append_541_(logPath, sprintf('%s[fleet_used] used=%s (pool=%s)', tag, solveInfo.usedFleetTag, solveInfo.fleetTag));
    if printToConsole
        fprintf('%s[fleet_used] used=%s (pool=%s)\n', tag, solveInfo.usedFleetTag, solveInfo.fleetTag);
    end

end

% ========================= helpers =========================
function [logPath, printToConsole] = log_cfg_541_(cfg)
    logPath = '';
    printToConsole = false;
    try
        if isfield(cfg,'Log') && isstruct(cfg.Log)
            if isfield(cfg.Log,'logPath'), logPath = char(string(cfg.Log.logPath)); end
            if isfield(cfg.Log,'printToConsole'), printToConsole = logical(cfg.Log.printToConsole); end
        end
    catch
        logPath = '';
        printToConsole = false;
    end
end

function [pendingIds, activeIds] = pending_customers_541_(instanceNow, stateBefore)
    activeIds = [];
    pendingIds = [];
    try
        activeIds = find(instanceNow.Data.q(2:instanceNow.Data.n+1) > 0);
    catch
        activeIds = [];
    end
    frozen = [];
    try frozen = unique(stateBefore.frozenCustomers(:)); catch, frozen = []; end
    pendingIds = setdiff(activeIds, frozen, 'stable');
end

function [planNow, solveInfo] = build_plan_no_pending_541_(ctx, instanceNow, stateBefore, cfg, planPrev, baseCV, baseEV, activeIds)
    nCV = baseCV;
    nEV = baseEV;
    K = nCV + nEV;
    detail = repmat(struct('route',[],'startTimeMin',0), K, 1);

    baseK = numel(stateBefore.vehicles);
    for k = 1:K
        route = [0 0];
        startTimeMin = 0;
        if k <= baseK
            sv = stateBefore.vehicles(k);
            route = sv.frozenNodes(:).';
            if isempty(route), route = [0 0]; end
            if route(1) ~= 0, route = [0 route]; end
            if route(end) ~= 0, route = [route 0]; end
            try
                if isfield(planPrev,'detail') && numel(planPrev.detail) >= k && isfield(planPrev.detail(k),'startTimeMin')
                    startTimeMin = planPrev.detail(k).startTimeMin;
                end
            catch
                startTimeMin = 0;
            end
            if strcmp(sv.phase, 'not_started')
                try startTimeMin = max(startTimeMin, stateBefore.tNow); catch, end
            end
        else
            try startTimeMin = stateBefore.tNow; catch, startTimeMin = 0; end
        end
        detail(k).route = route;
        detail(k).startTimeMin = startTimeMin;
    end

    planNow = struct();
    planNow.detail = detail;
    planNow.nCV = nCV;
    planNow.nEV = nEV;
    planNow.fleetTag = sprintf('CV%d_EV%d', nCV, nEV);

    solveInfo = struct();
    solveInfo.note = 'no_pending_customers';
    solveInfo.activeCount = numel(activeIds);
    solveInfo.feasible = true;
end

function [Gsnap, Gfull, pendingIndex] = build_snapshot_G_541_(ctx, instanceNow, pendingIds, nCV, nEV)
    ctxFull = ctx;
    ctxFull.Data = instanceNow.Data;
    Gfull = build_G_from_ctx(ctxFull, 'nCV', nCV, 'nEV', nEV, 'AllowCharging', true, 'ForceChargeOnce', false, 'ForceChargePolicy', 'ANY_EV');

    dataPend = build_pending_data_541_(instanceNow.Data, pendingIds);
    ctxPend = ctx;
    ctxPend.Data = dataPend;
    Gsnap = build_G_from_ctx(ctxPend, 'nCV', nCV, 'nEV', nEV, 'AllowCharging', true, 'ForceChargeOnce', false, 'ForceChargePolicy', 'ANY_EV');

    pendingIndex = NaN(instanceNow.Data.n, 1);
    for i = 1:numel(pendingIds)
        cid = pendingIds(i);
        if isfinite(cid) && cid >= 1 && cid <= instanceNow.Data.n
            pendingIndex(cid) = i;
        end
    end
end

function dataPend = build_pending_data_541_(dataFull, pendingIds)
    nPending = numel(pendingIds);
    nAll = dataFull.n;
    E = dataFull.E;

    coord = NaN(1 + nPending + E, 2);
    q = zeros(1 + nPending + E, 1);
    LT = NaN(1 + nPending + E, 1);
    RT = NaN(1 + nPending + E, 1);

    coord(1,:) = dataFull.coord(1,:);
    q(1) = dataFull.q(1);
    LT(1) = dataFull.LT(1);
    RT(1) = dataFull.RT(1);

    for i = 1:nPending
        cid = pendingIds(i);
        if isfinite(cid) && cid >= 1 && cid <= nAll
            coord(i+1,:) = dataFull.coord(cid+1,:);
            q(i+1) = dataFull.q(cid+1);
            LT(i+1) = dataFull.LT(cid+1);
            RT(i+1) = dataFull.RT(cid+1);
        else
            coord(i+1,:) = dataFull.coord(1,:);
            q(i+1) = 0;
            LT(i+1) = 0;
            RT(i+1) = 1440;
        end
    end

    for r = 1:E
        fullNode = nAll + r;
        newNode = nPending + r;
        coord(newNode+1,:) = dataFull.coord(fullNode+1,:);
        q(newNode+1) = dataFull.q(fullNode+1);
        LT(newNode+1) = dataFull.LT(fullNode+1);
        RT(newNode+1) = dataFull.RT(fullNode+1);
    end

    dataPend = struct();
    dataPend.coord = coord;
    dataPend.q = q;
    dataPend.LT = LT;
    dataPend.RT = RT;
    dataPend.n = nPending;
    dataPend.E = E;
    dataPend.ST = dataFull.ST;
    dataPend.D = pairwise_dist_fast(coord);
end

function vehInfo = build_vehicle_info_541_(stateBefore, instanceNow, Gfull, planPrev, cfg, nCV, nEV, K) %#ok<INUSD>
    baseK = numel(stateBefore.vehicles);
    vehInfo = repmat(struct(), K, 1);
    for k = 1:K
        isEV = (k > nCV);
        prefix = [0];
        phase = 'not_started';
        available = true;
        committedLoad = 0;
        startTimeMin = 0;
        endBat = NaN;

        if k <= baseK
            sv = stateBefore.vehicles(k);
            prefix = sv.frozenNodes(:).';
            if isempty(prefix), prefix = [0]; end
            if prefix(1) ~= 0, prefix = [0 prefix]; end
            phase = sv.phase;
            if strcmp(phase, 'done')
                available = false;
            end
            try
                vehInfo(k).pendingSeed = sv.pendingCustomers(:).';
            catch
                vehInfo(k).pendingSeed = [];
            end
            frozen = [];
            servedOrStarted = [];
            try frozen = unique(sv.frozenCustomers(:)); catch, frozen = []; end
            try servedOrStarted = unique(sv.servedOrStartedCustomers(:)); catch, servedOrStarted = []; end
            committed = setdiff(frozen, servedOrStarted);
            committed = committed(isfinite(committed) & committed>=1 & committed<=instanceNow.Data.n);
            try committedLoad = sum(instanceNow.Data.q(committed+1)); catch, committedLoad = 0; end
            try endBat = sv.frozenEndBatteryKWh; catch, endBat = NaN; end
            try
                if isfield(planPrev,'detail') && numel(planPrev.detail) >= k && isfield(planPrev.detail(k),'startTimeMin')
                    startTimeMin = planPrev.detail(k).startTimeMin;
                end
            catch
                startTimeMin = 0;
            end
            if strcmp(phase, 'not_started')
                % 未出发车辆：出发时刻允许在后续更新中前移/后移；此处仅给 tNow 下界（具体 startTimeMin 由 fitness 内部按首客户 LT 回推）。
                try startTimeMin = stateBefore.tNow; catch, end
                if isEV
                    endBat = Gfull.B0;
                end
            end
        else
            prefix = [0];
            available = true;
            phase = 'not_started';
            try startTimeMin = stateBefore.tNow; catch, startTimeMin = 0; end
            if isEV, endBat = Gfull.B0; end
            committedLoad = 0;
            vehInfo(k).pendingSeed = [];
        end

        vehInfo(k).k = k;
        vehInfo(k).isEV = isEV;
        vehInfo(k).prefixNodes = prefix;
        vehInfo(k).phase = phase;
        vehInfo(k).available = available;
        vehInfo(k).committedLoadKg = committedLoad;
        vehInfo(k).startTimeMin = startTimeMin;
        vehInfo(k).batteryEndKWh = endBat;
    end
end

function seedChrom = build_seed_chrom_541_(vehInfo, pendingIndex, nPending, K)
    seedChrom = [];
    if nPending <= 0 || K <= 0
        return;
    end
    routes = cell(K,1);
    assigned = [];
    for k = 1:K
        routes{k} = [];
        if ~vehInfo(k).available
            continue;
        end
        try
            if isfield(vehInfo(k),'pendingSeed')
                ids = vehInfo(k).pendingSeed(:);
            else
                ids = [];
            end
        catch
            ids = [];
        end
        if isempty(ids)
            continue;
        end
        idx = [];
        for i = 1:numel(ids)
            cid = ids(i);
            if cid >= 1 && cid <= numel(pendingIndex) && isfinite(pendingIndex(cid))
                idx(end+1) = pendingIndex(cid); %#ok<AGROW>
            end
        end
        idx = unique(idx, 'stable');
        routes{k} = idx(:).';
        assigned = [assigned idx(:).']; %#ok<AGROW>
    end
    assigned = unique(assigned, 'stable');
    missing = setdiff(1:nPending, assigned, 'stable');
    if ~isempty(missing)
        avail = find([vehInfo.available]);
        if isempty(avail)
            avail = 1:K;
        end
        ai = 1;
        for i = 1:numel(missing)
            k = avail(ai);
            routes{k}(end+1) = missing(i); %#ok<AGROW>
            ai = ai + 1;
            if ai > numel(avail), ai = 1; end
        end
    end
    try
        [perm, cuts] = merge_routes_to_perm_pub(routes, nPending, K);
        seedChrom = [perm cuts];
    catch
        seedChrom = [];
    end
    % ensure seed length = nPending + (K-1)
    expLen = nPending + max(K-1, 0);
    if isempty(seedChrom) || numel(seedChrom) ~= expLen
        try
            perm = 1:nPending;
            cuts = fixCuts_deterministic([], nPending, K);
            seedChrom = [perm cuts];
            seedChrom = repair_chromosome_deterministic(seedChrom, nPending, K, struct());
        catch
            seedChrom = [];
        end
    end
end

function [candPlan, candInfo] = run_gsaa_candidate_541_(ctx, Gsnap, cfg, logPath, printToConsole, tag)
    NP = ctx.SolverCfg.NP;
    MaxGen = ctx.SolverCfg.MaxGen;
    Pc = ctx.SolverCfg.Pc;
    Pm = ctx.SolverCfg.Pm;
    Pe = ctx.SolverCfg.Pe;
    T0 = ctx.SolverCfg.T0;
    Tmin = ctx.SolverCfg.Tmin;
    alpha = ctx.SolverCfg.alpha;
    STOP_BY_TMIN = ctx.SolverCfg.STOP_BY_TMIN;
    NRun = ctx.SolverCfg.NRun;
    if ~isfinite(NRun) || NRun < 1, NRun = 1; end
    parallelLogLevel = normalize_parallel_log_level_541_(get_cfg_value_541_(cfg, 'Solver.parallelLogLevel', 'detailed'));

    parallelCtl = resolve_parallel_control_541_(cfg, NRun, printToConsole, tag);
    if printToConsole
        fprintf('%s[gsaa] NRun=%d | parallel=%d(workers=%d) | logLevel=%s | reason=%s\n', ...
            tag, NRun, double(parallelCtl.enabled), round(parallelCtl.workersActive), ...
            char(string(parallelLogLevel)), char(string(parallelCtl.reason)));
    end
    log_append_541_(logPath, sprintf('%s[gsaa] NRun=%d | parallel=%d(workers=%d) | logLevel=%s | reason=%s', ...
        tag, NRun, double(parallelCtl.enabled), round(parallelCtl.workersActive), char(string(parallelLogLevel)), char(string(parallelCtl.reason))));

    bestFeas = inf; bestFeasCh = []; bestFeasDetail = []; bestFeasRun = NaN; bestFeasSeed = NaN;
    bestPen = inf;  bestPenCh = []; bestPenRun = NaN; bestPenSeed = NaN;

    runRec = repmat(struct('seed', NaN, 'feasible', false, 'cost', NaN, 'ch', [], 'penCost', inf, 'penCh', [], ...
        'initStrictFeasible', NaN, 'firstFeasibleGen', NaN, 'stopGen', NaN, 'elapsedSec', NaN), NRun, 1);

    if parallelCtl.enabled
        parfor run = 1:NRun
            seed = set_rng_for_run_541_(cfg, run);
            GsnapRun = Gsnap;
            try
                if ~isfield(GsnapRun, 'opt') || ~isstruct(GsnapRun.opt)
                    GsnapRun.opt = struct();
                end
                GsnapRun.opt.consoleVerbose = false;
            catch
            end
            t0 = tic;
            outRun = one_run_gsaa_541(NP, MaxGen, Pc, Pm, Pe, T0, Tmin, alpha, STOP_BY_TMIN, GsnapRun, 'FitnessFcn', @fitness_snapshot_541);
            rec = struct('seed', seed, 'feasible', logical(outRun.bestFeasibleFound), 'cost', NaN, 'ch', [], 'penCost', inf, 'penCh', [], ...
                'initStrictFeasible', NaN, 'firstFeasibleGen', NaN, 'stopGen', NaN, 'elapsedSec', toc(t0));
            if rec.feasible
                rec.cost = outRun.bestCost;
                rec.ch = outRun.bestCh;
            end
            if isfield(outRun,'bestPenaltyCost') && isfinite(outRun.bestPenaltyCost)
                rec.penCost = outRun.bestPenaltyCost;
            end
            if isfield(outRun,'bestPenaltyCh')
                rec.penCh = outRun.bestPenaltyCh;
            end
            if isfield(outRun, 'initStrictFeasible')
                rec.initStrictFeasible = outRun.initStrictFeasible;
            end
            if isfield(outRun, 'firstFeasibleGen')
                rec.firstFeasibleGen = outRun.firstFeasibleGen;
            end
            if isfield(outRun, 'stopGen')
                rec.stopGen = outRun.stopGen;
            end
            runRec(run) = rec;
        end
    else
        for run = 1:NRun
            seed = set_rng_for_run_541_(cfg, run);
            if printToConsole
                fprintf('%s[gsaa] run %d/%d (seed=%g)\n', tag, run, NRun, seed);
            end
            log_append_541_(logPath, sprintf('%s[gsaa] run %d/%d (seed=%g)', tag, run, NRun, seed));

            GsnapRun = Gsnap;
            try
                if ~isfield(GsnapRun, 'opt') || ~isstruct(GsnapRun.opt)
                    GsnapRun.opt = struct();
                end
                GsnapRun.opt.consoleVerbose = logical(printToConsole);
            catch
            end
            t0 = tic;
            outRun = one_run_gsaa_541(NP, MaxGen, Pc, Pm, Pe, T0, Tmin, alpha, STOP_BY_TMIN, GsnapRun, 'FitnessFcn', @fitness_snapshot_541);

            rec = struct('seed', seed, 'feasible', logical(outRun.bestFeasibleFound), 'cost', NaN, 'ch', [], 'penCost', inf, 'penCh', [], ...
                'initStrictFeasible', NaN, 'firstFeasibleGen', NaN, 'stopGen', NaN, 'elapsedSec', toc(t0));
            if rec.feasible
                rec.cost = outRun.bestCost;
                rec.ch = outRun.bestCh;
            end
            if isfield(outRun,'bestPenaltyCost') && isfinite(outRun.bestPenaltyCost)
                rec.penCost = outRun.bestPenaltyCost;
            end
            if isfield(outRun,'bestPenaltyCh')
                rec.penCh = outRun.bestPenaltyCh;
            end
            if isfield(outRun, 'initStrictFeasible')
                rec.initStrictFeasible = outRun.initStrictFeasible;
            end
            if isfield(outRun, 'firstFeasibleGen')
                rec.firstFeasibleGen = outRun.firstFeasibleGen;
            end
            if isfield(outRun, 'stopGen')
                rec.stopGen = outRun.stopGen;
            end
            runRec(run) = rec;
        end
    end

    if parallelCtl.enabled
        emit_parallel_run_logs_541_(tag, runRec, NRun, parallelLogLevel, printToConsole, logPath);
    end

    for run = 1:NRun
        if ~parallelCtl.enabled
            log_append_541_(logPath, sprintf('%s[gsaa][run %d/%d] seed=%g | feasible=%d | best=%s', ...
                tag, run, NRun, runRec(run).seed, double(runRec(run).feasible), fmt_num_541_(runRec(run).cost)));
        end
        if runRec(run).feasible && runRec(run).cost < bestFeas
            bestFeas = runRec(run).cost;
            bestFeasCh = runRec(run).ch;
            bestFeasDetail = [];
            bestFeasRun = run;
            bestFeasSeed = runRec(run).seed;
        end
        if isfinite(runRec(run).penCost) && runRec(run).penCost < bestPen
            bestPen = runRec(run).penCost;
            bestPenCh = runRec(run).penCh;
            bestPenRun = run;
            bestPenSeed = runRec(run).seed;
        end
    end

    candInfo = struct();
    candInfo.nRun = NRun;
    candInfo.bestFeasibleCost = bestFeas;
    candInfo.bestPenaltyCost = bestPen;
    candInfo.bestRun = bestFeasRun;
    candInfo.bestSeed = bestFeasSeed;
    candInfo.note = '';

    if isfinite(bestFeas)
        candInfo.feasible = true;
        detail = bestFeasDetail;
        if isempty(detail)
            [~,~,~,detail] = fitness_snapshot_541(bestFeasCh, Gsnap);
        end
        candPlan = build_plan_struct_541_(detail, Gsnap);
    else
        candInfo.feasible = false;
        candInfo.note = 'no_feasible_solution';
        detail = [];
        if ~isempty(bestPenCh)
            [~,~,~,detail] = fitness_snapshot_541(bestPenCh, Gsnap);
        end
        candPlan = build_plan_struct_541_(detail, Gsnap);
        candInfo.bestRun = bestPenRun;
        candInfo.bestSeed = bestPenSeed;
    end

    candInfo.bestPenaltyPlan = candPlan;
end

function ctl = resolve_parallel_control_541_(cfg, nRun, printToConsole, tag)
ctl = struct('requested', false, 'enabled', false, 'workersRequested', 0, 'workersActive', 1, 'reason', 'parallel_disabled');
try
    ctl.requested = logical(cfg.Solver.parallelEnable);
    ctl.workersRequested = round(double(cfg.Solver.parallelWorkers));
catch
    ctl.requested = false;
    ctl.workersRequested = 0;
end
if ~ctl.requested
    ctl.reason = 'parallel_disabled';
    return;
end
if nRun <= 1
    ctl.reason = 'single_run_no_parallel';
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
    if printToConsole
        warning('solve_snapshot_svrp_541:parallelFallback', '%s[gsaa] 并行初始化失败，回退串行：%s', tag, ME.message);
    end
end
end

function emit_parallel_run_logs_541_(tag, runRec, nRun, logLevel, printToConsole, logPath)
if strcmp(logLevel, 'none')
    return;
end
for run = 1:nRun
    rec = runRec(run);
    if strcmp(logLevel, 'summary')
        line = sprintf('%s[gsaa][run %d/%d] seed=%g | feasible=%d | best=%s | stopGen=%s | elapsed=%ss', ...
            tag, run, nRun, rec.seed, double(rec.feasible), fmt_num_541_(rec.cost), fmt_num_541_(rec.stopGen), fmt_num_541_(rec.elapsedSec));
        if printToConsole
            fprintf('%s\n', line);
        end
        log_append_541_(logPath, line);
    else
        line1 = sprintf('%s[gsaa][run %d/%d] seed=%g', tag, run, nRun, rec.seed);
        line2 = sprintf('  [初始化] strictFeasible=%s | firstFeasibleGen=%s | stopGen=%s', ...
            fmt_num_541_(rec.initStrictFeasible), fmt_num_541_(rec.firstFeasibleGen), fmt_num_541_(rec.stopGen));
        line3 = sprintf('  [结果] feasible=%d | best=%s | penaltyBest=%s | elapsed=%ss', ...
            double(rec.feasible), fmt_num_541_(rec.cost), fmt_num_541_(rec.penCost), fmt_num_541_(rec.elapsedSec));
        if printToConsole
            fprintf('%s\n', line1);
            fprintf('%s\n', line2);
            fprintf('%s\n', line3);
        end
        log_append_541_(logPath, line1);
        log_append_541_(logPath, line2);
        log_append_541_(logPath, line3);
    end
end
end

function lv = normalize_parallel_log_level_541_(lvRaw)
lv = lower(strtrim(char(string(lvRaw))));
if ~any(strcmp(lv, {'none', 'summary', 'detailed'}))
    lv = 'detailed';
end
end

function v = get_cfg_value_541_(cfg, dotted, def)
v = def;
try
    parts = strsplit(char(string(dotted)), '.');
    cur = cfg;
    for i = 1:numel(parts)
        key = char(string(parts{i}));
        if ~isstruct(cur) || ~isfield(cur, key)
            return;
        end
        cur = cur.(key);
    end
    v = cur;
catch
    v = def;
end
end

function s = fmt_num_541_(v)
if ~isfinite(v)
    s = 'NA';
else
    s = sprintf('%.6f', v);
end
end

function seed = set_rng_for_run_541_(cfg, run)
    seed = run;
    try
        s = cfg.Solver.seed;
        if ischar(s) && strcmpi(s, 'shuffle')
            rng('shuffle');
            st = rng;
            seed = st.Seed;
            return;
        end
        if isstring(s), s = char(s); end
        if isnumeric(s) && isfinite(s)
            seed = round(s) + (run - 1);
            rng(seed, 'twister');
            return;
        end
    catch
    end
    rng(run, 'twister');
    seed = run;
end

function plan = build_plan_struct_541_(detail, Gsnap)
    nCV = Gsnap.nCV;
    nEV = Gsnap.nEV;
    if isempty(detail)
        detail = repmat(struct('route',[0 0],'startTimeMin',0), nCV+nEV, 1);
    end
    plan = struct();
    plan.detail = detail;
    plan.nCV = nCV;
    plan.nEV = nEV;
    plan.fleetTag = sprintf('CV%d_EV%d', nCV, nEV);
end

function [usedCV, usedEV] = used_fleet_from_plan_541_(plan, nCV, nEV, nCustomer)
    usedCV = 0;
    usedEV = 0;
    if ~isfield(plan,'detail') || isempty(plan.detail)
        return;
    end
    K = min(numel(plan.detail), nCV+nEV);
    used = false(K,1);
    for k = 1:K
        r = [];
        try r = plan.detail(k).route(:); catch, r = []; end
        if isempty(r), continue; end
        used(k) = any(isfinite(r) & (r>=1) & (r<=nCustomer));
    end
    if nCV > 0
        usedCV = sum(used(1:min(nCV,K)));
    end
    if nEV > 0 && K > nCV
        usedEV = sum(used((nCV+1):K));
    end
end

function [cnt, pairs] = count_pending_reassign_541_(vehInfo, detail, pendingIds, nCustomer)
    cnt = 0;
    pairs = {};
    if isempty(detail)
        return;
    end
    K = min(numel(detail), numel(vehInfo));
    owner = zeros(nCustomer, 1);
    for k = 1:K
        ids = [];
        try ids = vehInfo(k).pendingSeed(:); catch, ids = []; end
        ids = ids(isfinite(ids) & ids>=1 & ids<=nCustomer);
        for ii = 1:numel(ids)
            cid = ids(ii);
            if owner(cid) == 0
                owner(cid) = k;
            end
        end
    end
    for k = 1:K
        r = [];
        try r = detail(k).route(:); catch, r = []; end
        if isempty(r), continue; end
        cus = r(r>=1 & r<=nCustomer);
        if isempty(cus), continue; end
        for ii = 1:numel(cus)
            cid = cus(ii);
            if ~ismember(cid, pendingIds), continue; end
            ok = (owner(cid) == 0) || (owner(cid) == k);
            if ~ok
                cnt = cnt + 1;
                pairs{end+1,1} = sprintf('cid=%d:%d->%d', cid, owner(cid), k); %#ok<AGROW>
            end
        end
    end
end

function candInfo = fill_candidate_metrics_541_(candInfo, candPlan, Gfull, pendingIds, vehInfo, cfg)
    try
        timeline = simulate_timeline_541(Gfull, candPlan.detail, cfg);
        candInfo.totalCost = timeline.summary.totalCost;
        candInfo.distanceKm = timeline.summary.distanceKm;
        candInfo.nCharge = timeline.summary.nCharge;
        candInfo.vioTw = timeline.summary.vioTw;
        candInfo.vioBat = timeline.summary.vioBat;
    catch
        candInfo.totalCost = NaN;
        candInfo.distanceKm = NaN;
        candInfo.nCharge = NaN;
        candInfo.vioTw = NaN;
        candInfo.vioBat = NaN;
    end
    try
        candInfo.vioCap = cap_violation_541_(vehInfo, candPlan.detail, pendingIds, Gfull);
    catch
        candInfo.vioCap = NaN;
    end
end

function vcap = cap_violation_541_(vehInfo, detail, pendingIds, Gfull)
    vcap = 0;
    if isempty(detail)
        return;
    end
    for k = 1:min(numel(vehInfo), numel(detail))
        route = [];
        try route = detail(k).route(:); catch, route = []; end
        if isempty(route)
            continue;
        end
        cus = route(route>=1 & route<=Gfull.n);
        if isempty(cus)
            pendingLoad = 0;
        else
            mask = ismember(cus, pendingIds);
            pend = cus(mask);
            pendingLoad = sum(Gfull.q(pend+1));
        end
        committed = vehInfo(k).committedLoadKg;
        cap = Gfull.Qmax(k);
        if isfinite(cap) && (committed + pendingLoad > cap)
            vcap = vcap + (committed + pendingLoad - cap) / max(cap, 1);
        end
    end
end

function candList = append_candidate_541_(candList, candInfo)
    if isempty(candList)
        candList = candInfo;
    else
        candList(end+1) = candInfo; %#ok<AGROW>
    end
end

function log_candidate_541_(logPath, printToConsole, ci, tag)
    line = sprintf('%s[fleet_cand] extraCV=%d extraEV=%d fleet=%s feasible=%d cost=%.2f dist=%.2f nCharge=%d vioTw=%.2f vioBat=%.2f vioCap=%.2f note=%s', ...
        tag, ci.extraCV, ci.extraEV, ci.fleetTag, double(ci.feasible), ci.totalCost, ci.distanceKm, ci.nCharge, ci.vioTw, ci.vioBat, ci.vioCap, char(string(ci.note)));
    log_append_541_(logPath, line);
    if printToConsole
        fprintf('%s\n', line);
    end
end

function explain_fleet_choice_541_(logPath, printToConsole, candList, solveInfo, tag)
    if isempty(candList)
        return;
    end
    best = solveInfo;
    line = sprintf('%s[fleet_choice] best=%s feasible=%d cost=%.2f extraCV=%d extraEV=%d', ...
        tag, best.fleetTag, double(best.feasible), best.totalCost, best.bestExtraCV, best.bestExtraEV);
    log_append_541_(logPath, line);
    if printToConsole, fprintf('%s\n', line); end

    if best.bestExtraCV == 0 && best.bestExtraEV == 0
        % 解释不增车：列出第二优候选
        costs = [candList.totalCost];
        feas = [candList.feasible];
        costs(~feas) = inf;
        [~, ord] = sort(costs, 'ascend');
        if numel(ord) >= 2 && isfinite(costs(ord(2)))
            alt = candList(ord(2));
            line2 = sprintf('%s[fleet_choice] reason=no_extra_vehicle (others higher cost) | alt=%s cost=%.2f', ...
                tag, alt.fleetTag, alt.totalCost);
            log_append_541_(logPath, line2);
            if printToConsole, fprintf('%s\n', line2); end
        end
    end
end

function log_append_541_(filePath, line)
    if isempty(filePath), return; end
    ensure_dir(fileparts(filePath));
    fid = fopen(filePath, 'a');
    if fid < 0
        return;
    end
    c = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', char(string(line)));
end

function s = min_to_hhmm_541_(tMin)
    if ~isfinite(tMin)
        s = 'NaN';
        return;
    end
    h = floor(tMin/60);
    m = round(tMin - 60*h);
    s = sprintf('%02d:%02d', h, m);
end

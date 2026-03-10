function out = run_section_541(ctx)
% 修改日志
% - v19 2026-02-10: 新增 SECTION541_PARALLEL_LOG_LEVEL；并行模式下输出按 run 序的顺序化详细日志（none/summary/detailed）。
% - v18 2026-02-09: 新增 SECTION541_PARALLEL_ENABLE/WORKERS 并行开关透传到快照 GSAA NRun；并优化日志提示并行状态。
% - v1 2026-01-24: 新增 section_541（论文 5.4.1 动态需求下车辆组合与调度 DVRP）；含 ctx guard + RNG 隔离；动态逻辑隔离在 modules/section541。
% - v2 2026-01-24: 补充 cfg 开关注释（SECTION541_*）；并确保 531 自动引导不影响 541 的 RNG 序列（见 helper 内部保存/恢复）。
% - v3 2026-01-24: 补齐 541 开关面板中文旁注（含义/默认值/允许调整范围/仅 generalize 生效项）。
% - v4 2026-01-24: generalize 支持 SECTION541_WINDOW/MAX_EXTRAEV/MAX_EXTRACV；并追加输出稳定文件 logs/align_report.txt（不覆盖）。
% - v5 2026-01-24: 增加终端进度提示 + drawnow 刷新，避免 Cursor/VSCode 误判“卡死”。
% - v6 2026-01-25: 输出表格表头/枚举中文化；并明确说明 541 不使用 GSAA 的 NRun（避免误解“太快=没算”）。
% - v7 2026-01-25: 增加 DataPolicy（默认优先 data/ 表格数据）并打印数据源路径；并为 11.2/11.3 预留 servedOrStarted 与候选审计字段。

% - v8 2026-01-25: 新增快照求解循环次数/控制台详输出开关（由 run_modes 面板统一设置并同步）。
% - v9 2026-01-27: 论文示例静态/动态数据优先；事件/初始/方案/成本分子目录输出；图例仅保留路径；表格中文结构与累计成本对齐；图窗保留与表格终端输出可控。
% - v10 2026-01-27: 快照求解切换为 GSAA 主程序（与 5.3.x 参数一致）；移除 snapshotNRun；终端表格输出改为格式化打印避免科学计数法。
% - v11 2026-01-27: Table5.6 需求类型输出优先沿用原始类型（新增/取消/减少/增加）；若仅有 update 则按 delta 符号映射减少/增加（仅影响表格展示）。
% - v12 2026-01-29: paper_repro 下覆盖车队基数为 5/5；增加需求驱动“额外 EV”提示与日志。
% - v13 2026-01-29: paper_repro：初始方案固定为 2CV+2EV（表5.7）；车队池固定为论文可用车队 5CV+5EV（不允许超出）；并将 4 路初始方案映射到 5/5 的车位上，避免 CV/EV 编号/车型错位。
% - v14 2026-01-29: paper_repro：初始方案来源恢复为 section_531（论文 5.3.1 的逻辑链），不再手抄表5.7；并用“首客户 LT 回推”推导出发时刻（可与表5.7对照）；若与表5.7不一致仅做差异报告不覆盖结果。
% - v15 2026-01-30: section_541 默认 seed 改为 1（用户指定）；与 run_modes 的 SECTION541_SEED=1 对齐。
% - v16 2026-01-31: paper_repro：若初始方案与表5.7不一致，改用表5.7作为初始方案并记录覆盖原因。
% - v17 2026-01-31: 遵循硬约束：初始方案仅来自 5.3.1，禁用 Table5.7 覆盖，仅差异报告。
sectionName = 'section_541';

% 统一输出路径/签名（供 enforce_section_spec 静态检查）
paths = output_paths(ctx.Meta.projectRoot, sectionName, ctx.Meta.runTag);
sig = build_signature(ctx);

% ===== RNG 隔离（保存-设置-恢复）=====
rngStateBefore = rng;
rngBeforePath = fullfile(paths.mats, artifact_filename('rng_before', sectionName, 'guard', sig.param.short, sig.data.short, ctx.Meta.timestamp, '.mat'));
save(rngBeforePath, 'rngStateBefore');

% ===== ctx guard（禁止修改 ctx/全局参数）=====
ctxSigBefore = build_signature(ctx);
keyCfgBefore = guard_snapshot_541_(ctx);
guardBeforePath = fullfile(paths.mats, artifact_filename('guard_before', sectionName, 'guard', sig.param.short, sig.data.short, ctx.Meta.timestamp, '.mat'));
save(guardBeforePath, 'ctxSigBefore', 'keyCfgBefore');

% ===== cfg（本 section 局部配置；不写回 ctx）=====
cfg = default_cfg_541_(ctx);
modeTag = cfg.Mode;

modeLabel = '';
algoProfile = '';
try, modeLabel = char(string(ctx.Meta.modeLabel)); catch, end
try, algoProfile = char(string(ctx.Meta.algoProfile)); catch, end
if isempty(modeLabel), modeLabel = 'UNKNOWN'; end
if isempty(algoProfile), algoProfile = 'UNKNOWN'; end
fprintf('[%s] runTag=%s | modeLabel=%s | algoProfile=%s | modeTag=%s | paramSig=%s | dataSig=%s\n', ...
    sectionName, ctx.Meta.runTag, modeLabel, algoProfile, modeTag, sig.param.short, sig.data.short);
try
    w = cfg.Dynamic.windowOverride;
    wtxt = 'auto';
    if ~isempty(w) && numel(w) == 2 && all(isfinite(w))
        wtxt = sprintf('%g-%g', w(1), w(2));
    end
    seedTxt = '';
    try seedTxt = char(string(cfg.Solver.seed)); catch, end
    fprintf('[%s] q=%gkg T=%gmin qAccum=%s | windowOverride=%s | maxExtraEV=%d maxExtraCV=%d | seed=%s warmStart=%d\n', ...
        sectionName, cfg.Dynamic.qKg, cfg.Dynamic.TMin, char(string(cfg.Dynamic.qAccumPolicy)), wtxt, ...
        round(cfg.CandidateFleet.maxExtraEV), round(cfg.CandidateFleet.maxExtraCV), seedTxt, double(cfg.Solver.warmStart));
catch
end
try
    nrun = NaN;
    try nrun = ctx.SolverCfg.NRun; catch, end
    if ~isfinite(nrun) || nrun < 1, nrun = 1; end
    fprintf('[%s] solver=GSAA | NRun=%d | consoleVerbose=%d | parallel=%d(workers=%d) | parallelLogLevel=%s\n', ...
        sectionName, round(nrun), double(cfg.Log.printToConsole), double(cfg.Solver.parallelEnable), round(cfg.Solver.parallelWorkers), ...
        char(string(cfg.Solver.parallelLogLevel)));
catch
end
try
    fprintf('[%s] dataPolicy=%s\n', sectionName, char(string(cfg.DataPolicy)));
catch
end
try
    fprintf('[%s] 提示：快照使用 GSAA 主程序，NRun 与 5.3.x 保持一致。\n', sectionName);
catch
end
fprintf('[%s] 提示：每次更新将依次执行：状态图 -> 事件批处理 -> 求解 -> 仿真 -> 优化图/写表/落盘；两次输出间无新行属于正常计算中。\n', sectionName);
drawnow('limitrate');

logPath = fullfile(paths.logs, artifact_filename('run_log', sectionName, modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.txt'));
alignReportPath = fullfile(paths.logs, artifact_filename('align_report', sectionName, modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.txt'));
guardReportPath = fullfile(paths.logs, artifact_filename('guard_report', sectionName, 'guard', sig.param.short, sig.data.short, ctx.Meta.timestamp, '.txt'));
rngGuardReportPath = fullfile(paths.logs, artifact_filename('rng_guard_report', sectionName, 'guard', sig.param.short, sig.data.short, ctx.Meta.timestamp, '.txt'));

% 子目录：按类型分类输出（图/表）
figStateDir = fullfile(paths.figures, 'state');
figPlanDir = fullfile(paths.figures, 'plan');
tblEventsDir = fullfile(paths.tables, 'events');
tblInitDir = fullfile(paths.tables, 'init');
tblPlanDir = fullfile(paths.tables, 'plan');
tblCostDir = fullfile(paths.tables, 'cost');
try
    ensure_dir(figStateDir);
    ensure_dir(figPlanDir);
    ensure_dir(tblEventsDir);
    ensure_dir(tblInitDir);
    ensure_dir(tblPlanDir);
    ensure_dir(tblCostDir);
catch
end

% 设置 541 的 RNG（仅在 541 内部有效，结束前恢复）
cfg = rng_setup_541_(cfg, logPath);
try
    if ~isfield(cfg,'Log') || ~isstruct(cfg.Log)
        cfg.Log = struct();
    end
    cfg.Log.logPath = logPath; % 541 内部审计日志（候选车队/需求压力等）；不写回 ctx
    if ~isfield(cfg.Log,'printToConsole') || isempty(cfg.Log.printToConsole)
        cfg.Log.printToConsole = false; % 由 run_modes 的 SECTION541_CONSOLE_VERBOSE 控制（默认开）
    end
catch
end

% ===== 论文示例数据文件（缺失则自动生成；仅影响 541）=====
paperInfo = struct();
try
    paperInfo = ensure_paper_data_files_541(ctx.Meta.projectRoot, cfg.PaperFiles.staticName, cfg.PaperFiles.dynamicName, logPath, alignReportPath);
    cfg.PaperFiles.staticPath = paperInfo.staticPath;
    cfg.PaperFiles.dynamicPath = paperInfo.dynamicPath;
catch
    paperInfo = struct();
end

% ===== DataPolicy：静态基准数据优先从 data/ 读取（局部 ctxWork；不写回 ctx）=====
[ctxWork, dataDiag] = apply_data_policy_541_(ctx, cfg, logPath, alignReportPath);
ctxWork = apply_paper_fleet_override_541_(ctxWork, cfg, logPath, alignReportPath);
try
    % 使用 ctxWork 更新签名（后续产物命名与缓存隔离一致）
    sig = build_signature(ctxWork);
catch
end
try
    fprintf('[%s] baseData=%s\n', sectionName, char(string(dataDiag.baseDataPath)));
    drawnow('limitrate');
catch
end

% ===== 1) 定位/读取事件表（通过 helper，避免规范扫描误伤）=====
xlsxPath = '';
try
    if isfield(cfg,'PaperFiles') && isfield(cfg.PaperFiles,'dynamicPath')
        if exist(cfg.PaperFiles.dynamicPath, 'file') == 2
            xlsxPath = cfg.PaperFiles.dynamicPath;
        end
    end
catch
end
if isempty(xlsxPath)
    try
        xlsxPath = find_realtime_events_xlsx_541(ctx.Meta.projectRoot, cfg.PaperFiles.dynamicName);
    catch
        xlsxPath = find_realtime_events_xlsx_541(ctx.Meta.projectRoot);
    end
end
log_append_(logPath, sprintf('[events_xlsx] %s', xlsxPath));
try
    fprintf('[%s] eventsXlsx=%s\n', sectionName, char(string(xlsxPath)));
    drawnow('limitrate');
catch
end
[eventsRaw, recvWindow] = read_realtime_events_541(xlsxPath);

% paper_repro：若缺窗口，使用论文默认 [08:00,10:00]；generalize：用事件推断并对齐到 T
[recvWindow, winNote] = finalize_recv_window_541_(recvWindow, eventsRaw, cfg);
log_append_(logPath, sprintf('[window] recvWindow=[%g,%g] min | note=%s', recvWindow(1), recvWindow(2), winNote));

% 事件表增强（old/new/delta；并不改变求解，只用于追溯与 q 统计）
baseDemandMap = build_base_demand_map_541_(ctxWork);
events = enrich_events_541_(eventsRaw, baseDemandMap);

% 输出 Table5.6（事件解析表）
t56Name = '动态需求信息';
t56Path = fullfile(tblEventsDir, artifact_filename(t56Name, sectionName, modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.xlsx'));
eventsOut = events_table_cn_for_output_541_(events);
t56Path = write_table_xlsx_first_541(eventsOut, t56Path, logPath);
try
    if isfield(cfg,'Output') && isfield(cfg.Output,'printTables') && cfg.Output.printTables
        print_table_cn_541_(eventsOut, sprintf('[%s] Table5.6 动态需求信息', sectionName));
    end
catch
end

% ===== 2) 批处理更新时刻 =====
[uTimes, batches, batchMeta] = build_update_times_541(events, recvWindow, cfg.Dynamic.qKg, cfg.Dynamic.TMin, cfg);
log_append_(logPath, sprintf('[updates] count=%d | qKg=%g | TMin=%g', numel(uTimes), cfg.Dynamic.qKg, cfg.Dynamic.TMin));
try
    fprintf('[%s] recvWindow=[%g,%g]min | updates=%d\n', sectionName, recvWindow(1), recvWindow(2), numel(uTimes));
    for i = 1:numel(uTimes)
        fprintf('[%s] u%d=%s (%gmin) | batchEvents=%d\n', sectionName, i, min_to_hhmm_(uTimes(i)), uTimes(i), height(batches{i}));
    end
catch
end
for i = 1:numel(batchMeta)
    log_append_(logPath, batchMeta{i}.logLine);
    for j = 1:numel(batchMeta{i}.qContribLines)
        log_append_(logPath, ['  ' batchMeta{i}.qContribLines{j}]);
    end
end

% ===== 3) 初始实例（不写回 ctx；用于稳定客户编号与站点编号）=====
instance0 = build_initial_instance_541(ctxWork, events, recvWindow, cfg);

% ===== 4) 初始方案（必须来自 section_531 产物；保持论文“5.3.1 -> 5.4.1”链路）=====
ctxInit = ctxWork;
try
    % paper_repro：541 的可用车队是 5/5，但初始解“已派车辆”来自 5.3.1 的 2CV+2EV；此处只用于加载 531 的初始 4 路，不写回 ctxWork。
    if strcmp(cfg.Mode, 'paper_repro')
        ctxInit.P.Fleet.nCV = ctx.P.Fleet.nCV;
        ctxInit.P.Fleet.nEV = ctx.P.Fleet.nEV;
    end
catch
end
init = load_initial_plan_from_531_541(ctxInit, paths);
try
    if strcmp(cfg.Mode, 'paper_repro')
        log_append_(logPath, sprintf('[paper_repro][init] source=section_531 (ctxInit fleet=CV%d_EV%d)', round(ctxInit.P.Fleet.nCV), round(ctxInit.P.Fleet.nEV)));
    else
        log_append_(logPath, '[init] source=section_531');
    end
catch
end
try
    if strcmp(cfg.Mode, 'paper_repro')
        if ~(isfield(init,'nCV') && isfield(init,'nEV') && round(init.nCV) == 2 && round(init.nEV) == 2)
            error('section_541:initFleetMismatch', 'paper_repro expects init fleet=CV2_EV2 from Table5.7, got CV%g_EV%g', init.nCV, init.nEV);
        end
        if ~(isfield(init,'detail') && numel(init.detail) == 4)
            error('section_541:initPlanSizeMismatch', 'paper_repro expects 4 routes in Table5.7, got %d', numel(init.detail));
        end
    end
catch ME
    log_append_(logPath, sprintf('[paper_repro][init_check] FAILED: %s', ME.message));
    rethrow(ME);
end
% 若 instance0.n 与 ctx.Data.n 不同，则平移“站点节点编号”，避免路线引用错位
init.detail = remap_detail_station_nodes_541(init.detail, ctx.Data.n, instance0.Data.n, ctx.Data.E);
% 推导初始车辆出发时刻：按“到达首客户恰好 LT”回推（不改路线；仅补齐 startTimeMin 以便 Table5.7 时刻可对照）
try
    gInitTmp = build_G_from_instance_541_(ctxWork, instance0, init.nCV, init.nEV);
    for k = 1:numel(init.detail)
        try
            if ~isfield(init.detail(k),'startTimeMin') || ~isfinite(init.detail(k).startTimeMin)
                init.detail(k).startTimeMin = infer_depart_time_from_first_customer_541_(init.detail(k).route, 0, gInitTmp, k);
            end
        catch
            init.detail(k).startTimeMin = 0;
        end
    end
catch
    for k = 1:numel(init.detail)
        try
            if ~isfield(init.detail(k),'startTimeMin') || ~isfinite(init.detail(k).startTimeMin)
                init.detail(k).startTimeMin = 0;
            end
        catch
            init.detail(k).startTimeMin = 0;
        end
    end
end

% paper_repro：对照论文表5.7（仅做差异报告，不覆盖 init）
try
    if strcmp(cfg.Mode, 'paper_repro')
        ref = paper_init_plan_table57_541(instance0.Data.n, instance0.Data.E);
        [okInit, msgInit] = compare_init_plan_to_table57_541_(init, ref);
        if okInit
            log_append_(logPath, sprintf('[paper_repro][init_check] OK: %s', msgInit));
        else
            log_append_(logPath, sprintf('[paper_repro][init_check] MISMATCH: %s', msgInit));
            if ~isempty(alignReportPath)
                log_append_(alignReportPath, sprintf('[paper_repro][init_check] MISMATCH: %s', msgInit));
            end
        end
    end
catch
end

% 自检：初始方案中的客户必须在初始时刻为 active（否则说明 531 方案与 5.4.1 实例口径不一致）
usedCust = [];
usedSt = [];
try
    for k = 1:numel(init.detail)
        r = init.detail(k).route(:);
        usedCust = [usedCust; r(r>=1 & r<=instance0.Data.n)]; %#ok<AGROW>
        usedSt = [usedSt; r(r>=instance0.Data.n+1 & r<=instance0.Data.n+instance0.Data.E)]; %#ok<AGROW>
    end
catch
end
usedCust = unique(usedCust);
if ~isempty(usedCust)
    bad = usedCust(instance0.Data.q(usedCust+1) <= 0);
    if ~isempty(bad)
        error('section_541:initPlanMismatch', 'init plan visits inactive customers: %s (paper_repro: please verify Table5.7 routes vs current data)', mat2str(bad(:).'));
    end
end
if ~isempty(usedSt)
    if any(usedSt < instance0.Data.n+1) || any(usedSt > instance0.Data.n+instance0.Data.E)
        error('section_541:initPlanStationMismatch', 'init plan station node ids out of range after remap');
    end
end

gInit = build_G_from_instance_541_(ctxWork, instance0, init.nCV, init.nEV);
timelineInit = simulate_timeline_541(gInit, init.detail, cfg);
t57 = timeline_table_541_(instance0, timelineInit, init, 'init');
t57Name = '初始配送方案各节点时刻信息';
t57Path = fullfile(tblInitDir, artifact_filename(t57Name, sectionName, modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.xlsx'));
t57Path = write_table_xlsx_first_541(t57, t57Path, logPath);
try
    if isfield(cfg,'Output') && isfield(cfg.Output,'printTables') && cfg.Output.printTables
        print_table_cn_541_(t57, sprintf('[%s] Table5.7 初始配送方案', sectionName));
    end
catch
end

% ===== 5) 动态循环 =====
instancePrev = instance0;

planPrev0 = struct('detail', init.detail, 'nCV', init.nCV, 'nEV', init.nEV, 'fleetTag', sprintf('CV%d_EV%d', init.nCV, init.nEV));
planPrev = planPrev0;
timelinePrev = timelineInit;

% paper_repro：将 2CV+2EV 的初始 4 路映射到论文可用车队 5CV+5EV 的车位上（CV1..CV5, EV1..EV5），保证车型/编号一致
try
    if strcmp(cfg.Mode, 'paper_repro')
        nCVPool = round(ctxWork.P.Fleet.nCV);
        nEVPool = round(ctxWork.P.Fleet.nEV);
        if ~(nCVPool == 5 && nEVPool == 5)
            error('section_541:paperFleetNot5_5', 'paper_repro expects available fleet=CV5_EV5 (paper 5.2), got CV%g_EV%g', ctxWork.P.Fleet.nCV, ctxWork.P.Fleet.nEV);
        end
        planPrev = expand_plan_to_pool_541_(planPrev0, nCVPool, nEVPool);
        gPrevPool = build_G_from_instance_541_(ctxWork, instance0, planPrev.nCV, planPrev.nEV);
        timelinePrev = simulate_timeline_541(gPrevPool, planPrev.detail, cfg);
        log_append_(logPath, sprintf('[paper_repro] expand init plan slots: %s -> %s (keep routes, only pad/shift EV slots)', planPrev0.fleetTag, planPrev.fleetTag));
    end
catch ME
    log_append_(logPath, sprintf('[paper_repro] expand init plan slots failed: %s', ME.message));
    rethrow(ME);
end

costHistory = init_cost_history_541_(timelineInit, init);

iterArtifacts = struct();
cancelFailAll = {};

for ui = 1:numel(uTimes)
    tNow = uTimes(ui);

    stateBefore = build_state_at_time_541(tNow, planPrev, timelinePrev, cfg);
    try
        fprintf('[%s][u%02d] tNow=%s (%gmin)\n', sectionName, ui, min_to_hhmm_(tNow), tNow);
        drawnow('limitrate');
    catch
    end
    try
        fprintf('[%s][u%02d] step=plot_state\n', sectionName, ui);
        drawnow('limitrate');
    catch
    end
    figState = plot_dynamic_state_541(instancePrev, planPrev, timelinePrev, stateBefore, tNow, cfg);
    figStateName = fig_name_state_(ui, numel(uTimes), tNow);
    figStatePath = fullfile(figStateDir, artifact_filename(figStateName, sectionName, modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.png'));
    export_figure(figState, figStatePath, 300, struct('exportNoAxisLabels', true));

    try
        fprintf('[%s][u%02d] step=apply_events\n', sectionName, ui);
        drawnow('limitrate');
    catch
    end
    [instanceNow, cancelFailList, batchInfo] = apply_event_batch_541(instancePrev, stateBefore, batches{ui}, tNow, cfg);
    for k = 1:numel(cancelFailList)
        cancelFailAll{end+1,1} = cancelFailList{k}; %#ok<AGROW>
    end
    log_append_(logPath, sprintf('[u%d] tNow=%s | batch=%d events | cancelFail=%d', ui, min_to_hhmm_(tNow), height(batches{ui}), numel(cancelFailList)));
    try
        fprintf('[%s][u%02d] batchEvents=%d | cancelFail=%d\n', sectionName, ui, height(batches{ui}), numel(cancelFailList));
        drawnow('limitrate');
    catch
    end
    if ~isempty(batchInfo)
        for bi = 1:numel(batchInfo)
            log_append_(logPath, ['  ' batchInfo{bi}]);
        end
    end

    % ===== 需求压力审计（apply_events 后、solve 前）=====
    try
        pressLines = demand_pressure_audit_541_(ctxWork, instancePrev, instanceNow, stateBefore, batches{ui}, cfg);
        for pi = 1:numel(pressLines)
            log_append_(logPath, pressLines{pi});
        end
    catch
    end

    try
        fprintf('[%s][u%02d] step=solve\n', sectionName, ui);
        drawnow('limitrate');
    catch
    end
    cfgSolve = cfg;
    try
        if strcmp(cfg.Mode, 'paper_repro')
            [needExtraEV, reason] = demand_driven_extra_ev_541_(ctxWork, instanceNow, stateBefore);
            if needExtraEV
                % paper_repro：车队池已固定为 5/5（论文 5.2），此处仅做审计提示，不通过“扩池”绕过论文上界
                log_append_(logPath, sprintf('[u%d][extra_ev_check] %s', ui, reason));
                try fprintf('[%s][u%02d] extra_ev_check: %s\n', sectionName, ui, reason); catch, end
            end
        end
    catch
    end
    [planNow, solveInfo] = solve_snapshot_svrp_541(ctxWork, instanceNow, stateBefore, cfgSolve, planPrev);
    gNow = build_G_from_instance_541_(ctxWork, instanceNow, planNow.nCV, planNow.nEV);
    timelineNow = simulate_timeline_541(gNow, planNow.detail, cfgSolve);
    try
        fprintf('[%s][u%02d] fleet=%s | totalCost=%.3f | dist=%.1fkm | nCharge=%d | vioTw=%d vioBat=%d\n', ...
            sectionName, ui, planNow.fleetTag, timelineNow.summary.totalCost, timelineNow.summary.distanceKm, ...
            timelineNow.summary.nCharge, timelineNow.summary.vioTw, timelineNow.summary.vioBat);
        drawnow('limitrate');
    catch
    end

    try
        fprintf('[%s][u%02d] step=export_and_tables\n', sectionName, ui);
        drawnow('limitrate');
    catch
    end
    figPlan = plot_dynamic_plan_541(instanceNow, planNow, timelineNow, tNow, cfg);
    figPlanName = fig_name_plan_(ui, numel(uTimes), tNow);
    figPlanPath = fullfile(figPlanDir, artifact_filename(figPlanName, sectionName, modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.png'));
    export_figure(figPlan, figPlanPath, 300, struct('exportNoAxisLabels', true));

    [tblPlan, tblCost, costHistory] = build_tables_541(instanceNow, planNow, timelineNow, tNow, cfgSolve, costHistory);
    [tblPlanName, tblCostName] = table_names_update_(ui, numel(uTimes), tNow);
    tblPlanPath = fullfile(tblPlanDir, artifact_filename(tblPlanName, sectionName, modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.xlsx'));
    tblCostPath = fullfile(tblCostDir, artifact_filename(tblCostName, sectionName, modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.xlsx'));
    tblPlanPath = write_table_xlsx_first_541(tblPlan, tblPlanPath, logPath);
    tblCostPath = write_table_xlsx_first_541(tblCost, tblCostPath, logPath);
    try
        if isfield(cfg,'Output') && isfield(cfg.Output,'printTables') && cfg.Output.printTables
            print_table_cn_541_(tblPlan, sprintf('[%s][u%02d] 优化方案表', sectionName, ui));
            print_table_cn_541_(tblCost, sprintf('[%s][u%02d] 成本对比表（累计）', sectionName, ui));
        end
    catch
    end

    iterMat = struct();
    iterMat.tNow = tNow;
    iterMat.batch = batches{ui};
    iterMat.stateBefore = stateBefore;
    iterMat.instanceNow = instanceNow;
    iterMat.planNow = planNow;
    iterMat.timelineNow = timelineNow;
    iterMat.costHistory = costHistory;
    iterMat.cancelFailList = cancelFailList;
    iterMat.solveInfo = solveInfo;
    iterMat.cfg = cfgSolve;
    iterMat.sig = sig;
    iterMat.ctxSigBefore = ctxSigBefore;
    iterMat.keyCfgBefore = keyCfgBefore;
    iterMat.batchReason = batchMeta{ui};

    matName = sprintf('u%02d_state_plan', ui);
    matPath = fullfile(paths.mats, artifact_filename(matName, sectionName, modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.mat'));
    save(matPath, '-struct', 'iterMat');
    try
        fprintf('[%s][u%02d] done\n', sectionName, ui);
        drawnow('limitrate');
    catch
    end

    iterArtifacts.(sprintf('u%02d_fig_state', ui)) = figStatePath;
    iterArtifacts.(sprintf('u%02d_fig_plan', ui)) = figPlanPath;
    iterArtifacts.(sprintf('u%02d_table_plan', ui)) = tblPlanPath;
    iterArtifacts.(sprintf('u%02d_table_cost', ui)) = tblCostPath;
    iterArtifacts.(sprintf('u%02d_mat', ui)) = matPath;

    instancePrev = instanceNow;
    planPrev = planNow;
    timelinePrev = timelineNow;
end

% ===== 5) 对齐/自检报告（只报告不改结果）=====
validate_alignment_541(paths, cfg, events, recvWindow, uTimes, iterArtifacts, cancelFailAll, alignReportPath);
% 额外生成稳定文件名（追加写，避免覆盖）：outputs/section_541/logs/align_report.txt
append_to_stable_log_541_(fullfile(paths.logs, 'align_report.txt'), alignReportPath, ctx.Meta.timestamp);

% ===== 6) ctx guard 收尾（硬失败）=====
ctxSigAfter = build_signature(ctx);
keyCfgAfter = guard_snapshot_541_(ctx);
guardAfterPath = fullfile(paths.mats, artifact_filename('guard_after', sectionName, 'guard', sig.param.short, sig.data.short, ctx.Meta.timestamp, '.mat'));
save(guardAfterPath, 'ctxSigAfter', 'keyCfgAfter');

guard_check_or_error_(ctxSigBefore, ctxSigAfter, keyCfgBefore, keyCfgAfter, guardReportPath);

% ===== 7) RNG 恢复与硬校验 =====
rng(rngStateBefore);
rngStateAfterRestore = rng; %#ok<NASGU>
rngAfterPath = fullfile(paths.mats, artifact_filename('rng_after_restore', sectionName, 'guard', sig.param.short, sig.data.short, ctx.Meta.timestamp, '.mat'));
save(rngAfterPath, 'rngStateAfterRestore');
rng_guard_check_or_error_(rngStateBefore, rngStateAfterRestore, rngGuardReportPath);

out = struct();
out.meta = struct('sectionName', sectionName, 'modeTag', modeTag, 'runTag', ctx.Meta.runTag, ...
    'timestamp', ctx.Meta.timestamp, 'paramSig', sig.param, 'dataSig', sig.data, 'cfg', cfg);
out.meta.features = {'dynamic','dvrp'};
try
    out.meta.baseData = dataDiag;
    out.meta.eventsXlsx = xlsxPath;
    try out.meta.paperFiles = cfg.PaperFiles; catch, end
    out.meta.dataFallback = logical(dataDiag.dataFallback);
    if out.meta.dataFallback
        out.meta.features{end+1} = 'dataFallback';
    end
catch
end
out.paths = paths;
out.artifacts = struct();
out.artifacts.eventsTable = t56Path;
out.artifacts.initPlanTable = t57Path;
out.artifacts.log = logPath;
out.artifacts.alignReport = alignReportPath;
out.artifacts.guardBefore = guardBeforePath;
out.artifacts.guardAfter = guardAfterPath;
out.artifacts.rngBefore = rngBeforePath;
out.artifacts.rngAfterRestore = rngAfterPath;

fns = fieldnames(iterArtifacts);
for i = 1:numel(fns)
    out.artifacts.(fns{i}) = iterArtifacts.(fns{i});
end
end

% ========================= local helpers =========================
function cfg = default_cfg_541_(ctx)
cfg = struct();

% ===================== 541 开关面板（仅影响 section_541；不写回 ctx） =====================
% paper_repro（默认，论文 5.4.1 示例复现口径）：
% - q=500kg，T=30min
% - 若事件表未给窗口：默认接收窗口 [08:00,10:00]（480~600min）
% - q 累计口径：默认 positive_only（仅累计新增 + 正向变更增量；取消/减少不做净额抵消）
% - 固定 RNG seed（写入日志/out.meta），启用 warm-start
% - 候选车队枚举范围更小（更稳定复现论文结构）
%
% generalize（更宽松，更解释化；不反向影响 paper_repro 的可复现性与产物结构）：
% - 窗口/触发可由事件表驱动；允许用户改 q/T/seed/qAccum（仍需有限上界避免无限加车）
%
% 环境变量（generalize 下允许覆盖；两种模式均读取 snapshot/console 开关）：
% - SECTION541_MODE=paper_repro|generalize
% - SECTION541_QKG=500                 % 定量触发阈值（kg）
% - SECTION541_TMIN=30                 % 定时触发周期（min）
% - SECTION541_SEED=1|shuffle          % RNG：整数或 shuffle
% - SECTION541_QACCUM=positive_only|net
% - SECTION541_WINDOW=08:00-10:00      % 接收窗口覆盖（空则由文件/事件推断）
% - SECTION541_MAX_EXTRAEV=4           % 额外 EV 上界（有限枚举）
% - SECTION541_MAX_EXTRACV=2           % 额外 CV 上界（有限枚举）
% - SECTION541_CONSOLE_VERBOSE=true    % 两种模式均读取：控制台详细输出 true/false（候选车队/压力审计）
% - SECTION541_PARALLEL_ENABLE=true    % 两种模式均读取：GSAA 的 NRun 是否并行执行（仅加速，不改参数/语义）
% - SECTION541_PARALLEL_WORKERS=0      % 并行 worker 数：0=自动；>0=指定上限
% - SECTION541_PAPER_STATIC_XLSX=论文示例静态节点数据.xlsx
% - SECTION541_PAPER_EVENTS_XLSX=论文示例动态需求数据.xlsx
% - SECTION541_KEEP_FIGURES=true       % 是否保持图窗不自动关闭
% - SECTION541_PRINT_TABLES=true       % 是否在终端打印表格内容
% =====================================================================

cfg.Mode = 'paper_repro'; % 'paper_repro' | 'generalize'
try
    v = getenv('SECTION541_MODE');
    v = lower(strtrim(char(string(v))));
    if any(strcmp(v, {'paper_repro','generalize'}))
        cfg.Mode = v;
    end
catch
end

cfg.DataPolicy = 'prefer_data'; % prefer_data(默认：论文示例 xlsx) | prefer_internal(仅显式指定才允许内置数据)
try
    v = getenv('SECTION541_DATA_POLICY');
    v = lower(strtrim(char(string(v))));
    if any(strcmp(v, {'prefer_data','prefer_internal'}))
        cfg.DataPolicy = v;
    end
catch
end

cfg.Validate = struct();
cfg.Validate.enable = true; % 是否启用对齐/产物完整性报告（仅报告不改结果）；两种模式默认均开启
try
    v = getenv('SECTION541_VALIDATE_ENABLE');
    v = lower(strtrim(char(string(v))));
    if any(strcmp(v, {'0','false','off','no'}))
        cfg.Validate.enable = false;
    elseif any(strcmp(v, {'1','true','on','yes'}))
        cfg.Validate.enable = true;
    end
catch
end

cfg.PaperFiles = struct();
cfg.PaperFiles.staticName = '论文示例静态节点数据.xlsx';
cfg.PaperFiles.dynamicName = '论文示例动态需求数据.xlsx';
try
    v = getenv('SECTION541_PAPER_STATIC_XLSX');
    v = strtrim(char(string(v)));
    if ~isempty(v), cfg.PaperFiles.staticName = v; end
catch
end
try
    v = getenv('SECTION541_PAPER_EVENTS_XLSX');
    v = strtrim(char(string(v)));
    if ~isempty(v), cfg.PaperFiles.dynamicName = v; end
catch
end

cfg.Dynamic = struct();
cfg.Dynamic.qKg = 500;                      % 定量触发阈值 q（kg）；paper_repro 固定=500；generalize 允许覆盖
cfg.Dynamic.TMin = 30;                      % 定时触发周期 T（min）；paper_repro 固定=30；generalize 允许覆盖
cfg.Dynamic.qAccumPolicy = 'positive_only'; % q 累计口径：positive_only(默认，论文示例) | net
% - positive_only：仅累计新增 + 正向变更增量；取消/减少不计入 q（不做净额抵消）
% - net：累计净变化（可能被取消/减少抵消）
cfg.Dynamic.windowOverride = [];            % 强制接收窗口覆盖 [t0,tEnd] (min)；默认空（使用“文件窗口/默认窗口/推断窗口”）
cfg.Dynamic.defaultRecvWindow = '08:00-10:00';  % paper_repro 默认接收窗口（仅当事件表未显式给窗口）
try
    v = getenv('SECTION541_DEFAULT_RECV_WINDOW');
    v = strtrim(char(string(v)));
    if ~isempty(v)
        cfg.Dynamic.defaultRecvWindow = v;
    end
catch
end

cfg.Solver = struct();
cfg.Solver.seed = 1;                        % RNG 种子：paper_repro 固定；generalize 默认仍固定但允许覆盖/或 shuffle
cfg.Solver.warmStart = true;                % warm-start：将上一轮未服务序列映射为本轮初始分配（仅影响初始解，不改模型参数）
cfg.Solver.parallelEnable = false;          % GSAA 的 NRun 并行开关（仅加速，不改参数/语义）
cfg.Solver.parallelWorkers = 0;             % 并行 worker 数：0=自动；>0=指定上限
cfg.Solver.parallelLogLevel = 'detailed';   % 并行顺序日志级别：none | summary | detailed
try
    v = getenv('SECTION541_WARMSTART');
    v = lower(strtrim(char(string(v))));
    if any(strcmp(v, {'0','false','off','no'}))
        cfg.Solver.warmStart = false;
    elseif any(strcmp(v, {'1','true','on','yes'}))
        cfg.Solver.warmStart = true;
    end
catch
end
cfg.Solver.cacheEnable = false;             % 缓存开关（默认关闭；若启用需以 build_signature 隔离）
try
    v = getenv('SECTION541_CACHE_ENABLE');
    v = lower(strtrim(char(string(v))));
    if any(strcmp(v, {'1','true','on','yes'}))
        cfg.Solver.cacheEnable = true;
    elseif any(strcmp(v, {'0','false','off','no'}))
        cfg.Solver.cacheEnable = false;
    end
catch
end
cfg.Solver.nRun = 1;                        % 仅用于日志展示；实际 NRun 统一使用 ctx.SolverCfg.NRun
try
    cfg.Solver.nRun = round(ctx.SolverCfg.NRun);
catch
end
if ~isfinite(cfg.Solver.nRun) || cfg.Solver.nRun < 1
    cfg.Solver.nRun = 1;
end
try
    v = getenv('SECTION541_PARALLEL_ENABLE');
    v = lower(strtrim(char(string(v))));
    if any(strcmp(v, {'1','true','on','yes'}))
        cfg.Solver.parallelEnable = true;
    elseif any(strcmp(v, {'0','false','off','no'}))
        cfg.Solver.parallelEnable = false;
    end
catch
end
try
    v = getenv('SECTION541_PARALLEL_WORKERS');
    v = strtrim(char(string(v)));
    if ~isempty(v)
        w = str2double(v);
        if isfinite(w) && w >= 0
            cfg.Solver.parallelWorkers = round(w);
        end
    end
catch
end
try
    v = getenv('SECTION541_PARALLEL_LOG_LEVEL');
    v = strtrim(char(string(v)));
    if ~isempty(v)
        cfg.Solver.parallelLogLevel = v;
    end
catch
end
cfg.Solver.parallelLogLevel = normalize_parallel_log_level_541_(cfg.Solver.parallelLogLevel);

cfg.Log = struct();
cfg.Log.printToConsole = true;              % 控制台是否打印候选审计/压力审计（由 run_modes 的 SECTION541_CONSOLE_VERBOSE 控制）
try
    v = getenv('SECTION541_CONSOLE_VERBOSE');
    v = lower(strtrim(char(string(v))));
    if any(strcmp(v, {'0','false','off','no'}))
        cfg.Log.printToConsole = false;
    elseif any(strcmp(v, {'1','true','on','yes'}))
        cfg.Log.printToConsole = true;
    end
catch
end
cfg.Output = struct();
cfg.Output.keepFigures = true;
cfg.Output.printTables = true;
try
    v = getenv('SECTION541_KEEP_FIGURES');
    v = lower(strtrim(char(string(v))));
    if any(strcmp(v, {'0','false','off','no'}))
        cfg.Output.keepFigures = false;
    elseif any(strcmp(v, {'1','true','on','yes'}))
        cfg.Output.keepFigures = true;
    end
catch
end
try
    v = getenv('SECTION541_PRINT_TABLES');
    v = lower(strtrim(char(string(v))));
    if any(strcmp(v, {'0','false','off','no'}))
        cfg.Output.printTables = false;
    elseif any(strcmp(v, {'1','true','on','yes'}))
        cfg.Output.printTables = true;
    end
catch
end
    cfg.CandidateFleet = struct();
    % paper_repro：车队池固定为论文可用车队上界（5CV+5EV），不允许超出；是否“派车”由 GSAA/可行性自然决定
    cfg.CandidateFleet.maxExtraEV = 0;
    cfg.CandidateFleet.maxExtraCV = 0;
if strcmp(cfg.Mode, 'generalize')
    % generalize 允许扩大（仍有限上界）
    cfg.CandidateFleet.maxExtraEV = 4;
    cfg.CandidateFleet.maxExtraCV = 2;
    try
        qv = getenv('SECTION541_QKG');
        tv = getenv('SECTION541_TMIN');
        if ~isempty(qv), cfg.Dynamic.qKg = str2double(qv); end
        if ~isempty(tv), cfg.Dynamic.TMin = str2double(tv); end
    catch
    end
    try
        seedv = getenv('SECTION541_SEED');
        seedv = strtrim(char(string(seedv)));
        if ~isempty(seedv)
            if strcmpi(seedv, 'shuffle')
                cfg.Solver.seed = 'shuffle';
            else
                s = str2double(seedv);
                if isfinite(s)
                    cfg.Solver.seed = round(s);
                end
            end
        end
    catch
    end
    try
        ap = getenv('SECTION541_QACCUM');
        ap = lower(strtrim(char(string(ap))));
        if any(strcmp(ap, {'positive_only','net'}))
            cfg.Dynamic.qAccumPolicy = ap;
        end
    catch
    end
    try
        wv = getenv('SECTION541_WINDOW');
        wv = strtrim(char(string(wv)));
        if ~isempty(wv)
            win = parse_window_to_min_541(wv);
            if ~isempty(win) && numel(win) == 2 && all(isfinite(win))
                cfg.Dynamic.windowOverride = win(:).';
            end
        end
    catch
    end
    try
        mev = getenv('SECTION541_MAX_EXTRAEV');
        mcv = getenv('SECTION541_MAX_EXTRACV');
        if ~isempty(mev)
            v = str2double(mev);
            if isfinite(v) && v >= 0
                cfg.CandidateFleet.maxExtraEV = round(v);
            end
        end
        if ~isempty(mcv)
            v = str2double(mcv);
            if isfinite(v) && v >= 0
                cfg.CandidateFleet.maxExtraCV = round(v);
            end
        end
    catch
    end
end

cfg.Cache = struct();
cfg.Cache.enable = false; % 默认关闭；若未来启用：仅允许落盘到 outputs/section_541/cache 且以 build_signature(ctx) 隔离；禁止 persistent/global

cfg.Paper = struct();
cfg.Paper.defaultRecvWindowMin = [480 600]; % paper_repro 默认接收窗口 08:00-10:00（仅当事件表未显式给窗口）

% 基本自检：不依赖猜测，直接暴露
assert(isfield(ctx,'P') && isfield(ctx,'Data') && isfield(ctx,'Meta'));
assert(isfield(ctx.Meta,'projectRoot') && isfield(ctx.Meta,'runTag') && isfield(ctx.Meta,'timestamp'));
end

function cfg = rng_setup_541_(cfg, logPath)
if strcmp(cfg.Mode, 'paper_repro')
    rng(cfg.Solver.seed, 'twister');
    log_append_(logPath, sprintf('[rng] mode=%s | seed=%g | alg=twister', cfg.Mode, cfg.Solver.seed));
    return;
end
if ischar(cfg.Solver.seed) && strcmpi(cfg.Solver.seed, 'shuffle')
    rng('shuffle');
    st = rng;
    log_append_(logPath, sprintf('[rng] mode=%s | seed=shuffle | actualSeed=%g | alg=%s', cfg.Mode, st.Seed, st.Type));
else
    rng(cfg.Solver.seed, 'twister');
    log_append_(logPath, sprintf('[rng] mode=%s | seed=%g | alg=twister', cfg.Mode, cfg.Solver.seed));
end
end

function keyCfg = guard_snapshot_541_(ctx)
keyCfg = struct();

% Solver
try keyCfg.SolverCfg = ctx.SolverCfg; catch, keyCfg.SolverCfg = struct(); end

% P (关键模型参数快照：不深拷贝大对象)
keyCfg.P = struct();
try keyCfg.P.Fleet = ctx.P.Fleet; catch, end
try keyCfg.P.EV = ctx.P.EV; catch, end
try keyCfg.P.Price = ctx.P.Price; catch, end
try keyCfg.P.Model = ctx.P.Model; catch, end
try
    if isfield(ctx.P,'CMEM'), keyCfg.P.CMEM = ctx.P.CMEM; end
catch
end

% Data（仅存尺寸与哈希，避免大对象）
keyCfg.Data = struct();
try
    keyCfg.Data.n = ctx.Data.n;
    keyCfg.Data.E = ctx.Data.E;
    keyCfg.Data.ST = ctx.Data.ST;
    keyCfg.Data.sz_coord = size(ctx.Data.coord);
    keyCfg.Data.sz_q = size(ctx.Data.q);
    keyCfg.Data.sz_LT = size(ctx.Data.LT);
    keyCfg.Data.sz_RT = size(ctx.Data.RT);
    keyCfg.Data.hash = md5_json_short_(struct( ...
        'coord', ctx.Data.coord, 'q', ctx.Data.q, 'LT', ctx.Data.LT, 'RT', ctx.Data.RT, 'n', ctx.Data.n, 'E', ctx.Data.E, 'ST', ctx.Data.ST));
catch
end
end

function [recvWindow, note] = finalize_recv_window_541_(recvWindow, events, cfg)
note = '';
if ~isempty(cfg.Dynamic.windowOverride) && numel(cfg.Dynamic.windowOverride) == 2
    recvWindow = cfg.Dynamic.windowOverride(:).';
    note = 'cfg.Dynamic.windowOverride';
    return;
end
if isnumeric(recvWindow) && numel(recvWindow) == 2 && all(isfinite(recvWindow))
    recvWindow = recvWindow(:).';
    note = 'from_file';
    return;
end
if strcmp(cfg.Mode, 'paper_repro')
    recvWindow = cfg.Paper.defaultRecvWindowMin;
    note = 'paper_default';
    return;
end
% generalize：用事件 min/max 推断并按 T 对齐
t = events.tAppearMin;
t = t(isfinite(t));
if isempty(t)
    recvWindow = cfg.Paper.defaultRecvWindowMin;
    note = 'fallback_default_no_events';
    return;
end
t0 = floor(min(t) / cfg.Dynamic.TMin) * cfg.Dynamic.TMin;
tEnd = ceil(max(t) / cfg.Dynamic.TMin) * cfg.Dynamic.TMin;
recvWindow = [t0 tEnd];
note = 'inferred_from_events';
end

function baseDemandMap = build_base_demand_map_541_(ctx)
baseDemandMap = containers.Map('KeyType','double','ValueType','double');
try
    for i = 1:ctx.Data.n
        baseDemandMap(i) = double(ctx.Data.q(i+1));
    end
catch
end
end

function events = enrich_events_541_(eventsRaw, baseDemandMap)
events = eventsRaw;
if ~ismember('oldDemandKg', events.Properties.VariableNames)
    events.oldDemandKg = NaN(height(events),1);
end
if ~ismember('newDemandKg', events.Properties.VariableNames)
    events.newDemandKg = NaN(height(events),1);
end
if ~ismember('deltaDemandKg', events.Properties.VariableNames)
    events.deltaDemandKg = NaN(height(events),1);
end

curDem = baseDemandMap;
[~, order] = sort(events.tAppearMin);
for ii = 1:numel(order)
    r = order(ii);
    cid = events.customerId(r);
    typ = lower(char(string(events.eventType(r))));
    if isnan(cid)
        continue;
    end
    if ~isKey(curDem, cid)
        curDem(cid) = NaN;
    end
    oldv = curDem(cid);
    newv = events.newDemandKg(r);

    events.oldDemandKg(r) = oldv;
    if strcmp(typ, 'cancel')
        events.newDemandKg(r) = 0;
        events.deltaDemandKg(r) = -oldv;
        curDem(cid) = 0;
    elseif strcmp(typ, 'add') || strcmp(typ, 'update')
        if ~isfinite(newv)
            events.deltaDemandKg(r) = NaN;
        else
            events.deltaDemandKg(r) = newv - oldv;
        end
        curDem(cid) = newv;
    else
        events.deltaDemandKg(r) = NaN;
    end
end
end

function guard_check_or_error_(sigBefore, sigAfter, keyBefore, keyAfter, reportPath)
diffs = {};
if ~strcmp(sigBefore.param.full, sigAfter.param.full) || ~strcmp(sigBefore.data.full, sigAfter.data.full)
    diffs{end+1,1} = 'build_signature(ctx) changed'; %#ok<AGROW>
end
diffs = [diffs; struct_diff_lines_(keyBefore, keyAfter, '')]; %#ok<AGROW>
if ~isempty(diffs)
    log_append_(reportPath, '[guard] FAILED: ctx/keyCfg changed (禁止修改 ctx/全局参数)');
    for i = 1:numel(diffs)
        log_append_(reportPath, ['  - ' diffs{i}]);
    end
    error('section_541:ctxGuardFailed', 'ctx guard failed: 禁止修改 ctx/全局参数（详见 guard_report）');
end
log_append_(reportPath, '[guard] OK: ctx/keyCfg unchanged');
end

function rng_guard_check_or_error_(rngBefore, rngAfter, reportPath)
ok = false;
try
    ok = isequaln(rngBefore, rngAfter);
catch
    ok = false;
end
if ~ok
    log_append_(reportPath, '[rng_guard] FAILED: RNG state not restored');
    log_append_(reportPath, sprintf('  before: Type=%s Seed=%g', rngBefore.Type, rngBefore.Seed));
    log_append_(reportPath, sprintf('  after : Type=%s Seed=%g', rngAfter.Type, rngAfter.Seed));
    error('section_541:rngGuardFailed', 'RNG guard failed: RNG 状态未恢复（详见 rng_guard_report）');
end
log_append_(reportPath, '[rng_guard] OK: RNG restored');
end

function linesOut = struct_diff_lines_(a, b, prefix)
linesOut = {};
if ~isstruct(a) || ~isstruct(b)
    if ~isequaln(a, b)
        linesOut{end+1,1} = sprintf('%s: value changed', prefix); %#ok<AGROW>
    end
    return;
end
fa = fieldnames(a);
fb = fieldnames(b);
allf = unique([fa; fb]);
for i = 1:numel(allf)
    f = allf{i};
    p = f;
    if ~isempty(prefix)
        p = [prefix '.' f];
    end
    ha = isfield(a, f);
    hb = isfield(b, f);
    if ~ha || ~hb
        linesOut{end+1,1} = sprintf('%s: field missing', p); %#ok<AGROW>
        continue;
    end
    va = a.(f);
    vb = b.(f);
    if isstruct(va) && isstruct(vb)
        sub = struct_diff_lines_(va, vb, p);
        if ~isempty(sub)
            linesOut = [linesOut; sub]; %#ok<AGROW>
        end
    else
        if ~isequaln(va, vb)
            linesOut{end+1,1} = sprintf('%s: value changed', p); %#ok<AGROW>
        end
    end
end
end

function txt = md5_json_short_(s)
try
    js = jsonencode(s);
    bytes = unicode2native(js, 'UTF-8');
    md = java.security.MessageDigest.getInstance('MD5');
    md.update(uint8(bytes));
    raw = typecast(md.digest(), 'uint8');
    hex = lower(reshape(dec2hex(raw, 2).', 1, []));
    txt = hex(1:8);
catch
    txt = 'nohash';
end
end

function log_append_(filePath, line)
ensure_dir(fileparts(filePath));
fid = fopen(filePath, 'a');
if fid < 0
    return;
end
c = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', char(string(line)));
end

function append_to_stable_log_541_(stablePath, srcPath, ts)
if nargin < 1 || isempty(stablePath) || nargin < 2 || isempty(srcPath)
    return;
end
if exist(srcPath, 'file') ~= 2
    return;
end
txt = '';
try
    txt = fileread(srcPath);
catch
    return;
end
if isempty(txt)
    return;
end
ensure_dir(fileparts(stablePath));
fid = fopen(stablePath, 'a');
if fid < 0
    return;
end
c = onCleanup(@() fclose(fid));
fprintf(fid, '==== align_report (%s) src=%s ====\n', char(string(ts)), char(string(srcPath)));
fprintf(fid, '%s\n', txt);
fprintf(fid, '==== end ====\n\n');
end

function s = min_to_hhmm_(tMin)
try
    h = floor(tMin/60);
    m = round(tMin - 60*h);
    s = sprintf('%02d:%02d', h, m);
catch
    s = sprintf('%gmin', tMin);
end
end

function print_table_cn_541_(tbl, titleLine)
if nargin < 2, titleLine = ''; end
try
    if ~isempty(titleLine)
        fprintf('%s\n', char(string(titleLine)));
    end
catch
end
if isempty(tbl)
    fprintf('(empty)\n');
    return;
end
if istable(tbl)
    header = tbl.Properties.VariableNames;
    data = table2cell(tbl);
    tbl = [header; data];
end
if ~iscell(tbl)
    try
        fprintf('%s\n', char(string(tbl)));
    catch
        disp(tbl);
    end
    return;
end
for r = 1:size(tbl,1)
    row = tbl(r,:);
    line = join_row_541_(row);
    fprintf('%s\n', line);
end
end

function line = join_row_541_(row)
parts = cell(1, numel(row));
for c = 1:numel(row)
    parts{c} = format_cell_541_(row{c});
end
try
    line = strjoin(parts, ' | ');
catch
    line = '';
    for c = 1:numel(parts)
        if c == 1
            line = parts{c};
        else
            line = [line ' | ' parts{c}]; %#ok<AGROW>
        end
    end
end
end

function s = format_cell_541_(v)
s = '';
if isstring(v)
    v = char(v);
end
if ischar(v)
    s = v;
    return;
end
if isnumeric(v)
    if isempty(v)
        s = '';
        return;
    end
    if isscalar(v)
        if isnan(v)
            s = 'NaN';
        elseif isinf(v)
            if v > 0, s = 'Inf'; else, s = '-Inf'; end
        else
            if abs(v - round(v)) < 1e-9
                s = sprintf('%.0f', v);
            else
                s = sprintf('%.2f', v);
            end
        end
    else
        parts = cell(1, numel(v));
        for i = 1:numel(v)
            parts{i} = format_cell_541_(v(i));
        end
        s = strjoin(parts, ',');
    end
    return;
end
try
    s = char(string(v));
catch
    s = '';
end
end

function hist = init_cost_history_541_(timelineInit, init)
%#ok<INUSD>
c = summary_cost_local_541_(timelineInit, init);
hist = struct('label', '初始路径', ...
    'startCost', c.startCost, ...
    'driveCost', c.driveCost, ...
    'fuelCost', c.fuelCost, ...
    'elecCost', c.elecCost, ...
    'carbonCost', c.carbonCost, ...
    'totalCost', c.totalCost);
end

function s = summary_cost_local_541_(timelineNow, planNow)
s = struct('startCost',NaN,'driveCost',NaN,'fuelCost',NaN,'elecCost',NaN,'carbonCost',NaN,'totalCost',NaN);
try
    if isfield(timelineNow,'summary')
        s.startCost = timelineNow.summary.startCost;
        s.driveCost = timelineNow.summary.driveCost;
        s.fuelCost = timelineNow.summary.fuelCost;
        s.elecCost = timelineNow.summary.elecCost;
        s.carbonCost = timelineNow.summary.carbonCost;
        s.totalCost = timelineNow.summary.totalCost;
        return;
    end
catch
end
try
    d = planNow.detail;
    s.startCost = sum([d.startCost]);
    s.driveCost = sum([d.driveCost]);
    s.fuelCost = sum([d.fuelCost]);
    s.elecCost = sum([d.elecCost]);
    s.carbonCost = sum([d.carbonCost]);
    s.totalCost = sum([d.totalCost]);
catch
end
end

function name = fig_name_state_(ui, m, tNow)
if nargin < 3 || isempty(tNow) || ~isfinite(tNow)
    tStr = '';
else
    try
        tStr = min_to_hhmm_(tNow);
    catch
        tStr = '';
    end
end
if ~isempty(tStr)
    name = sprintf('时刻 %s 配送状态', tStr);
    return;
end
if m == 4 && ui <= 4
    name = sprintf('配送状态_u%02d', ui);
    return;
end
name = sprintf('配送状态_u%02d', ui);
end

function name = fig_name_plan_(ui, m, tNow)
if nargin < 3 || isempty(tNow) || ~isfinite(tNow)
    tStr = '';
else
    try
        tStr = min_to_hhmm_(tNow);
    catch
        tStr = '';
    end
end
if ~isempty(tStr)
    name = sprintf('时刻 %s 优化路线', tStr);
    return;
end
if m == 4 && ui <= 4
    name = sprintf('优化路线_u%02d', ui);
    return;
end
name = sprintf('优化路线_u%02d', ui);
end

function [planName, costName] = table_names_update_(ui, m, tNow)
if nargin < 3 || isempty(tNow) || ~isfinite(tNow)
    tStr = '';
else
    try
        tStr = min_to_hhmm_(tNow);
    catch
        tStr = '';
    end
end
if m == 4 && ui <= 4 && ~isempty(tStr)
    planName = sprintf('时刻 %s 优化方案', tStr);
    costName = sprintf('时刻 %s 各项成本对比', tStr);
    return;
end
if ~isempty(tStr)
    planName = sprintf('时刻 %s 优化方案', tStr);
    costName = sprintf('时刻 %s 各项成本对比', tStr);
else
    planName = sprintf('优化方案_u%02d', ui);
    costName = sprintf('各项成本对比_u%02d', ui);
end
end

function g = build_G_from_instance_541_(ctx, instance, nCV, nEV)
ctxLocal = ctx;
ctxLocal.Data = instance.Data;
g = build_G_from_ctx(ctxLocal, 'nCV', nCV, 'nEV', nEV, 'AllowCharging', true, 'ForceChargeOnce', false, 'ForceChargePolicy', 'ANY_EV');
end

function t = timeline_table_541_(instance, timeline, plan, tag)
%#ok<INUSD>
n = instance.Data.n;
E = instance.Data.E;
header = {'路径','节点和时间信息'};
rows = {};

veh = timeline.vehicles;
names = strings(numel(veh),1);
for k = 1:numel(veh)
    names(k) = string(veh(k).name);
end
order = vehicle_order_local_541_(names);

pathIdx = 0;
for oi = 1:numel(order)
    k = order(oi);
    v = veh(k);
    if ~isfield(v,'route') || numel(v.route) < 2
        continue;
    end
    pathIdx = pathIdx + 1;
    pathName = sprintf('路径%d\n(%s)', pathIdx, v.name);
    [nodeStr, timeStr] = route_strings_local_541_(v, n, E);
    nodeTime = sprintf('%s\n%s', nodeStr, timeStr);
    rows(end+1,:) = {pathName, nodeTime}; %#ok<AGROW>
end
t = [header; rows];
end

function tOut = events_table_cn_for_output_541_(events)
header = {'ID','需求类型','X','Y','需求(kg)','时间窗','更新时间','旧需求(kg)','新需求(kg)','变更量(kg)'};
if isempty(events)
    tOut = header;
    return;
end
n = height(events);
rows = cell(n, numel(header));
for i = 1:n
    cid = safe_num_(events, 'customerId', i);
    x = safe_num_(events, 'x', i);
    y = safe_num_(events, 'y', i);
    newq = safe_num_(events, 'newDemandKg', i);
    oldq = safe_num_(events, 'oldDemandKg', i);
    delta = safe_num_(events, 'deltaDemandKg', i);
    tStr = '';
    try tStr = min_to_hhmm_(events.tAppearMin(i)); catch, tStr = ''; end
    winStr = window_str_541_(safe_num_(events,'LTW',i), safe_num_(events,'RTW',i));

    typ = '';
    try typ = lower(strtrim(string(events.eventType(i)))); catch, end
    rawTyp = "";
    try rawTyp = string(events.rawType(i)); catch, rawTyp = ""; end
    rawTyp = strtrim(rawTyp);

    % 优先使用原始需求类型（论文表 5.6：新增/取消/减少/增加）
    if contains(rawTyp, "新增")
        typ = "新增";
    elseif contains(rawTyp, "取消")
        typ = "取消";
    elseif contains(rawTyp, "减少")
        typ = "减少";
    elseif contains(rawTyp, "增加")
        typ = "增加";
    else
        if typ == "add"
            typ = "新增";
        elseif typ == "cancel"
            typ = "取消";
        else
            % update：按 deltaDemandKg 的符号映射（仅展示；不改变事件语义）
            if isfinite(delta)
                if delta < -1e-9
                    typ = "减少";
                elseif delta > 1e-9
                    typ = "增加";
                else
                    typ = "变更";
                end
            else
                typ = "变更";
            end
        end
    end
    rows(i,:) = {cid, char(string(typ)), x, y, newq, winStr, tStr, oldq, newq, delta};
end
tOut = [header; rows];
end

function lines = demand_pressure_audit_541_(ctx, instancePrev, instanceNow, stateBefore, batch, cfg) %#ok<INUSD>
lines = {};

% 1) 新增/变更的需求变化统计（kg）
netAddUpdate = 0;
posAddUpdate = 0;
negAddUpdate = 0;
cancelNet = 0;
try
    for i = 1:height(batch)
        typ = lower(char(string(batch.eventType(i))));
        d = batch.deltaDemandKg(i);
        if ~isfinite(d), continue; end
        if strcmp(typ, 'cancel')
            cancelNet = cancelNet + d;
            continue;
        end
        if strcmp(typ, 'add') || strcmp(typ, 'update')
            netAddUpdate = netAddUpdate + d;
            posAddUpdate = posAddUpdate + max(d, 0);
            negAddUpdate = negAddUpdate + min(d, 0);
        end
    end
catch
end
lines{end+1,1} = sprintf('[pressure] batchDelta: add/update net=%g | pos=%g | neg=%g | cancelNet=%g', ...
    netAddUpdate, posAddUpdate, negAddUpdate, cancelNet); %#ok<AGROW>
try
    if isfield(cfg,'Mode') && strcmp(cfg.Mode, 'paper_repro')
        lines{end+1,1} = '[pressure] note: frozen segment is immutable; paper_repro uses departure-load capacity semantics to drive whether new vehicles are needed.'; %#ok<AGROW>
    else
        lines{end+1,1} = '[pressure] note: frozen segment is immutable; pending customers can be transferred/reordered.'; %#ok<AGROW>
    end
catch
    lines{end+1,1} = '[pressure] note: frozen segment is immutable.'; %#ok<AGROW>
end

% 2) 每辆车冻结段末端：已锁定(未开始服务但已冻结) vs 待配送(可重排/可移交) 的容量压力
try
    tNow = stateBefore.tNow;
    svcStart = [];
    if isfield(stateBefore,'customerServiceStartMin')
        svcStart = stateBefore.customerServiceStartMin;
    end

    for k = 1:numel(stateBefore.vehicles)
        sv = stateBefore.vehicles(k);
        cap = NaN;
        if sv.isEV
            try cap = ctx.P.Fleet.QEV; catch, cap = NaN; end
        else
            try cap = ctx.P.Fleet.QCV; catch, cap = NaN; end
        end

        frozen = [];
        try frozen = unique(sv.frozenCustomers(:)); catch, frozen = []; end
        servedOrStarted = [];
        try servedOrStarted = unique(sv.servedOrStartedCustomers(:)); catch, servedOrStarted = []; end
        pending = [];
        try pending = unique(sv.pendingCustomers(:)); catch, pending = []; end

        % 冻结但“未开始服务”的客户（例如在途目的客户）视为 committed
        committed = setdiff(frozen, servedOrStarted);
        committed = committed(isfinite(committed) & committed>=1 & committed<=instanceNow.Data.n);
        if ~isempty(svcStart)
            keep = false(size(committed));
            for ii = 1:numel(committed)
                cid = committed(ii);
                if cid <= numel(svcStart) && isfinite(svcStart(cid)) && (svcStart(cid) >= (tNow - 1e-9))
                    keep(ii) = true;
                end
            end
            committed = committed(keep);
        end

        pending = pending(isfinite(pending) & pending>=1 & pending<=instanceNow.Data.n);

        committedLoad = 0;
        pendingLoad = 0;
        try committedLoad = sum(instanceNow.Data.q(committed+1)); catch, committedLoad = NaN; end
        try pendingLoad = sum(instanceNow.Data.q(pending+1)); catch, pendingLoad = NaN; end

        capLeft = NaN;
        if isfinite(cap) && isfinite(committedLoad)
            capLeft = cap - committedLoad;
        end

        lines{end+1,1} = sprintf('[pressure] %s(k=%d, %s) cap=%g | committed=%gkg(n=%d) | pending=%gkg(n=%d) | capLeftAfterCommitted=%g', ...
            sv.name, k, sv.phase, cap, committedLoad, numel(committed), pendingLoad, numel(pending), capLeft); %#ok<AGROW>
    end
catch
end
end

function s = phase_to_cn_541_(phase)
s = char(string(phase));
p = lower(strtrim(s));
if strcmp(p, 'travel')
    s = '行驶';
elseif strcmp(p, 'service')
    s = '服务';
elseif strcmp(p, 'charge')
    s = '充电';
elseif strcmp(p, 'wait')
    s = '等待';
end
end

function s = tag_to_cn_541_(tag)
s = char(string(tag));
t = lower(strtrim(s));
if strcmp(t, 'init')
    s = '初始';
end
end

function [ctxWork, dataDiag] = apply_data_policy_541_(ctx, cfg, logPath, alignReportPath)
% apply_data_policy_541_ - 仅在 section_541 内部使用的“静态数据源策略”
% 约束：
% - 不写回 ctx（只返回 ctxWork）
% - 默认 prefer_data：优先使用 <projectRoot>/data/ 下的表格数据
% - 仅当用户显式设置 prefer_internal 才允许使用内置数据（避免默认 internal）

if nargin < 4, alignReportPath = ''; end
if nargin < 3, logPath = ''; end

ctxWork = ctx;
dataDiag = struct();
dataDiag.policy = '';
try dataDiag.policy = char(string(cfg.DataPolicy)); catch, dataDiag.policy = ''; end
if isempty(dataDiag.policy), dataDiag.policy = 'prefer_data'; end

dataDiag.baseDataSource = '';
dataDiag.baseDataPath = '';
dataDiag.baseDataSheet = 1;
dataDiag.baseDataRange = 'B2:F999';
dataDiag.dataFallback = false;
dataDiag.note = '';

policy = lower(strtrim(dataDiag.policy));
if strcmp(policy, 'prefer_internal')
    % 显式使用内置数据（仅当用户明确要求）
    try
        if isfield(ctxWork,'Data') && isfield(ctxWork.Data,'info') && isfield(ctxWork.Data.info,'source')
            dataDiag.baseDataSource = char(string(ctxWork.Data.info.source));
        end
    catch
    end
    if isempty(dataDiag.baseDataSource), dataDiag.baseDataSource = 'internal'; end
    dataDiag.baseDataPath = '(internal)';
    dataDiag.note = 'prefer_internal (explicit)';
    log_append_(logPath, sprintf('[data_base] policy=%s | source=%s | path=%s', policy, dataDiag.baseDataSource, dataDiag.baseDataPath));
    return;
end

% prefer_data：默认使用论文示例静态 xlsx；若不存在再回退 internal（需记录原因）
staticPath = '';
try
    if isfield(cfg,'PaperFiles') && isfield(cfg.PaperFiles,'staticPath')
        staticPath = char(string(cfg.PaperFiles.staticPath));
    end
catch
end
if isempty(staticPath)
    try staticPath = fullfile(ctx.Meta.projectRoot, 'data', '论文示例静态节点数据.xlsx'); catch, staticPath = ''; end
end

if ~isempty(staticPath) && exist(staticPath, 'file') == 2
    try
        [Data, meta] = read_static_nodes_541(staticPath, ctx);
        ctxWork.Data = Data;
        dataDiag.baseDataSource = 'paper_xlsx';
        dataDiag.baseDataPath = staticPath;
        dataDiag.baseDataSheet = 1;
        dataDiag.baseDataRange = '';
        dataDiag.note = 'paper_static_xlsx';
        log_append_(logPath, sprintf('[data_base] policy=%s | source=%s | path=%s', policy, dataDiag.baseDataSource, dataDiag.baseDataPath));
        return;
    catch ME
        dataDiag.note = sprintf('paper_xlsx failed: %s', ME.message);
    end
else
    dataDiag.note = 'paper_xlsx missing';
end

% fallback internal（仅记录，不改算法）
dataDiag.dataFallback = true;
dataDiag.baseDataSource = 'internal';
dataDiag.baseDataPath = '(internal)';
log_append_(logPath, sprintf('[data_base] fallback_to_internal: %s', dataDiag.note));
if ~isempty(alignReportPath)
    log_append_(alignReportPath, sprintf('[data_base] fallback_to_internal: %s', dataDiag.note));
end
end

function ctxWork = apply_paper_fleet_override_541_(ctxWork, cfg, logPath, alignReportPath)
% paper_repro: 论文 5.2 车队规模固定为 5/5（可用车队），不改初始 4 条路线的来源
if nargin < 4, alignReportPath = ''; end
if nargin < 3, logPath = ''; end
try
    if ~strcmp(cfg.Mode, 'paper_repro')
        return;
    end
catch
    return;
end
try
    oldCV = ctxWork.P.Fleet.nCV;
    oldEV = ctxWork.P.Fleet.nEV;
catch
    return;
end
if ~isfinite(oldCV) || ~isfinite(oldEV)
    return;
end
if oldCV == 5 && oldEV == 5
    return;
end
ctxWork.P.Fleet.nCV = 5;
ctxWork.P.Fleet.nEV = 5;
log_append_(logPath, sprintf('[paper_override] Fleet.nCV/nEV: %g/%g -> 5/5 (section_541 paper_repro)', oldCV, oldEV));
if ~isempty(alignReportPath)
    log_append_(alignReportPath, sprintf('[paper_override] Fleet.nCV/nEV: %g/%g -> 5/5 (section_541 paper_repro)', oldCV, oldEV));
end
end

function [needExtraEV, reason] = demand_driven_extra_ev_541_(ctx, instanceNow, stateBefore)
needExtraEV = false;
reason = '';
try
    activeIds = find(instanceNow.Data.q(2:instanceNow.Data.n+1) > 0);
catch
    activeIds = [];
end
frozen = [];
try frozen = unique(stateBefore.frozenCustomers(:)); catch, frozen = []; end
pending = setdiff(activeIds, frozen, 'stable');

pendingDemand = 0;
try
    if ~isempty(pending)
        pendingDemand = sum(instanceNow.Data.q(pending+1));
    end
catch
    pendingDemand = 0;
end

    capLeftTotal = 0;
    try
        for k = 1:numel(stateBefore.vehicles)
            sv = stateBefore.vehicles(k);
            % 仅统计“已派车且未结束”的车辆：空车(未派车)不计入；已结束(done)不计入
            dispatched = false;
            try
                dispatched = ~isempty(sv.pendingCustomers) || ~isempty(sv.servedCustomers) || ~isempty(sv.servedOrStartedCustomers) || ~isempty(sv.frozenCustomers);
            catch
                dispatched = false;
            end
            if ~dispatched
                continue;
            end
            if isfield(sv,'phase') && strcmp(sv.phase, 'done')
                continue;
            end
            cap = NaN;
        if sv.isEV
            try cap = ctx.P.Fleet.QEV; catch, cap = NaN; end
        else
            try cap = ctx.P.Fleet.QCV; catch, cap = NaN; end
        end
        frozenK = [];
        servedOrStarted = [];
        try frozenK = unique(sv.frozenCustomers(:)); catch, frozenK = []; end
        try servedOrStarted = unique(sv.servedOrStartedCustomers(:)); catch, servedOrStarted = []; end
        committed = setdiff(frozenK, servedOrStarted);
        committed = committed(isfinite(committed) & committed>=1 & committed<=instanceNow.Data.n);
        committedLoad = 0;
        try committedLoad = sum(instanceNow.Data.q(committed+1)); catch, committedLoad = 0; end
        if isfinite(cap)
            capLeft = cap - committedLoad;
            if capLeft > 0
                capLeftTotal = capLeftTotal + capLeft;
            end
        end
    end
catch
    capLeftTotal = 0;
end

if pendingDemand > capLeftTotal + 1e-9
    needExtraEV = true;
    reason = sprintf('pendingDemand=%g > capLeft=%g (paper_repro add EV)', pendingDemand, capLeftTotal);
else
    reason = sprintf('pendingDemand=%g <= capLeft=%g', pendingDemand, capLeftTotal);
end
end

function plan2 = expand_plan_to_pool_541_(plan, nCVPool, nEVPool)
% expand_plan_to_pool_541_ - 将 CV/EV 分段的 plan.detail 映射到更大的 (nCVPool+nEVPool) 车位上：
% - CV 段保持在 1..nCVPool 前缀；EV 段移动到 (nCVPool+1)..(nCVPool+nEV0)
% 仅用于 paper_repro 的车型/编号对齐；不修改路线内容。
    plan2 = plan;
    nCV0 = round(plan.nCV);
    nEV0 = round(plan.nEV);
    if ~isfinite(nCV0) || ~isfinite(nEV0) || nCV0 < 0 || nEV0 < 0
        error('expand_plan_to_pool_541:badFleet', 'invalid plan fleet: CV%g EV%g', plan.nCV, plan.nEV);
    end
    if ~isfinite(nCVPool) || ~isfinite(nEVPool) || nCVPool < 0 || nEVPool < 0
        error('expand_plan_to_pool_541:badPool', 'invalid pool fleet: CV%g EV%g', nCVPool, nEVPool);
    end
    if isempty(plan.detail) || numel(plan.detail) ~= (nCV0 + nEV0)
        error('expand_plan_to_pool_541:badDetail', 'plan.detail size mismatch: got %d, expect %d', numel(plan.detail), nCV0+nEV0);
    end
    if nCVPool < nCV0 || nEVPool < nEV0
        error('expand_plan_to_pool_541:poolTooSmall', 'pool smaller than plan: plan CV%d EV%d vs pool CV%d EV%d', nCV0, nEV0, nCVPool, nEVPool);
    end

    K = nCVPool + nEVPool;
    blank = plan.detail(1);
    blank.route = [0 0];
    blank.startTimeMin = 0;
    detail2 = repmat(blank, K, 1);

    % CV：保持位置不变（前缀）
    for k = 1:nCV0
        detail2(k) = plan.detail(k);
    end
    % EV：整体右移到 EV 段（紧跟在 CV 段之后）
    for e = 1:nEV0
        src = nCV0 + e;
        dst = nCVPool + e;
        detail2(dst) = plan.detail(src);
    end

    plan2.detail = detail2;
    plan2.nCV = nCVPool;
    plan2.nEV = nEVPool;
    plan2.fleetTag = sprintf('CV%d_EV%d', round(plan2.nCV), round(plan2.nEV));
end

function v = safe_num_(tbl, field, i)
v = NaN;
try
    if ismember(field, tbl.Properties.VariableNames)
        v = tbl.(field)(i);
        if iscell(v), v = v{1}; end
    end
catch
    v = NaN;
end
end

function s = window_str_541_(ltw, rtw)
if ~isfinite(ltw) || ~isfinite(rtw)
    s = '';
    return;
end
s = sprintf('[%s-%s]', min_to_hhmm_(ltw), min_to_hhmm_(rtw));
end

function order = vehicle_order_local_541_(names)
n = numel(names);
meta = zeros(n, 3); % [typeOrder, idxNum, origIdx]
for i = 1:n
    s = upper(strtrim(char(string(names(i)))));
    t = 3;
    idxNum = i;
    if startsWith(s,'CV')
        t = 1;
        idxNum = str2double(regexprep(s,'[^0-9]',''));
    elseif startsWith(s,'EV')
        t = 2;
        idxNum = str2double(regexprep(s,'[^0-9]',''));
    end
    if ~isfinite(idxNum), idxNum = i; end
    meta(i,:) = [t, idxNum, i];
end
[~, ord] = sortrows(meta, [1 2 3]);
order = ord(:).';
end

function [nodeStr, timeStr] = route_strings_local_541_(veh, n, E)
route = veh.route(:).';
if isempty(route)
    nodeStr = '';
    timeStr = '';
    return;
end
labels = strings(numel(route),1);
for i = 1:numel(route)
    labels(i) = node_label_table_local_541_(route(i), n, E);
end
nodeStr = strjoin(cellstr(labels), '->');

tVals = NaN(numel(route),1);
tVals(1) = veh.startTimeMin;
for i = 2:numel(route)
    vi = find_visit_by_seq_local_541_(veh, i);
    if isempty(vi)
        tVals(i) = NaN;
    else
        if isfield(vi,'isCustomer') && vi.isCustomer
            tVals(i) = vi.tServiceStartMin;
        elseif isfield(vi,'isStation') && vi.isStation
            tVals(i) = vi.tArriveMin;
        else
            tVals(i) = vi.tArriveMin;
        end
    end
end
tStr = strings(numel(tVals),1);
for i = 1:numel(tVals)
    tStr(i) = string(min_to_hhmm_(tVals(i)));
end
timeStr = strjoin(cellstr(tStr), '->');
end

function vi = find_visit_by_seq_local_541_(veh, seqIndex)
vi = [];
if ~isfield(veh,'visits') || isempty(veh.visits)
    return;
end
for i = 1:numel(veh.visits)
    if isfield(veh.visits(i),'seqIndex') && veh.visits(i).seqIndex == seqIndex
        vi = veh.visits(i);
        return;
    end
end
end

function label = node_label_table_local_541_(node, n, E)
if node == 0
    label = '0';
    return;
end
if node >= (n+1) && node <= (n+E)
    label = sprintf('R%d', node - n);
    return;
end
label = sprintf('%d', node);
end

function startTimeMin = infer_depart_time_from_first_customer_541_(route, tNow, G, k)
% infer_depart_time_from_first_customer_541_ - infer depart time by back-propagating from first customer's LT
% This matches the paper Table5.7 style ("depart so that arrive at first customer ~= LT") when LT is provided.
    if nargin < 2 || ~isfinite(tNow)
        tNow = 0;
    end
    startTimeMin = tNow;
    if nargin < 3 || ~isstruct(G) || isempty(route)
        startTimeMin = max(0, startTimeMin);
        return;
    end

    r = route(:).';
    r = r(isfinite(r));

    firstCus = NaN;
    for i = 1:numel(r)
        node = r(i);
        if node == 0
            continue;
        end
        if is_station(node, G)
            continue;
        end
        if node >= 1 && node <= G.n
            firstCus = node;
            break;
        end
    end
    if ~isfinite(firstCus)
        startTimeMin = max(0, startTimeMin);
        return;
    end

    try
        lt = G.LT(firstCus+1);
        d = G.D(1, firstCus+1);
        sp = NaN;
        try sp = G.Speed(k); catch, sp = NaN; end
        if ~isfinite(sp) || sp <= 0
            try sp = G.Speed(1); catch, sp = 40/60; end
        end
        tTravel = d / max(sp, 1e-12);
        if isfinite(lt) && isfinite(tTravel)
            startTimeMin = max(startTimeMin, lt - tTravel);
        end
    catch
    end

    if ~isfinite(startTimeMin)
        startTimeMin = tNow;
    end
    startTimeMin = max(startTimeMin, tNow);
    startTimeMin = max(0, startTimeMin);
end

function [ok, msg] = compare_init_plan_to_table57_541_(init, ref)
% compare_init_plan_to_table57_541_ - compare init routes with paper Table5.7 (report only; do not override)
    ok = true;
    msg = 'routes match Table5.7';

    if ~isfield(init,'detail') || ~isfield(ref,'detail')
        ok = false;
        msg = 'missing detail';
        return;
    end
    K1 = numel(init.detail);
    K2 = numel(ref.detail);
    if K1 ~= K2
        ok = false;
        msg = sprintf('routeCount=%d (paper=%d)', K1, K2);
        return;
    end

    tolStartMin = 1; % minutes; only for reporting
    for k = 1:K1
        r1 = [];
        r2 = [];
        try r1 = init.detail(k).route(:).'; catch, r1 = []; end
        try r2 = ref.detail(k).route(:).';  catch, r2 = []; end
        r1 = r1(isfinite(r1));
        r2 = r2(isfinite(r2));
        if ~isequal(r1, r2)
            ok = false;
            msg = sprintf('k=%d route mismatch: got=%s | paper=%s', k, route_to_str_541_(r1), route_to_str_541_(r2));
            return;
        end
        % start time: not a hard gate (531 does not store startTimeMin); only report mismatch if both are finite
        try
            t1 = init.detail(k).startTimeMin;
            t2 = ref.detail(k).startTimeMin;
            if isfinite(t1) && isfinite(t2) && (abs(double(t1) - double(t2)) > tolStartMin + 1e-9)
                ok = false;
                msg = sprintf('k=%d startTimeMin mismatch: got=%gmin paper=%gmin (routes match)', k, double(t1), double(t2));
                return;
            end
        catch
        end
    end
end

function s = route_to_str_541_(route)
    if isempty(route)
        s = '[]';
        return;
    end
    try
        s = sprintf('%d-', route);
        if ~isempty(s)
            s = s(1:end-1);
        end
    catch
        s = '[?]';
    end
end

function lv = normalize_parallel_log_level_541_(lvRaw)
lv = lower(strtrim(char(string(lvRaw))));
if ~any(strcmp(lv, {'none', 'summary', 'detailed'}))
    lv = 'detailed';
end
end

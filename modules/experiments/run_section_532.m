function out = run_section_532(ctx)
% 修改日志
% - v5 2026-02-10: 新增 SECTION532_PARALLEL_LOG_LEVEL；并行模式下按 run 序输出顺序化详细日志（none/summary/detailed）。
% - v4 2026-02-09: 新增 SECTION532_PARALLEL_ENABLE/WORKERS 并行加速；并将并行日志改为按 run 序号汇总输出，提升可读性。
% - v1 2026-01-21: 新增 run_section_532(ctx)；统一从 ctx 取参/签名/输出路径；mix_2_2 缓存必须做签名校验。
% - v1 2026-01-21: 缓存目录统一 outputs/section_532/cache；旧 CACHE/section_532 作为 legacy 目录仅允许“签名匹配”才可用（无签名一律忽略）。
% - v2 2026-01-21: 缓存命中/未命中提示中文化；补齐 out.meta.features 供规范检查器校验。
% - v3 2026-02-03: 从环境变量读取输出控制开关（VERBOSE/KEEP_FIGURES/PRINT_TABLES），由 run_modes.m 统一控制。
sectionName = 'section_532';
modeTag = 'compare';

% ===== 从环境变量读取输出控制开关（由 run_modes.m 设置）=====
cfg_verbose = env_bool_or_default_('SECTION532_VERBOSE', true);
cfg_keepFigures = env_bool_or_default_('SECTION532_KEEP_FIGURES', true);
cfg_printTables = env_bool_or_default_('SECTION532_PRINT_TABLES', true);
% ============================================================

paths = output_paths(ctx.Meta.projectRoot, sectionName, ctx.Meta.runTag);
sigBase = build_signature(ctx);

if cfg_verbose
    fprintf('[%s] runTag=%s | modeTag=%s | paramSig=%s | dataSig=%s\n', ...
        sectionName, ctx.Meta.runTag, modeTag, sigBase.param.short, sigBase.data.short);
end

% ---------- Case A: MIX_2_2（可缓存） ----------
mixKey = 'mix_2_2';
mixCaseTag = 'MIX_2_2';

% 先扫描 legacy 目录，确保旧缓存不被误读（无签名/签名不匹配都会被 ignore 并打印）
legacyCacheDir = fullfile(ctx.Meta.projectRoot, 'CACHE', sectionName);

if exist(legacyCacheDir, 'dir') == 7
    cache_load_best(legacyCacheDir, mixKey, sigBase.param.full, sigBase.data.full, 'ForceRecompute', ctx.SolverCfg.forceRecompute);
end

[mixPayload, mixCachePath, mixCacheMeta] = cache_load_best(paths.cache, mixKey, sigBase.param.full, sigBase.data.full, ...
    'ForceRecompute', ctx.SolverCfg.forceRecompute);
mixResult = [];
if ~isempty(mixPayload)
    mixResult = mixPayload;
    if cfg_verbose
        fprintf('[%s][缓存] 已加载 %s: %s\n', sectionName, mixKey, mixCachePath);
    end
else
    if cfg_verbose
        fprintf('[%s][缓存] 未命中 -> 重算 %s\n', sectionName, mixKey);
    end
    mixResult = run_one_case_(ctx, mixCaseTag, ctx.P.Fleet.nCV, ctx.P.Fleet.nEV, false, paths, sigBase, modeTag);

    meta = struct();
    meta.sectionName = sectionName;
    meta.modeTag = mixCaseTag;
    meta.timestamp = ctx.Meta.timestamp;
    meta.paramSigFull = sigBase.param.full;
    meta.paramSigShort = sigBase.param.short;
    meta.dataSigFull = sigBase.data.full;
    meta.dataSigShort = sigBase.data.short;
    meta.cost = mixResult.bestGlobal.cost;
    try
        saved = cache_save(paths.cache, mixKey, mixResult, meta);
        if cfg_verbose
            fprintf('[%s][缓存] 已保存: %s\n', sectionName, saved);
        end
    catch ME
        if cfg_verbose
            fprintf('[%s][缓存] 保存失败: %s\n', sectionName, ME.message);
        end
    end
end

% ---------- Case B: CUSTOM（默认 3CV+0EV，可在 ctx.P.Section532 中配置） ----------
custom_nCV = round(ctx.P.Section532.custom_nCV);
custom_nEV = round(ctx.P.Section532.custom_nEV);
customTag  = char(string(ctx.P.Section532.custom_case_tag));

customOverride = struct('P', struct('Fleet', struct('nCV', custom_nCV, 'nEV', custom_nEV)));
ctxCustom = apply_override(ctx, customOverride);
sigCustom = build_signature(ctxCustom);

customResult = run_one_case_(ctxCustom, customTag, custom_nCV, custom_nEV, true, paths, sigCustom, modeTag);

% ---------- 表 5.5：对比 ----------
table55 = [];
try
    table55 = build_table55(customResult.summary, mixResult.summary);
    if cfg_printTables
        disp('===== 表5.5(配送结果对比) =====');
        disp(table55);
    end
    t55Path = fullfile(paths.tables, artifact_filename('配送结果对比', sectionName, modeTag, sigBase.param.short, sigBase.data.short, ctx.Meta.timestamp, '.xlsx'));
    try
        writetable(table55, t55Path);
    catch
        t55Path = replace_ext_(t55Path, '.csv');
        writetable(table55, t55Path);
    end
catch ME
    fprintf('[%s] build_table55 failed: %s\n', sectionName, ME.message);
    t55Path = '';
end

out = struct();
out.meta = struct('sectionName', sectionName, 'modeTag', modeTag, 'runTag', ctx.Meta.runTag, ...
    'timestamp', ctx.Meta.timestamp, 'paramSig', sigBase.param, 'dataSig', sigBase.data);
out.meta.features = {'cache','table'};
out.paths = paths;
out.mixResult = mixResult;
out.customResult = customResult;
out.table55 = table55;
out.artifacts = struct();
if exist('t55Path','var'), out.artifacts.table55 = t55Path; end
if exist('mixCacheMeta','var') && isstruct(mixCacheMeta) && ~isempty(fieldnames(mixCacheMeta))
    out.cacheMeta.mix = mixCacheMeta;
end
end

function result = run_one_case_(ctxCase, caseTag, nCV, nEV, isCustomCase, paths, sig, modeTag)
sectionName = 'section_532';

% 从环境变量读取输出控制开关
cfg_verbose = env_bool_or_default_('SECTION532_VERBOSE', true);
cfg_keepFigures = env_bool_or_default_('SECTION532_KEEP_FIGURES', true);
cfg_parallelEnable = env_bool_or_default_('SECTION532_PARALLEL_ENABLE', false);
cfg_parallelWorkers = env_int_or_default_('SECTION532_PARALLEL_WORKERS', 0);
cfg_parallelLogLevel = normalize_parallel_log_level_532_(env_str_or_default_('SECTION532_PARALLEL_LOG_LEVEL', 'detailed'));

caseModeTag = sprintf('%s_%s', modeTag, caseTag);

if cfg_verbose
    fprintf('[%s] case=%s | nCV=%d nEV=%d | paramSig=%s dataSig=%s\n', ...
        sectionName, caseTag, nCV, nEV, sig.param.short, sig.data.short);
end

G = build_G_from_ctx(ctxCase, 'nCV', nCV, 'nEV', nEV, 'AllowCharging', true, 'ForceChargeOnce', false, 'ForceChargePolicy', 'ANY_EV');

n = ctxCase.Data.n;
E = ctxCase.Data.E;
coord = ctxCase.Data.coord;

% SolverCfg
NP = ctxCase.SolverCfg.NP;
MaxGen = ctxCase.SolverCfg.MaxGen;
Pc = ctxCase.SolverCfg.Pc;
Pm = ctxCase.SolverCfg.Pm;
Pe = ctxCase.SolverCfg.Pe;
T0 = ctxCase.SolverCfg.T0;
Tmin = ctxCase.SolverCfg.Tmin;
alpha = ctxCase.SolverCfg.alpha;
STOP_BY_TMIN = ctxCase.SolverCfg.STOP_BY_TMIN;
NRun = ctxCase.SolverCfg.NRun;

parallelCtl = resolve_parallel_control_532_(cfg_parallelEnable, cfg_parallelWorkers, NRun, cfg_verbose, sectionName, caseTag);
try
    G.opt.consoleVerbose = logical(cfg_verbose && ~parallelCtl.enabled);
catch
end
if cfg_verbose
    fprintf('[%s][%s] solver=GSAA | NRun=%d | parallel=%d(workers=%d) | logLevel=%s | reason=%s\n', ...
        sectionName, caseTag, round(NRun), double(parallelCtl.enabled), round(parallelCtl.workersActive), ...
        char(string(cfg_parallelLogLevel)), char(string(parallelCtl.reason)));
end

bestGlobal = struct('cost', inf, 'ch', [], 'detail', [], 'run', NaN, 'seed', NaN, 'isFeasible', false);
bestGlobalPen = struct('cost', inf, 'ch', [], 'detail', [], 'run', NaN, 'seed', NaN, 'isFeasible', false);

feasCountInit = zeros(NRun, 1);
firstFeasibleGenRun = NaN(NRun, 1);
stopGenRun = NaN(NRun, 1);
foundFeasibleRun = false(NRun, 1);
bestFeasibleCostRun = NaN(NRun, 1);
runRec = repmat(struct( ...
    'seed', NaN, ...
    'initStrictFeasible', NaN, ...
    'firstFeasibleGen', NaN, ...
    'stopGen', NaN, ...
    'bestFeasibleFound', false, ...
    'bestCost', NaN, ...
    'bestCh', [], ...
    'bestPenaltyCost', inf, ...
    'bestPenaltyCh', [], ...
    'elapsedSec', NaN), NRun, 1);

if parallelCtl.enabled
    if cfg_verbose
        fprintf('[%s][%s] 并行执行 NRun：%d 次（workers=%d）\n', sectionName, caseTag, NRun, round(parallelCtl.workersActive));
    end
    parfor run = 1:NRun
        runRec(run) = run_one_seed_532_(run, NP, MaxGen, Pc, Pm, Pe, T0, Tmin, alpha, STOP_BY_TMIN, G);
    end
else
    for run = 1:NRun
        if cfg_verbose
            fprintf('[%s][%s] 运行 %d/%d (seed=%d)\n', sectionName, caseTag, run, NRun, run);
        end
        runRec(run) = run_one_seed_532_(run, NP, MaxGen, Pc, Pm, Pe, T0, Tmin, alpha, STOP_BY_TMIN, G);
    end
end

if cfg_verbose && parallelCtl.enabled
    emit_parallel_logs_532_(sectionName, caseTag, runRec, NRun, cfg_parallelLogLevel);
end

for run = 1:NRun
    feasCountInit(run) = runRec(run).initStrictFeasible;
    firstFeasibleGenRun(run) = runRec(run).firstFeasibleGen;
    stopGenRun(run) = runRec(run).stopGen;
    foundFeasibleRun(run) = runRec(run).bestFeasibleFound;
    if runRec(run).bestFeasibleFound
        bestFeasibleCostRun(run) = runRec(run).bestCost;
    end

    if runRec(run).bestFeasibleFound && runRec(run).bestCost < bestGlobal.cost
        bestGlobal.cost = runRec(run).bestCost;
        bestGlobal.ch = runRec(run).bestCh;
        bestGlobal.run = run;
        bestGlobal.seed = runRec(run).seed;
    end
    if isfinite(runRec(run).bestPenaltyCost) && runRec(run).bestPenaltyCost < bestGlobalPen.cost
        bestGlobalPen.cost = runRec(run).bestPenaltyCost;
        bestGlobalPen.ch = runRec(run).bestPenaltyCh;
        bestGlobalPen.run = run;
        bestGlobalPen.seed = runRec(run).seed;
    end
end

if isfinite(bestGlobal.cost)
    bestGlobal.isFeasible = true;
else
    warning('[%s][%s] NRun=%d 未找到严格可行解，回退 penalty 解用于表格/绘图（不造假）', sectionName, caseTag, NRun);
    bestGlobal = bestGlobalPen;
    bestGlobal.isFeasible = false;
end

% CV-only 后处理（使用 ctx 真源参数）
if cv_only_case(G) && isfield(G,'cvOnlyOpt') && isstruct(G.cvOnlyOpt) && isfield(G.cvOnlyOpt,'enableCVOnlyImprove') && G.cvOnlyOpt.enableCVOnlyImprove
    try
        [bestCh2, bestCost2, cvStats] = post_improve_cv_only(bestGlobal.ch, bestGlobal.cost, G, G.cvOnlyOpt);
        if isfinite(bestCost2) && bestCost2 + 1e-9 < bestGlobal.cost
            if cfg_verbose
                fprintf('[%s][%s][post] CV-only improve: %.6f -> %.6f\n', sectionName, caseTag, bestGlobal.cost, bestCost2);
            end
            bestGlobal.ch = bestCh2;
            bestGlobal.cost = bestCost2;
            bestGlobal.cvOnlyStats = cvStats;
        end
    catch ME
        if cfg_verbose
            fprintf('[%s][%s][post] CV-only improve failed: %s\n', sectionName, caseTag, ME.message);
        end
    end
end

[~,~,~,bestGlobal.detail] = fitness_strict_penalty(bestGlobal.ch, G);

if cfg_verbose
    fprintf('[%s][%s] bestCost=%.6f | bestRun=%g | feasible=%d\n', sectionName, caseTag, bestGlobal.cost, bestGlobal.run, double(bestGlobal.isFeasible));
end

routeInfo = build_tables_from_detail(bestGlobal.detail, n, E, nCV);

statsRun = table((1:NRun)', feasCountInit, firstFeasibleGenRun, stopGenRun, foundFeasibleRun, bestFeasibleCostRun, ...
    'VariableNames', {'运行','初始严格可行','首次可行代','停止代','找到可行','最优可行成本'});

% tables
% === 论文表格对齐说明（paper_repro 严格对齐）===
% 表5.2/5.3：混合车队配送方案（含电能成本列）
% 表5.4：燃油车队配送路径的各项成本（无电能成本列，对应论文 5.3.2 节）
% ============================================
fleetPlanName = '物流配送方案';
fleetCostName = '配送路径的各项成本';
useCVOnlyTable = false;  % 是否使用表5.4格式（无电能成本列）
if nCV > 0 && nEV > 0
    fleetPlanName = '混合车队的物流配送方案';
    fleetCostName = '配送路径的各项成本';
elseif nCV > 0 && nEV == 0
    fleetPlanName = '燃油车队的物流配送方案';
    fleetCostName = '燃油车队配送路径的各项成本';  % 对应论文表5.4
    useCVOnlyTable = true;
elseif nCV == 0 && nEV > 0
    fleetPlanName = '纯电车队的物流配送方案';
    fleetCostName = '纯电车队配送路径的各项成本';
end
t52Path = fullfile(paths.tables, artifact_filename(fleetPlanName, sectionName, caseModeTag, sig.param.short, sig.data.short, ctxCase.Meta.timestamp, '.xlsx'));
t53Path = fullfile(paths.tables, artifact_filename(fleetCostName, sectionName, caseModeTag, sig.param.short, sig.data.short, ctxCase.Meta.timestamp, '.xlsx'));
rsPath  = fullfile(paths.tables, artifact_filename('运行统计', sectionName, caseModeTag, sig.param.short, sig.data.short, ctxCase.Meta.timestamp, '.xlsx'));
try
    writetable(routeInfo.table52, t52Path);
    % 论文表5.4（燃油车队）无电能成本列，使用专用函数生成
    if useCVOnlyTable
        t54 = build_table54_from_detail(bestGlobal.detail);
        writetable(t54, t53Path);
    else
        writetable(routeInfo.table53, t53Path);
    end
    writetable(statsRun, rsPath);
catch
    t52Path = replace_ext_(t52Path, '.csv');
    t53Path = replace_ext_(t53Path, '.csv');
    rsPath  = replace_ext_(rsPath,  '.csv');
    writetable(routeInfo.table52, t52Path);
    if useCVOnlyTable
        t54 = build_table54_from_detail(bestGlobal.detail);
        writetable(t54, t53Path);
    else
        writetable(routeInfo.table53, t53Path);
    end
    writetable(statsRun, rsPath);
end

% Route fig
legendMode = legend_mode_for_fleet(nCV, nEV);
titleText = title_for_fleet(nCV, nEV);
fig = plot_routes_with_labels(coord, n, E, bestGlobal.detail, legendMode, titleText, G);
apply_plot_style(fig, findall(fig,'Type','axes'), 'default');
routePng = fullfile(paths.figures, artifact_filename(titleText, sectionName, caseModeTag, sig.param.short, sig.data.short, ctxCase.Meta.timestamp, '.png'));
export_figure(fig, routePng, 300);
if ~cfg_keepFigures
    close(fig);
end

% summary for table55
fleetLabel = fleet_type_label(nCV, nEV, logical(isCustomCase));
summary = summarize_for_table55(bestGlobal.detail, G, fleetLabel);

result = struct();
result.caseTag = caseTag;
result.nCV = nCV;
result.nEV = nEV;
result.bestGlobal = bestGlobal;
result.routeInfo = routeInfo;
result.statsRun = statsRun;
result.summary = summary;
result.artifacts = struct('table52', t52Path, 'table53', t53Path, 'runStats', rsPath, 'routePng', routePng);
end

function p = replace_ext_(p, newExt)
[d, n] = fileparts(p);
if newExt(1) ~= '.', newExt = ['.' newExt]; end
p = fullfile(d, [n newExt]);
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

function lv = normalize_parallel_log_level_532_(lvRaw)
lv = lower(strtrim(char(string(lvRaw))));
if ~any(strcmp(lv, {'none', 'summary', 'detailed'}))
    lv = 'detailed';
end
end

function ctl = resolve_parallel_control_532_(requested, workersRequested, nRun, cfg_verbose, sectionName, caseTag)
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
        warning('run_section_532:parallelFallback', '[%s][%s] 并行初始化失败，回退串行：%s', sectionName, caseTag, ME.message);
    end
end
end

function rec = run_one_seed_532_(seed, NP, MaxGen, Pc, Pm, Pe, T0, Tmin, alpha, STOP_BY_TMIN, G)
rng(seed, 'twister');
t0 = tic;
outRun = one_run_gsaa(NP, MaxGen, Pc, Pm, Pe, T0, Tmin, alpha, STOP_BY_TMIN, G);
rec = struct();
rec.seed = seed;
rec.initStrictFeasible = outRun.initStrictFeasible;
rec.firstFeasibleGen = outRun.firstFeasibleGen;
rec.stopGen = outRun.stopGen;
rec.bestFeasibleFound = logical(outRun.bestFeasibleFound);
rec.bestCost = NaN;
rec.bestCh = [];
if rec.bestFeasibleFound
    rec.bestCost = outRun.bestCost;
    rec.bestCh = outRun.bestCh;
end
rec.bestPenaltyCost = inf;
rec.bestPenaltyCh = [];
if isfield(outRun,'bestPenaltyCost') && isfinite(outRun.bestPenaltyCost)
    rec.bestPenaltyCost = outRun.bestPenaltyCost;
end
if isfield(outRun,'bestPenaltyCh')
    rec.bestPenaltyCh = outRun.bestPenaltyCh;
end
rec.elapsedSec = toc(t0);
end

function s = fmt_num_532_(v)
if ~isfinite(v)
    s = 'NA';
else
    s = sprintf('%.6f', v);
end
end

function emit_parallel_logs_532_(sectionName, caseTag, runRec, nRun, logLevel)
if strcmp(logLevel, 'none')
    return;
end
for run = 1:nRun
    rec = runRec(run);
    if strcmp(logLevel, 'summary')
        fprintf('[%s][%s][run %d/%d] seed=%d | feasible=%d | best=%s | stopGen=%s | elapsed=%ss\n', ...
            sectionName, caseTag, run, nRun, round(rec.seed), double(rec.bestFeasibleFound), ...
            fmt_num_532_(rec.bestCost), fmt_num_532_(rec.stopGen), fmt_num_532_(rec.elapsedSec));
    else
        fprintf('[%s][%s][run %d/%d] seed=%d\n', sectionName, caseTag, run, nRun, round(rec.seed));
        fprintf('  [初始化] strictFeasible=%s | firstFeasibleGen=%s | stopGen=%s\n', ...
            fmt_num_532_(rec.initStrictFeasible), fmt_num_532_(rec.firstFeasibleGen), fmt_num_532_(rec.stopGen));
        fprintf('  [结果] feasible=%d | best=%s | penaltyBest=%s | elapsed=%ss\n', ...
            double(rec.bestFeasibleFound), fmt_num_532_(rec.bestCost), fmt_num_532_(rec.bestPenaltyCost), fmt_num_532_(rec.elapsedSec));
    end
end
end

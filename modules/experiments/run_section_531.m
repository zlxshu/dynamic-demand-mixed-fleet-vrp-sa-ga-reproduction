function out = run_section_531(ctx)
% 修改日志
% - v8 2026-02-10: 新增 SECTION531_PARALLEL_LOG_LEVEL；并行模式下提供按 run 序的顺序化详细日志（none/summary/detailed）。
% - v7 2026-02-09: 新增 SECTION531_PARALLEL_ENABLE/WORKERS 并行加速；并将终端输出改为“并行计算+有序汇总”，避免日志交叉污染。
% - v1 2026-01-21: 新增 run_section_531(ctx)；统一从 ctx 取参/签名/输出路径，禁止本地写死参数。
% - v1 2026-01-21: 输出统一落盘 outputs/section_531/{tables,figures,mats}，文件名含签名与 runTag。
% - v2 2026-01-21: 控制台输出中文化（运行）；补齐 out.meta.features 供规范检查器校验。
% - v3 2026-01-24: 增加进度提示：说明迭代日志只在特定代数输出，避免 IDE 终端误判“卡死”。
% - v4 2026-01-31: 增加 5 车排查日志（debug）。
% - v5 2026-02-03: 保存 out 到 section_531/mats 便于复用（不覆盖）。
% - v6 2026-02-03: 从环境变量读取输出控制开关（VERBOSE/KEEP_FIGURES/PRINT_TABLES），由 run_modes.m 统一控制。

sectionName = 'section_531';
modeTag = 'actualBest';

% ===== 从环境变量读取输出控制开关（由 run_modes.m 设置）=====
cfg_verbose = env_bool_or_default_('SECTION531_VERBOSE', true);
cfg_keepFigures = env_bool_or_default_('SECTION531_KEEP_FIGURES', true);
cfg_printTables = env_bool_or_default_('SECTION531_PRINT_TABLES', true);
cfg_parallelEnable = env_bool_or_default_('SECTION531_PARALLEL_ENABLE', false);
cfg_parallelWorkers = env_int_or_default_('SECTION531_PARALLEL_WORKERS', 0);
cfg_parallelLogLevel = normalize_parallel_log_level_531_(env_str_or_default_('SECTION531_PARALLEL_LOG_LEVEL', 'detailed'));
% ============================================================

paths = output_paths(ctx.Meta.projectRoot, sectionName, ctx.Meta.runTag);
sig = build_signature(ctx);

if cfg_verbose
    fprintf('[%s] runTag=%s | modeTag=%s | paramSig=%s | dataSig=%s\n', ...
        sectionName, ctx.Meta.runTag, modeTag, sig.param.short, sig.data.short);
end

% 构建 G（统一口径）
G = build_G_from_ctx(ctx, ...
    'nCV', ctx.P.Fleet.nCV, ...
    'nEV', ctx.P.Fleet.nEV, ...
    'AllowCharging', true, ...
    'ForceChargeOnce', false, ...
    'ForceChargePolicy', 'ANY_EV');

n = ctx.Data.n;
E = ctx.Data.E;
coord = ctx.Data.coord;

% SolverCfg
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

parallelCtl = resolve_parallel_control_(cfg_parallelEnable, cfg_parallelWorkers, NRun, cfg_verbose, sectionName);
try
    G.opt.consoleVerbose = logical(cfg_verbose && ~parallelCtl.enabled);
catch
end
if cfg_verbose
    fprintf('[%s] solver=GSAA | NRun=%d | parallel=%d(workers=%d) | logLevel=%s | reason=%s\n', ...
        sectionName, round(NRun), double(parallelCtl.enabled), round(parallelCtl.workersActive), ...
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
        fprintf('[%s] 并行执行 NRun：%d 次（workers=%d）\n', sectionName, NRun, round(parallelCtl.workersActive));
    end
    parfor run = 1:NRun
        runRec(run) = run_one_seed_531_(run, NP, MaxGen, Pc, Pm, Pe, T0, Tmin, alpha, STOP_BY_TMIN, G);
    end
else
    for run = 1:NRun
        if cfg_verbose
            fprintf('[%s] 运行 %d/%d (seed=%d)\n', sectionName, run, NRun, run);
        end
        runRec(run) = run_one_seed_531_(run, NP, MaxGen, Pc, Pm, Pe, T0, Tmin, alpha, STOP_BY_TMIN, G);
    end
end

if cfg_verbose && parallelCtl.enabled
    emit_parallel_logs_531_(sectionName, runRec, NRun, cfg_parallelLogLevel);
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
    [~,~,~,bestGlobal.detail] = fitness_strict_penalty(bestGlobal.ch, G);
else
    warning('[%s] NRun=%d 未找到严格可行解，回退 penalty 解用于表格/绘图（不造假）', sectionName, NRun);
    bestGlobal = bestGlobalPen;
    bestGlobal.isFeasible = false;
    [~,~,~,bestGlobal.detail] = fitness_strict_penalty(bestGlobal.ch, G);
end

if cfg_verbose
    fprintf('[%s] bestCost=%.6f | bestRun=%g | feasible=%d\n', sectionName, bestGlobal.cost, bestGlobal.run, double(bestGlobal.isFeasible));
end

% 表格
routeInfo = build_tables_from_detail(bestGlobal.detail, n, E, G.nCV);

statsRun = table((1:NRun)', feasCountInit, firstFeasibleGenRun, stopGenRun, foundFeasibleRun, bestFeasibleCostRun, ...
    'VariableNames', {'运行','初始严格可行','首次可行代','停止代','找到可行','最优可行成本'});

% 打印表格（由 SECTION531_PRINT_TABLES 控制）
if cfg_printTables
    disp('===== 表5.2(混合车队的物流配送方案) =====');
    disp(routeInfo.table52);
    disp('===== 表5.3(配送路径的各项成本) =====');
    disp(routeInfo.table53);
end

% 落盘 tables
t52Path = fullfile(paths.tables, artifact_filename('混合车队的物流配送方案', sectionName, modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.xlsx'));
t53Path = fullfile(paths.tables, artifact_filename('配送路径的各项成本', sectionName, modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.xlsx'));
rsPath  = fullfile(paths.tables, artifact_filename('运行统计', sectionName, modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.xlsx'));
try
    writetable(routeInfo.table52, t52Path);
    writetable(routeInfo.table53, t53Path);
    writetable(statsRun, rsPath);
catch
    t52Path = replace_ext_(t52Path, '.csv');
    t53Path = replace_ext_(t53Path, '.csv');
    rsPath  = replace_ext_(rsPath,  '.csv');
    writetable(routeInfo.table52, t52Path);
    writetable(routeInfo.table53, t53Path);
    writetable(statsRun, rsPath);
end

% 各节点位置图
try
    figNodes = plot_routes_with_labels(coord, n, E, struct([]), 'nodes', '各节点位置', G);
    apply_plot_style(figNodes, findall(figNodes,'Type','axes'), 'default');
    nodesPng = fullfile(paths.figures, artifact_filename('各节点位置', sectionName, modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.png'));
    export_figure(figNodes, nodesPng, 300);
    if ~cfg_keepFigures
        close(figNodes);
    end
catch
    nodesPng = '';
end

% 路径图
legendMode = legend_mode_for_fleet(G.nCV, G.nEV);
titleText = title_for_fleet(G.nCV, G.nEV);
fig = plot_routes_with_labels(coord, n, E, bestGlobal.detail, legendMode, titleText, G);
apply_plot_style(fig, findall(fig,'Type','axes'), 'default');
routePng = fullfile(paths.figures, artifact_filename(titleText, sectionName, modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.png'));
export_figure(fig, routePng, 300);
if ~cfg_keepFigures
    close(fig);
end

out = struct();
out.meta = struct('sectionName', sectionName, 'modeTag', modeTag, 'runTag', ctx.Meta.runTag, ...
    'timestamp', ctx.Meta.timestamp, 'paramSig', sig.param, 'dataSig', sig.data);
out.meta.features = {'baseline'};
out.paths = paths;
out.bestGlobal = bestGlobal;
out.routeInfo = routeInfo;
out.statsRun = statsRun;
out.artifacts = struct('table52', t52Path, 'table53', t53Path, 'runStats', rsPath, 'nodesPng', nodesPng, 'routePng', routePng);

% 将 out 保存到 mats（供 541/542 复用；不覆盖旧结果）
try
    outMat = fullfile(paths.mats, artifact_filename('out', sectionName, ctx.Meta.runTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.mat'));
    save(outMat, 'out');
    out.artifacts.outMat = outMat;
catch
end
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

function lv = normalize_parallel_log_level_531_(lvRaw)
lv = lower(strtrim(char(string(lvRaw))));
if ~any(strcmp(lv, {'none', 'summary', 'detailed'}))
    lv = 'detailed';
end
end

function ctl = resolve_parallel_control_(requested, workersRequested, nRun, cfg_verbose, sectionName)
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
        warning('run_section_531:parallelFallback', '[%s] 并行初始化失败，回退串行：%s', sectionName, ME.message);
    end
end
end

function rec = run_one_seed_531_(seed, NP, MaxGen, Pc, Pm, Pe, T0, Tmin, alpha, STOP_BY_TMIN, G)
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

function s = fmt_num_531_(v)
if ~isfinite(v)
    s = 'NA';
else
    s = sprintf('%.6f', v);
end
end

function emit_parallel_logs_531_(sectionName, runRec, nRun, logLevel)
if strcmp(logLevel, 'none')
    return;
end
for run = 1:nRun
    rec = runRec(run);
    if strcmp(logLevel, 'summary')
        fprintf('[%s][run %d/%d] seed=%d | feasible=%d | best=%s | stopGen=%s | elapsed=%ss\n', ...
            sectionName, run, nRun, round(rec.seed), double(rec.bestFeasibleFound), ...
            fmt_num_531_(rec.bestCost), fmt_num_531_(rec.stopGen), fmt_num_531_(rec.elapsedSec));
    else
        fprintf('[%s][run %d/%d] seed=%d\n', sectionName, run, nRun, round(rec.seed));
        fprintf('  [初始化] strictFeasible=%s | firstFeasibleGen=%s | stopGen=%s\n', ...
            fmt_num_531_(rec.initStrictFeasible), fmt_num_531_(rec.firstFeasibleGen), fmt_num_531_(rec.stopGen));
        fprintf('  [结果] feasible=%d | best=%s | penaltyBest=%s | elapsed=%ss\n', ...
            double(rec.bestFeasibleFound), fmt_num_531_(rec.bestCost), fmt_num_531_(rec.bestPenaltyCost), fmt_num_531_(rec.elapsedSec));
    end
end
end

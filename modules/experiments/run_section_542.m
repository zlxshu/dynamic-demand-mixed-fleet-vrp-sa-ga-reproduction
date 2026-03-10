function out = run_section_542(ctx)
% 修改日志
% - v6 2026-02-11: 修复 baseline 调度子函数未透传 cfg_parallelLogLevel 导致的未定义变量崩溃。
% - v5 2026-02-10: 新增 SECTION542_PARALLEL_LOG_LEVEL；并行模式下按 run 序输出顺序化详细日志（none/summary/detailed）。
% - v4 2026-02-09: 新增 SECTION542_PARALLEL_ENABLE/WORKERS；baseline 子求解支持 NRun 并行并改为有序摘要输出。
% - v2 2026-02-03: 清理未使用的调试变量
% - v3 2026-02-03: 从环境变量读取所有新增开关（由 run_modes.m 统一控制）
if nargin < 1 || isempty(ctx)
    error('section_542:missingCtx', 'run_section_542(ctx) 需要 ctx；请从 run_modes 运行，或直接调用 section_542()。');
end
sectionName = 'section_542';
modeTag = 'strategyCompare';

% ===== 从环境变量读取输出控制开关（由 run_modes.m 设置）=====
cfg_verbose = env_bool_or_default_('SECTION542_CONSOLE_VERBOSE', false);
cfg_keepFigures = env_bool_or_default_('SECTION542_KEEP_FIGURES', false);
cfg_printTables = env_bool_or_default_('SECTION542_PRINT_TABLES', false);
cfg_baseNCV = env_int_or_default_('SECTION542_BASE_NCV', 2);
cfg_baseNEV = env_int_or_default_('SECTION542_BASE_NEV', 2);
cfg_baselineMode = env_str_or_default_('SECTION542_BASELINE_MODE', 'paper_repro');
cfg_parallelEnable = env_bool_or_default_('SECTION542_PARALLEL_ENABLE', false);
cfg_parallelWorkers = env_int_or_default_('SECTION542_PARALLEL_WORKERS', 0);
cfg_parallelLogLevel = normalize_parallel_log_level_542_(env_str_or_default_('SECTION542_PARALLEL_LOG_LEVEL', 'detailed'));
% ============================================================

paths = output_paths(ctx.Meta.projectRoot, sectionName, ctx.Meta.runTag);
sig = build_signature(ctx);

modeLabel = '';
algoProfile = '';
try, modeLabel = char(string(ctx.Meta.modeLabel)); catch, end
try, algoProfile = char(string(ctx.Meta.algoProfile)); catch, end
if isempty(modeLabel), modeLabel = 'UNKNOWN'; end
if isempty(algoProfile), algoProfile = 'UNKNOWN'; end
if cfg_verbose
    fprintf('[%s] runTag=%s | modeLabel=%s | algoProfile=%s | modeTag=%s | paramSig=%s | dataSig=%s\n', ...
        sectionName, ctx.Meta.runTag, modeLabel, algoProfile, modeTag, sig.param.short, sig.data.short);
end

logPath = fullfile(paths.logs, artifact_filename('run', sectionName, modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.log'));
ensure_dir(paths.figures);
ensure_dir(paths.tables);
ensure_dir(paths.logs);
ensure_dir(paths.mats);

[out541, dynMatPath] = load_or_run_section_541_u_mat_(ctx, logPath);
dyn = load(dynMatPath);

dynInst = dyn.instanceNow;
dynPlan = dyn.planNow;
dynCfg = dyn.cfg;
dynSolve = dyn.solveInfo;
dynT = dyn.tNow;

baselineExtraEV = env_int_or_default_('SECTION542_BASELINE_MAX_EXTRAEV', 2);
baselineExtraCV = env_int_or_default_('SECTION542_BASELINE_MAX_EXTRACV', 0);
parallelCtl = resolve_parallel_control_542_(cfg_parallelEnable, cfg_parallelWorkers, ctx.SolverCfg.NRun, cfg_verbose, sectionName);
if cfg_verbose
    fprintf('[%s] baselineDispatchOnly: baseCV=%d baseEV=%d | maxExtraEV=%d maxExtraCV=%d | parallel=%d(workers=%d) | logLevel=%s | reason=%s\n', ...
        sectionName, cfg_baseNCV, cfg_baseNEV, round(baselineExtraEV), round(baselineExtraCV), ...
        double(parallelCtl.enabled), round(parallelCtl.workersActive), char(string(cfg_parallelLogLevel)), char(string(parallelCtl.reason)));
end

cfgNoDyn = dynCfg;
cfgNoDyn.Mode = 'paper_repro';
cfgNoDyn.Log = struct('logPath', logPath, 'printToConsole', false);
cfgNoDyn.Output = struct('keepFigures', false, 'printTables', false);
cfgNoDyn.CandidateFleet = struct('maxExtraCV', baselineExtraCV, 'maxExtraEV', baselineExtraEV);
if ~isfield(cfgNoDyn, 'Solver') || ~isstruct(cfgNoDyn.Solver)
    cfgNoDyn.Solver = struct();
end
if ~isfield(cfgNoDyn.Solver, 'warmStart')
    cfgNoDyn.Solver.warmStart = true;
end

baseCVNoDyn = cfg_baseNCV;
baseEVNoDyn = cfg_baseNEV;
[planNoDyn, solveNoDyn] = build_baseline_dispatch_only_542_(ctx, dynInst.Data, dynT, baseCVNoDyn, baseEVNoDyn, baselineExtraCV, baselineExtraEV, logPath, parallelCtl, cfg_verbose, cfg_parallelLogLevel);
baselinePolicy = 'dispatch_only_from_531';

[Gdyn, timelineDyn] = build_G_and_timeline_stub_(ctx, dynInst.Data, dynSolve.nCV, dynSolve.nEV);
sumDyn = simulate_timeline_summary_541(Gdyn, dynPlan.detail, dynCfg);
[dynRoutes, dynRates, dynLegNames] = used_routes_and_loadrates_ordered_542_(Gdyn, dynPlan, timelineDyn);

[Gno, timelineNoDyn] = build_G_and_timeline_stub_(ctx, dynInst.Data, solveNoDyn.nCV, solveNoDyn.nEV);
sumNo = simulate_timeline_summary_541(Gno, planNoDyn.detail, cfgNoDyn);
[noRoutes, noRates, noLegNames] = used_routes_and_loadrates_ordered_542_(Gno, planNoDyn, timelineNoDyn);
try solveNoDyn.bestCost = sumNo.totalCost; catch, end

try
    dup = audit_duplicate_customers_542_(planNoDyn, Gno.n);
    if ~isempty(dup)
        fprintf('[section_542] warning: baseline has duplicated customers across routes: %s\n', mat2str(dup));
    end
catch
end
if cfg_verbose
    try
        fprintf('[section_542] baseline routes (plot/table aligned order):\n');
        for i = 1:numel(noRoutes)
            fprintf('  - 路径%d: %s\n', i, route_to_str_(noRoutes{i}, Gno.n, Gno.E));
        end
    catch
    end
end

figNo = plot_routes_plain_542(dynInst, planNoDyn, timelineNoDyn);
try
    axList = findall(figNo, 'Type', 'axes');
    for ai = 1:numel(axList)
        try
            title(axList(ai), '不考虑动态需求的配送结果', 'Interpreter','none');
        catch
        end
    end
catch
end
fig514Path = fullfile(paths.figures, artifact_filename('不考虑动态需求的配送结果', sectionName, modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.png'));
export_figure(figNo, fig514Path, 300, struct('exportNoAxisLabels', true, 'exportNoTitle', false));

t516 = build_table_516_(Gdyn, dynRoutes, dynRates, noRoutes, noRates, dynLegNames, noLegNames);
t516Path = fullfile(paths.tables, artifact_filename('两种策略优化路径对比', sectionName, modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.xlsx'));
t516Path = write_table_xlsx_first_541(t516, t516Path, logPath);

t517 = build_table_517_(Gdyn, sumDyn, Gno, sumNo);
t517Path = fullfile(paths.tables, artifact_filename('两种策略优化结果对比', sectionName, modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.xlsx'));
t517Path = write_table_xlsx_first_541(t517, t517Path, logPath);

matOut = struct();
matOut.dynamic = struct('mat', dynMatPath, 'tNow', dynT, 'plan', dynPlan, 'solveInfo', dynSolve, 'summary', sumDyn);
matOut.noDynamic = struct('plan', planNoDyn, 'solveInfo', solveNoDyn, 'summary', sumNo, 'policy', baselinePolicy);
matOut.tables = struct('t516', {t516}, 't517', {t517});
matPath = fullfile(paths.mats, artifact_filename('result', sectionName, modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.mat'));
save(matPath, '-struct', 'matOut');

out = struct();
out.meta = struct('sectionName', sectionName, 'modeTag', modeTag, 'runTag', ctx.Meta.runTag, ...
    'timestamp', ctx.Meta.timestamp, 'paramSig', sig.param, 'dataSig', sig.data, 'features', struct());
out.paths = paths;
out.dep = struct('section_541', out541);
out.artifacts = struct('Fig5_14', fig514Path, 'Table5_16', t516Path, 'Table5_17', t517Path, 'Mat', matPath, 'Log', logPath);
end

function [planNoDyn, solveInfo] = build_baseline_dispatch_only_542_(ctx, dataFinal, snapshotTimeMin, baseCV, baseEV, extraCV, extraEV, logPath, parallelCtl, cfg_verbose, cfg_parallelLogLevel)
% === 论文 5.4.2 Baseline 策略对齐说明（paper_repro 严格对齐）===
%
% 论文原文（第7470-7472行）：
%   "对比实验在配送过程中不考虑动态化需求，也忽略需求处理间隔和需求上限等因素。
%    将动态需求作为已知的需求，加入原有的配送客户中。"
%
% 代码实现策略：
%   1. 初始路径来自 section_531（2CV+2EV，表5.7的4条路线）
%   2. 识别"待配送"客户（动态需求产生的 pending 客户）
%   3. 对 pending 客户使用额外 EV 进行追加优化
%
% 这种实现对应论文描述的"将动态需求作为已知需求，加入原有配送客户"的语义：
%   - "原有配送客户"= section_531 的初始路径
%   - "加入动态需求"= pending 客户追加优化
%   - 额外派车（论文图5.14：需要额外派出两辆电动汽车）
%
% 与"考虑动态优化"策略的关键差异：
%   - 本策略不考虑 T（时间间隔）和 q（需求上限）的批处理机制
%   - 初始路径固定不变，仅对新增需求追加调度
%   - 无法重新优化全局路径，导致车辆利用率降低（论文表5.16：76.47% vs 87.74%）
% ============================================
paths541 = output_paths(ctx.Meta.projectRoot, 'section_541', ctx.Meta.runTag);
ctxInit = ctx;
ctxInit.P.Fleet.nCV = baseCV;
ctxInit.P.Fleet.nEV = baseEV;
init = load_initial_plan_from_531_541(ctxInit, paths541);
try
    E = dataFinal.E;
catch
    E = ctxInit.Data.E;
end
try
    nOld = ctxInit.Data.n;
catch
    nOld = min(20, dataFinal.n);
end
init.detail = remap_detail_station_nodes_local_(init.detail, nOld, dataFinal.n, E);
try
    d = dataFinal.n - nOld;
    if isfinite(d) && d ~= 0
        fprintf('[section_542] remapInitStations: nOld=%d nNew=%d E=%d delta=%d\n', round(nOld), round(dataFinal.n), round(E), round(d));
    end
catch
end
try
    rCount = min(4, numel(init.detail));
    initRoutes = cell(rCount, 1);
    for ii = 1:rCount
        initRoutes{ii} = route_to_str_(init.detail(ii).route, dataFinal.n, E);
    end
catch
    initRoutes = {};
end

nCV = baseCV + extraCV;
nEV = baseEV + extraEV;
K = nCV + nEV;

detail = repmat(struct('route',[0 0],'startTimeMin',0), K, 1);
for k = 1:min(numel(init.detail), baseCV + baseEV)
    route = [0 0];
    try route = init.detail(k).route(:).'; catch, route = [0 0]; end
    route = route(isfinite(route));
    if isempty(route), route = [0 0]; end
    if route(1) ~= 0, route = [0 route]; end
    if route(end) ~= 0, route = [route 0]; end
    % NOTE: 保留原始路径，不移除已取消客户（算法真实逻辑）
    % 如果客户被取消（q=0），路径仍包含该节点，但配送量为0
    detail(k).route = route;
    try
        v = init.detail(k).startTimeMin;
        if isfinite(v), detail(k).startTimeMin = v; end
    catch
    end
end

used = [];
for k = 1:min(numel(init.detail), baseCV + baseEV)
    r = detail(k).route(:);
    used = [used; r(r>=1 & r<=dataFinal.n)]; %#ok<AGROW>
end
used = unique(used);
active = find(dataFinal.q(2:dataFinal.n+1) > 0);
pending = setdiff(active, used, 'stable');
inactiveInRoutes = [];
for k = 1:min(numel(init.detail), baseCV + baseEV)
    r = detail(k).route(:);
    r = r(isfinite(r));
    cus = r(r>=1 & r<=dataFinal.n);
    if isempty(cus)
        continue;
    end
    bad = cus(dataFinal.q(cus+1) <= 0);
    if ~isempty(bad)
        inactiveInRoutes = [inactiveInRoutes; bad(:)]; %#ok<AGROW>
    end
end
inactiveInRoutes = unique(inactiveInRoutes, 'stable');

if isempty(pending)
    % No pending customers, nothing to add
elseif extraEV <= 0
    try
        fid = fopen(logPath, 'a');
        if fid > 0
            c = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, '[section_542][baseline] skip pending optimization: pending=%d but extraEV=%d\n', numel(pending), round(extraEV));
        end
    catch
    end
else
    % Use GSAA to solve the pending customers subset (as a small static VRP)
    % using only extra EVs.
    % This is "Dispatch Only" with optimization for the new batch.

    try
        fid = fopen(logPath, 'a');
        if fid > 0
            fprintf(fid, '[section_542][baseline] optimizing pending customers with GSAA: %s\n', mat2str(pending));
            fclose(fid);
        end
    catch
    end

    % 1. Extract subset data
    % Map pending IDs (global) to 1..M (local)
    mapNewToOld = pending(:);
    M = numel(pending);

    % Construct subset Data
    subData = dataFinal;
    subData.n = M;
    % coord: Row 1 is Depot, Rows 2..M+1 are pending customers, then stations
    subData.coord = [dataFinal.coord(1,:); dataFinal.coord(pending+1,:); dataFinal.coord(dataFinal.n+2:end,:)];
    subData.q = [dataFinal.q(1); dataFinal.q(pending+1)]; % stations q is not used in q vector usually, or appended?
    % Check G.q usage: G.q is usually 1+(n)+...
    % In build_G_from_ctx, G.q is taken from ctx.Data.q.
    % Let's be careful. q usually includes depot(0) + customers(n). Stations are not in q.

    % 2. Setup ctx for sub-problem
    subCtx = ctx;
    subCtx.Data = subData;
    subCtx.P.Fleet.nCV = 0; % No CVs for extra dispatch
    subCtx.P.Fleet.nEV = extraEV; % Use available extra EVs

    % 3. Run GSAA on sub-problem
    [subPlan, ~] = solve_static_forced_use_all_542_(subCtx, parallelCtl, cfg_verbose, cfg_parallelLogLevel);

    % 4. Merge result back
    for i = 1:numel(subPlan.detail)
        % subPlan route uses 1..M. Need to map back to pending IDs.
        subRoute = subPlan.detail(i).route;

        % Map back
        finalRoute = [];
        for node = subRoute
            if node == 0
                finalRoute(end+1) = 0;
            elseif node >= 1 && node <= M
                finalRoute(end+1) = mapNewToOld(node);
            else
                % Stations: in subData, stations started at M+2.
                % In global Data, stations start at n+2.
                % But wait, subData.coord included stations at end.
                % GSAA treats nodes > M as stations.
                % We need to map station index.
                % In sub-problem, station 1 is node M+1? No, M+1 is M-th customer?
                % Node 1..M are customers. Node M+1..M+E are stations.
                % In global: Node n+1..n+E are stations.
                % So if node > M, it is a station.
                stationIdx = node - M;
                globalStationNode = dataFinal.n + stationIdx;
                finalRoute(end+1) = globalStationNode;
            end
        end

        % Assign to global detail
        % Append extra EV routes after the base fleet, preserving any extra CV slots.
        targetK = baseCV + baseEV + i;
        if targetK <= K
            detail(targetK).route = finalRoute;
            detail(targetK).startTimeMin = snapshotTimeMin;
        end
    end
end

planNoDyn = struct('detail', detail, 'nCV', nCV, 'nEV', nEV, 'fleetTag', sprintf('CV%d_EV%d', nCV, nEV));
[usedCV, usedEV] = used_fleet_counts_from_detail_542_(detail, nCV, nEV, dataFinal.n);
solveInfo = struct('nCV', nCV, 'nEV', nEV, 'usedCV', usedCV, 'usedEV', usedEV, 'bestCost', NaN, 'feasible', true);
routeStrings = cell(numel(detail), 1);
for k = 1:numel(detail)
    r = [];
    try r = detail(k).route(:).'; catch, r = []; end
    r = r(isfinite(r));
    if isempty(r)
        r = [0 0];
    end
    routeStrings{k} = route_to_str_(r, dataFinal.n, dataFinal.E);
end
try
    fid = fopen(logPath, 'a');
    if fid > 0
        c = onCleanup(@() fclose(fid));
        fprintf(fid, '[section_542][baseline] policy=dispatch_only_from_531 | base=CV%d_EV%d | extra=CV%d_EV%d | pending=%d | used=CV%d_EV%d\n', ...
            baseCV, baseEV, extraCV, extraEV, numel(pending), usedCV, usedEV);
    end
catch
end
end

function parts = split_pending_even_542_(pending, m)
parts = cell(max(0, round(m)), 1);
pending = pending(:).';
if isempty(parts) || isempty(pending)
    return;
end
for i = 1:numel(pending)
    j = mod(i-1, numel(parts)) + 1;
    parts{j} = [parts{j} pending(i)]; %#ok<AGROW>
end
end

function [usedCV, usedEV] = used_fleet_counts_from_detail_542_(detail, nCV, nEV, n)
usedCV = 0;
usedEV = 0;
K = numel(detail);
for k = 1:K
    r = [];
    try r = detail(k).route(:).'; catch, r = []; end
    r = r(isfinite(r));
    cus = r(r>=1 & r<=n);
    if isempty(cus)
        continue;
    end
    if k <= nCV
        usedCV = usedCV + 1;
    elseif k <= (nCV + nEV)
        usedEV = usedEV + 1;
    end
end
end

function [out541, dynMatPath] = load_or_run_section_541_u_mat_(ctx, logPath)
modeTag541 = strtrim(char(string(getenv('SECTION541_MODE'))));
if isempty(modeTag541)
    modeTag541 = 'paper_repro';
end

matsDir = fullfile(ctx.Meta.projectRoot, 'outputs', 'section_541', 'mats');
pattern = fullfile(matsDir, sprintf('u*_state_plan__section_541__%s__*.mat', modeTag541));
files = dir(pattern);
fileNames = {};
try
    fileNames = {files.name};
    if numel(fileNames) > 5
        fileNames = fileNames(1:5);
    end
catch
    fileNames = {};
end
if ~isempty(files)
    uIdx = NaN(numel(files), 1);
    for i = 1:numel(files)
        m = regexp(files(i).name, '^u(\d+)_state_plan__', 'tokens', 'once');
        if ~isempty(m)
            uIdx(i) = str2double(m{1});
        end
    end
    bestU = max(uIdx(isfinite(uIdx)));
    pick = find(uIdx == bestU);
    if isempty(pick)
        pick = 1:numel(files);
    end
    bestCost = inf;
    j = pick(1);
    for ii = 1:numel(pick)
        fp = fullfile(files(pick(ii)).folder, files(pick(ii)).name);
        try
            tmp = load(fp, 'solveInfo');
            if isfield(tmp, 'solveInfo') && isfield(tmp.solveInfo, 'bestCost') && isfinite(tmp.solveInfo.bestCost)
                c = double(tmp.solveInfo.bestCost);
            else
                c = inf;
            end
        catch
            c = inf;
        end
        if c < bestCost
            bestCost = c;
            j = pick(ii);
        end
    end
    dynMatPath = fullfile(files(j).folder, files(j).name);
    out541 = struct();
    out541.meta = struct('sectionName', 'section_541', 'modeTag', modeTag541, 'fromCache', true);
    out541.artifacts = struct('u00_mat', dynMatPath);
    return;
end

out541 = run_section_541(ctx);
dynMatPath = pick_latest_u_mat_from_out_541_(out541);
try
    if exist(logPath, 'file') == 2
        fid = fopen(logPath, 'a');
        if fid > 0
            fprintf(fid, '[section_542] section_541 cache miss -> rerun section_541\n');
            fclose(fid);
        end
    end
catch
end
end

function p = pick_latest_u_mat_from_out_541_(out541)
fns = fieldnames(out541.artifacts);
mats = {};
idx = [];
for i = 1:numel(fns)
    fn = fns{i};
    m = regexp(fn, '^u(\d+)_mat$', 'tokens', 'once');
    if isempty(m)
        continue;
    end
    mats{end+1,1} = out541.artifacts.(fn); %#ok<AGROW>
    idx(end+1,1) = str2double(m{1}); %#ok<AGROW>
end
if isempty(mats)
    error('section_542:noDynMat', 'cannot find u**_mat in section_541 out.artifacts');
end
[~, j] = max(idx);
p = mats{j};
end

function [ctxWork, baseCV, baseEV] = ctx_from_solve_info_(ctx, solveInfo)
baseCV = NaN;
baseEV = NaN;
try
    baseCV = solveInfo.nCV - solveInfo.extraCV;
    baseEV = solveInfo.nEV - solveInfo.extraEV;
catch
    baseCV = ctx.P.Fleet.nCV;
    baseEV = ctx.P.Fleet.nEV;
end
ctxWork = ctx;
if isfinite(baseCV) && baseCV >= 0
    ctxWork.P.Fleet.nCV = round(baseCV);
end
if isfinite(baseEV) && baseEV >= 0
    ctxWork.P.Fleet.nEV = round(baseEV);
end
baseCV = ctxWork.P.Fleet.nCV;
baseEV = ctxWork.P.Fleet.nEV;
end

function ctl = resolve_parallel_control_542_(requested, workersRequested, nRun, cfg_verbose, sectionName)
ctl = struct('requested', logical(requested), 'enabled', false, 'workersRequested', round(double(workersRequested)), ...
    'workersActive', 1, 'reason', 'parallel_disabled');
if ~ctl.requested
    ctl.reason = 'parallel_disabled';
    return;
end
if ~isfinite(nRun) || nRun <= 1
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
        warning('run_section_542:parallelFallback', '[%s] 并行初始化失败，回退串行：%s', sectionName, ME.message);
    end
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

function v = env_str_or_default_(name, def)
% 从环境变量读取字符串（由 run_modes.m 设置）
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

function state = build_fixed_state_no_dynamic_(instanceFinal, initDetail, baseCV, baseEV, tNow)
n = instanceFinal.Data.n;
q = instanceFinal.Data.q;
E = instanceFinal.Data.E;
Kbase = baseCV + baseEV;
vehicles = repmat(struct('k',0,'name','','isEV',false,'phase','not_started','stepIdx',NaN,'currentFromNode',0,'currentToNode',0,'currentNode',0, ...
    'batteryAtNowKWh',NaN,'frozenSeqIndex',1,'frozenNodes',[0],'pendingCustomers',[],'servedCustomers',[],'servedOrStartedCustomers',[], ...
    'frozenCustomers',[],'customerServiceStartMin',[],'customerServiceEndMin',[],'frozenEndTimeMin',tNow,'frozenEndBatteryKWh',NaN,'startTimeMin',tNow), Kbase, 1);

cvSlots = [1 2];
evSlots = [baseCV+1 baseCV+2];
for i = 1:min(2, numel(initDetail))
    k = cvSlots(i);
    route = initDetail(i).route;
    route = remap_station_nodes_if_needed_(route, n, E);
    route = sanitize_route_by_demand_(route, q, n);
    vehicles(k) = fill_fixed_vehicle_(vehicles(k), k, false, sprintf('CV%d', i), route, start_time_from_detail_or_default_(initDetail(i), 0), tNow, n);
end
for i = 1:2
    src = 2 + i;
    if src > numel(initDetail)
        break;
    end
    k = evSlots(i);
    route = initDetail(src).route;
    route = remap_station_nodes_if_needed_(route, n, E);
    route = sanitize_route_by_demand_(route, q, n);
    vehicles(k) = fill_fixed_vehicle_(vehicles(k), k, true, sprintf('EV%d', i), route, start_time_from_detail_or_default_(initDetail(src), 0), tNow, n);
end

frozenAll = [];
for k = 1:numel(vehicles)
    frozenAll = [frozenAll; vehicles(k).frozenCustomers(:)]; %#ok<AGROW>
end
state = struct();
state.tNow = tNow;
state.vehicles = vehicles;
state.servedCustomers = [];
state.servedOrStartedCustomers = unique(frozenAll(isfinite(frozenAll)));
state.frozenCustomers = unique(frozenAll(isfinite(frozenAll)));
state.customerServiceStartMin = [];
state.customerServiceEndMin = [];
end

function route = remap_station_nodes_if_needed_(route, nFinal, E)
route = route(:).';
route = route(isfinite(route));
nodes = route(route > 0);
if isempty(nodes)
    return;
end
n0 = min(20, nFinal);
delta = nFinal - n0;
if delta <= 0
    return;
end
for i = 1:numel(route)
    node = route(i);
    if node > n0 && node <= (n0 + E)
        route(i) = node + delta;
    end
end
end

function detail2 = remap_detail_station_nodes_local_(detail, nOld, nNew, E)
detail2 = detail;
delta = nNew - nOld;
if ~isfinite(delta) || delta == 0 || ~isfinite(E) || E <= 0
    return;
end
for k = 1:numel(detail2)
    if ~isfield(detail2(k),'route') || isempty(detail2(k).route)
        continue;
    end
    r = detail2(k).route(:).';
    mask = (r >= (nOld+1)) & (r <= (nOld+E));
    r(mask) = r(mask) + delta;
    detail2(k).route = r;
end
end

function t0 = start_time_from_detail_or_default_(d, def)
t0 = def;
try
    if isstruct(d) && isfield(d, 'startTimeMin') && isfinite(d.startTimeMin)
        t0 = d.startTimeMin;
        return;
    end
catch
end
end

function v = fill_fixed_vehicle_(v, k, isEV, name, route, startTimeMin, tNow, n)
v.k = k;
v.name = name;
v.isEV = isEV;
v.phase = 'done';
v.frozenNodes = route;
v.frozenSeqIndex = numel(route);
cus = route(route>=1 & route<=n);
cus = unique(cus(:), 'stable');
v.frozenCustomers = cus(:).';
v.servedOrStartedCustomers = v.frozenCustomers;
v.frozenEndTimeMin = tNow;
v.pendingCustomers = [];
v.customerServiceStartMin = [];
v.customerServiceEndMin = [];
v.batteryAtNowKWh = NaN;
v.frozenEndBatteryKWh = NaN;
v.startTimeMin = startTimeMin;
end

function route = sanitize_route_by_demand_(route, q, n)
if isempty(route)
    route = [0 0];
    return;
end
route = route(:).';
route = route(isfinite(route));
if isempty(route)
    route = [0 0];
    return;
end
if route(1) ~= 0
    route = [0 route];
end
if route(end) ~= 0
    route = [route 0];
end
keep = true(size(route));
for i = 1:numel(route)
    node = route(i);
    if node >= 1 && node <= n
        if q(node+1) <= 0
            keep(i) = false;
        end
    end
end
route = route(keep);
if route(1) ~= 0, route = [0 route]; end
if route(end) ~= 0, route = [route 0]; end
if numel(route) < 2
    route = [0 0];
end
end

function planPrev = build_plan_prev_from_fixed_state_(state, initDetail, baseCV, baseEV, nCV, nEV)
K = nCV + nEV;
planPrev = struct();
planPrev.detail = repmat(struct('route', [0 0], 'startTimeMin', state.tNow), K, 1);
for k = 1:numel(state.vehicles)
    planPrev.detail(k).route = state.vehicles(k).frozenNodes;
    try
        planPrev.detail(k).startTimeMin = state.vehicles(k).startTimeMin;
    catch
        planPrev.detail(k).startTimeMin = state.tNow;
    end
end
for i = 1:min(2, numel(initDetail))
    planPrev.detail(i).startTimeMin = start_time_from_detail_or_default_(initDetail(i), planPrev.detail(i).startTimeMin);
end
for i = 1:2
    src = 2 + i;
    if src > numel(initDetail)
        break;
    end
    k = baseCV + i;
    if k <= K
        planPrev.detail(k).startTimeMin = start_time_from_detail_or_default_(initDetail(src), planPrev.detail(k).startTimeMin);
    end
end
end

function fig = plot_routes_plain_542(instance, planNow, timelineNow)
n = instance.Data.n;
E = instance.Data.E;
coord = instance.Data.coord;
fig = figure('Color','w', 'WindowStyle','normal', 'Resize','on', 'NumberTitle','off'); hold on; box on;
try set(fig,'ToolBar','figure','MenuBar','figure'); catch, end

% Plot nodes (HandleVisibility off, labels in text)
hDepot = plot(coord(1,1), coord(1,2), 'r^', 'MarkerFaceColor','r', 'MarkerSize',10, 'HandleVisibility','off');
hCust = plot(coord(2:n+1,1), coord(2:n+1,2), 'bo', 'MarkerFaceColor','b', 'MarkerSize',5, 'HandleVisibility','off');
hStation = plot(coord(n+2:n+E+1,1), coord(n+2:n+E+1,2), 'gs', 'MarkerFaceColor','g', 'MarkerSize',8, 'HandleVisibility','off');

xy = coord(1:(n+E+1), :);
labels = strings(n+E+1, 1);
labels(1) = string(node_label_plot_542_(0,n,E));
for i = 1:n
    labels(i+1) = string(node_label_plot_542_(i,n,E));
end
for r = 1:E
    labels(n+r+1) = string(node_label_plot_542_(n+r,n,E));
end
fw = repmat("normal", n+E+1, 1);
fw(1) = "bold";
fw(n+2:n+E+1) = "bold";
fs = 8*ones(n+E+1, 1);
fs(1) = 9;

legH = [];
legL = {};

K = numel(planNow.detail);
names = strings(K,1);
for k = 1:K
    try names(k) = string(timelineNow.vehicles(k).name); catch, names(k) = "V"+k; end
end
order = vehicle_order_542_(names);

pathIdx = 0;
segs = zeros(0,4);
for oi = 1:numel(order)
    k = order(oi);
    if k > numel(planNow.detail)
        continue;
    end
    route = planNow.detail(k).route(:).';
    route = route(isfinite(route));
    if numel(route) < 2
        continue;
    end
    if any(route < 0) || any(route > (n+E))
        continue;
    end
    % Skip "no move" empty vehicles
    if numel(unique(route)) < 2
        continue;
    end

    vname = '';
    try vname = char(string(timelineNow.vehicles(k).name)); catch, vname = sprintf('V%d', k); end
    col = vehicle_color_542_(vname, k);

    xs = coord(route+1,1); ys = coord(route+1,2);
    % Main line
    plot(xs, ys, '-', 'Color', col, 'LineWidth', 2.2, 'HandleVisibility','off');
    if numel(xs) >= 2
        segs = [segs; [xs(1:end-1) ys(1:end-1) xs(2:end) ys(2:end)]]; %#ok<AGROW>
    end

    % Legend dummy
    pathIdx = pathIdx + 1;
    hLeg = plot(nan, nan, '-', 'Color', col, 'LineWidth', 2.2);
    hLeg.DisplayName = sprintf('路径%d', pathIdx);
    legH(end+1) = hLeg; %#ok<AGROW>
    legL{end+1} = hLeg.DisplayName; %#ok<AGROW>

end

place_labels_no_overlap(gca, xy, labels, struct('fontSize', fs, 'fontWeight', fw, 'backgroundColor', 'none', 'margin', 1, 'avoidSegments', segs));

if ~isempty(legH)
    legend(legH, legL, 'Location','bestoutside', 'Interpreter','none');
end
apply_plot_style(fig, findall(fig,'Type','axes'), 'default');
end

function c = vehicle_color_542_(name, fallbackIdx)
cols = [];
try
    if exist('turbo','file') == 2
        cols = turbo(12);
    end
catch
    cols = [];
end
if isempty(cols)
    cols = hsv(12);
end
t = upper(strtrim(char(string(name))));
idxNum = NaN;
if startsWith(t,'CV')
    idxNum = str2double(regexprep(t,'[^0-9]',''));
    if ~isfinite(idxNum), idxNum = fallbackIdx; end
    base = 1; span = 6;
    c = cols(base + mod(round(idxNum)-1, span), :);
    return;
end
if startsWith(t,'EV')
    idxNum = str2double(regexprep(t,'[^0-9]',''));
    if ~isfinite(idxNum), idxNum = fallbackIdx; end
    base = 7; span = 6;
    c = cols(base + mod(round(idxNum)-1, span), :);
    return;
end
if nargin < 2 || ~isfinite(fallbackIdx), fallbackIdx = 1; end
c = cols(mod(round(fallbackIdx)-1, size(cols,1)) + 1, :);
end

function order = vehicle_order_542_(names)
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

function label = node_label_plot_542_(node, n, E)
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

function [G, timeline] = build_G_and_timeline_stub_(ctx, data, nCV, nEV)
ctx2 = ctx;
ctx2.Data = data;
G = build_G_from_ctx(ctx2, 'nCV', nCV, 'nEV', nEV, 'AllowCharging', true, 'ForceChargeOnce', false, 'ForceChargePolicy', 'ANY_EV');
K = nCV + nEV;
vehicles = repmat(struct('name', '', 'isEV', false), K, 1);
for k = 1:K
    if k <= nCV
        vehicles(k).name = sprintf('CV%d', k);
        vehicles(k).isEV = false;
    else
        vehicles(k).name = sprintf('EV%d', k-nCV);
        vehicles(k).isEV = true;
    end
end
timeline = struct('vehicles', vehicles);
end

function [routes, ratesPct, legNames] = used_routes_and_loadrates_ordered_542_(G, plan, timeline)
routes = {};
ratesPct = [];
legNames = {};
if isempty(plan) || ~isfield(plan,'detail') || isempty(plan.detail)
    return;
end
K = numel(plan.detail);
names = strings(K, 1);
for k = 1:K
    try
        names(k) = string(timeline.vehicles(k).name);
    catch
        names(k) = "V" + k;
    end
end
order = vehicle_order_542_(names);
pathIdx = 0;
for oi = 1:numel(order)
    k = order(oi);
    if k > numel(plan.detail)
        continue;
    end
    route = [];
    try route = plan.detail(k).route(:).'; catch, route = []; end
    route = route(isfinite(route));
    if numel(route) < 2
        continue;
    end
    if any(route < 0) || any(route > (G.n + G.E))
        try
            fprintf('[section_542] warning: skip route with invalid node index (k=%d name=%s): %s\n', k, char(names(k)), mat2str(route));
        catch
        end
        continue;
    end
    if numel(unique(route)) < 2
        continue;
    end
    cus = route(route>=1 & route<=G.n);
    if isempty(cus)
        continue;
    end
    loadKg = sum(G.q(cus+1));
    cap = NaN;
    try cap = G.Qmax(k); catch, cap = NaN; end
    if ~isfinite(cap) || cap <= 0
        rate = NaN;
    else
        rate = 100 * loadKg / cap;
    end
    pathIdx = pathIdx + 1;
    routes{end+1,1} = route; %#ok<AGROW>
    ratesPct(end+1,1) = rate; %#ok<AGROW>
    % 论文表5.16格式：路径1(CV1)、路径2(CV2)、路径3(EV1) 等
    vehName = char(names(k));
    legNames{end+1,1} = sprintf('路径%d(%s)', pathIdx, vehName); %#ok<AGROW>
end
end

function dup = audit_duplicate_customers_542_(plan, n)
dup = [];
if isempty(plan) || ~isfield(plan,'detail') || isempty(plan.detail)
    return;
end
seen = false(n, 1);
for k = 1:numel(plan.detail)
    route = [];
    try route = plan.detail(k).route(:).'; catch, route = []; end
    route = route(isfinite(route));
    cus = unique(route(route>=1 & route<=n), 'stable');
    for i = 1:numel(cus)
        c = cus(i);
        if seen(c)
            dup(end+1,1) = c; %#ok<AGROW>
        else
            seen(c) = true;
        end
    end
end
dup = unique(dup, 'stable');
end

function t = build_table_516_(Gdyn, dynRoutes, dynRates, noRoutes, noRates, dynLegNames, noLegNames)
% === 论文表5.16 对齐说明 ===
% 表格格式：路径名(含车辆类型)、考虑动态优化路径、负载率、不考虑动态优化路径、负载率
% 路径命名如"路径1(CV1)"以便识别车辆类型
% ============================================
if nargin < 6, dynLegNames = {}; end
if nargin < 7, noLegNames = {}; end
n = max(numel(dynRoutes), numel(noRoutes));
t = cell(n + 2, 5);
t(1,:) = {'路径','考虑动态优化','负载率','不考虑动态优化','负载率'};
for i = 1:n
    % 优先使用包含车辆类型的名称
    if i <= numel(dynLegNames) && ~isempty(dynLegNames{i})
        t{i+1,1} = dynLegNames{i};
    elseif i <= numel(noLegNames) && ~isempty(noLegNames{i})
        t{i+1,1} = noLegNames{i};
    else
        t{i+1,1} = sprintf('路径%d', i);
    end
    if i <= numel(dynRoutes)
        t{i+1,2} = route_to_str_(dynRoutes{i}, Gdyn.n, Gdyn.E);
        t{i+1,3} = fmt_pct_(dynRates(i));
    else
        t{i+1,2} = '——';
        t{i+1,3} = '——';
    end
    if i <= numel(noRoutes)
        t{i+1,4} = route_to_str_(noRoutes{i}, Gdyn.n, Gdyn.E);
        t{i+1,5} = fmt_pct_(noRates(i));
    else
        t{i+1,4} = '——';
        t{i+1,5} = '——';
    end
end
t{n+2,1} = '平均负载率';
t{n+2,2} = '——';
t{n+2,3} = fmt_pct_(mean(dynRates, 'omitnan'));
t{n+2,4} = '——';
t{n+2,5} = fmt_pct_(mean(noRates, 'omitnan'));
end

function t = build_table_517_(Gdyn, sumDyn, Gno, sumNo)
t = cell(3, 6);
t(1,:) = {'策略','总成本(元)','碳排放量(kg)','能耗成本(元)','启动成本(元)','行驶里程(km)'};
t(2,:) = row_517_('考虑动态优化', Gdyn, sumDyn);
t(3,:) = row_517_('不考虑动态优化', Gno, sumNo);
end

function row = row_517_(name, G, s)
carbonKg = NaN;
try
    carbonKg = s.carbonCost / max(G.carbon_price, 1e-12);
catch
    carbonKg = NaN;
end
energyCost = NaN;
try
    energyCost = s.fuelCost + s.elecCost;
catch
    energyCost = NaN;
end
row = {name, round2_(s.totalCost, 2), round2_(carbonKg, 2), round2_(energyCost, 2), round2_(s.startCost, 2), round2_(s.distanceKm, 2)};
end

function s = route_to_str_(route, n, E)
if nargin < 3, E = 0; end
route = route(:).';
parts = strings(1, numel(route));
for i = 1:numel(route)
    node = route(i);
    if node == 0
        parts(i) = "0";
    elseif node >= 1 && node <= n
        parts(i) = string(node);
    elseif node > n && node <= (n + E)
        parts(i) = "R" + string(node - n);
    else
        parts(i) = string(node);
    end
end
s = char(strjoin(parts, "-"));
end

function s = fmt_pct_(v)
if ~isfinite(v)
    s = '——';
else
    s = sprintf('%.2f%%', v);
end
end

function y = round2_(x, nd)
if nargin < 2, nd = 2; end
if ~isfinite(x)
    y = x;
    return;
end
f = 10^nd;
y = round(x*f)/f;
end

function [plan, solveInfo] = solve_static_forced_use_all_542_(ctxNoDyn, parallelCtl, cfg_verbose, cfg_parallelLogLevel)
nCV = ctxNoDyn.P.Fleet.nCV;
nEV = ctxNoDyn.P.Fleet.nEV;
G = build_G_from_ctx(ctxNoDyn, ...
    'nCV', nCV, ...
    'nEV', nEV, ...
    'AllowCharging', true, ...
    'ForceChargeOnce', false, ...
    'ForceChargePolicy', 'ANY_EV');

NP = ctxNoDyn.SolverCfg.NP;
MaxGen = ctxNoDyn.SolverCfg.MaxGen;
Pc = ctxNoDyn.SolverCfg.Pc;
Pm = ctxNoDyn.SolverCfg.Pm;
Pe = ctxNoDyn.SolverCfg.Pe;
T0 = ctxNoDyn.SolverCfg.T0;
Tmin = ctxNoDyn.SolverCfg.Tmin;
alpha = ctxNoDyn.SolverCfg.alpha;
STOP_BY_TMIN = ctxNoDyn.SolverCfg.STOP_BY_TMIN;
NRun = ctxNoDyn.SolverCfg.NRun;
if ~isfinite(NRun) || NRun < 1
    NRun = 1;
end
cfg_parallelLogLevel = normalize_parallel_log_level_542_(cfg_parallelLogLevel);
useParallel = false;
try
    useParallel = logical(isstruct(parallelCtl) && isfield(parallelCtl,'enabled') && parallelCtl.enabled && NRun > 1);
catch
    useParallel = false;
end
try
    if ~isfield(G, 'opt') || ~isstruct(G.opt)
        G.opt = struct();
    end
    G.opt.consoleVerbose = logical(cfg_verbose && ~useParallel);
catch
end

bestFeaCost = inf;
bestFeaCh = [];
bestPenCost = inf;
bestPenCh = [];

runRec = repmat(struct('seed', NaN, 'feasible', false, 'cost', NaN, 'ch', [], 'penCost', inf, 'penCh', [], ...
    'initStrictFeasible', NaN, 'firstFeasibleGen', NaN, 'stopGen', NaN, 'elapsedSec', NaN), NRun, 1);
if useParallel
    parfor run = 1:NRun
        runRec(run) = run_one_seed_542_(run, NP, MaxGen, Pc, Pm, Pe, T0, Tmin, alpha, STOP_BY_TMIN, G);
    end
else
    for run = 1:NRun
        runRec(run) = run_one_seed_542_(run, NP, MaxGen, Pc, Pm, Pe, T0, Tmin, alpha, STOP_BY_TMIN, G);
    end
end

if cfg_verbose && useParallel
    emit_parallel_logs_542_(runRec, NRun, cfg_parallelLogLevel);
end

for run = 1:NRun
    if runRec(run).feasible && isfinite(runRec(run).cost) && runRec(run).cost < bestFeaCost
        bestFeaCost = runRec(run).cost;
        bestFeaCh = runRec(run).ch;
    end
    if isfinite(runRec(run).penCost) && runRec(run).penCost < bestPenCost
        bestPenCost = runRec(run).penCost;
        bestPenCh = runRec(run).penCh;
    end
end

if isfinite(bestFeaCost)
    bestCh = bestFeaCh;
    bestCost = bestFeaCost;
    isFeasible = true;
else
    bestCh = bestPenCh;
    bestCost = bestPenCost;
    isFeasible = false;
end

[~,~,~,detail] = fitness_strict_penalty(bestCh, G);
for k = 1:numel(detail)
    detail(k).startTimeMin = 0;
end
plan = struct('detail', detail);
solveInfo = struct('nCV', nCV, 'nEV', nEV, 'usedCV', nCV, 'usedEV', nEV, 'bestCost', bestCost, 'feasible', isFeasible);
end

function rec = run_one_seed_542_(seed, NP, MaxGen, Pc, Pm, Pe, T0, Tmin, alpha, STOP_BY_TMIN, G)
rng(seed, 'twister');
t0 = tic;
outRun = one_run_gsaa(NP, MaxGen, Pc, Pm, Pe, T0, Tmin, alpha, STOP_BY_TMIN, G);
rec = struct('seed', seed, 'feasible', false, 'cost', NaN, 'ch', [], 'penCost', inf, 'penCh', [], ...
    'initStrictFeasible', NaN, 'firstFeasibleGen', NaN, 'stopGen', NaN, 'elapsedSec', toc(t0));
if isfield(outRun, 'bestFeasibleFound') && outRun.bestFeasibleFound && isfinite(outRun.bestCost)
    rec.feasible = true;
    rec.cost = outRun.bestCost;
    rec.ch = outRun.bestCh;
end
if isfield(outRun, 'bestPenaltyCost') && isfinite(outRun.bestPenaltyCost)
    rec.penCost = outRun.bestPenaltyCost;
end
if isfield(outRun, 'bestPenaltyCh')
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
end

function s = fmt_num_542_(v)
if ~isfinite(v)
    s = 'NA';
else
    s = sprintf('%.6f', v);
end
end

function lv = normalize_parallel_log_level_542_(lvRaw)
lv = lower(strtrim(char(string(lvRaw))));
if ~any(strcmp(lv, {'none', 'summary', 'detailed'}))
    lv = 'detailed';
end
end

function emit_parallel_logs_542_(runRec, nRun, logLevel)
if strcmp(logLevel, 'none')
    return;
end
for run = 1:nRun
    rec = runRec(run);
    if strcmp(logLevel, 'summary')
        fprintf('[section_542][baseline][run %d/%d] seed=%d | feasible=%d | best=%s | stopGen=%s | elapsed=%ss\n', ...
            run, nRun, round(rec.seed), double(rec.feasible), fmt_num_542_(rec.cost), fmt_num_542_(rec.stopGen), fmt_num_542_(rec.elapsedSec));
    else
        fprintf('[section_542][baseline][run %d/%d] seed=%d\n', run, nRun, round(rec.seed));
        fprintf('  [初始化] strictFeasible=%s | firstFeasibleGen=%s | stopGen=%s\n', ...
            fmt_num_542_(rec.initStrictFeasible), fmt_num_542_(rec.firstFeasibleGen), fmt_num_542_(rec.stopGen));
        fprintf('  [结果] feasible=%d | best=%s | penaltyBest=%s | elapsed=%ss\n', ...
            double(rec.feasible), fmt_num_542_(rec.cost), fmt_num_542_(rec.penCost), fmt_num_542_(rec.elapsedSec));
    end
end
end

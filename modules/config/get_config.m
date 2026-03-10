function ctx = get_config(varargin)
% 修改日志
% - v1 2026-01-21: 新增全工程唯一参数入口 ctx（P/SolverCfg/Data/Meta），作为所有 section 的唯一真源。
% - v2 2026-01-21: 以 opt27.m 真源解析（opt27_constants）；ModeLabel 控制 PAPER/ENHANCED 口径；数据加载对齐 USE_INTERNAL_PAPER_DATA。
% - v3 2026-01-21: 参数真源改为“独立模块固化”(truth_baseline)，运行不再依赖 opt27.m；可选 VerifyOpt27 做对照核验（不影响默认真源）。
% - v4 2026-02-01: 透传 5.3.3 论文口径开关（点位/独立求解/论文曲线模式）。
% - v5 2026-02-02: 移除 PreferInternal 参数（内部数据已废除，强制使用 xlsx）。
% - v6 2026-02-02: 记录坐标缺失/距离矩阵 NaN（用于核对论文数据一致性）。

p = inputParser();
p.addParameter('RunTag', 'default', @(s) ischar(s) || isstring(s));
p.addParameter('ModeLabel', 'PAPER', @(s) ischar(s) || isstring(s));
p.addParameter('ForceRecompute', false, @(x) islogical(x) && isscalar(x));
p.addParameter('Opt27Path', '', @(s) ischar(s) || isstring(s));
p.addParameter('VerifyOpt27', false, @(x) islogical(x) && isscalar(x));
p.parse(varargin{:});
opt = p.Results;

projectRoot = project_root_dir();

% ===================== 0) 参数真源（固化模块） =====================
oc = truth_baseline();

modeLabel = upper(strtrim(char(string(opt.ModeLabel))));
if any(strcmp(modeLabel, {'PAPER','PAPER_STRICT','STRICT'}))
    paperMode = true;
elseif any(strcmp(modeLabel, {'ENHANCED','OPT27','BEST'}))
    paperMode = false;
else
    paperMode = logical(oc.Model.paperModeDefault);
end

P = struct();

% ---- EV 能量参数（单位明确） ----
P.EV = struct();
P.EV.B0_kWh   = oc.EV.B0_kWh;
P.EV.Bmin_kWh = oc.EV.Bmin_kWh;
P.EV.Bchg_kWh = oc.EV.Bchg_kWh;
P.EV.gE_kWh_per_km = oc.EV.gE_kWh_per_km;
P.EV.rg_kWh_per_h  = oc.EV.rg_kWh_per_h;

% ---- 价格/成本（单位明确） ----
P.Price = struct();
P.Price.elec_CNY_per_kWh     = oc.Price.elec_CNY_per_kWh;
P.Price.fuel_CNY_per_L       = oc.Price.fuel_CNY_per_L;
P.Price.carbon_CNY_per_kgCO2 = oc.Price.carbon_CNY_per_kgCO2;

% ---- 车队（速度单位明确；算法内部 Speed 为 km/min） ----
P.Fleet = struct();
P.Fleet.QCV = oc.Fleet.QCV;
P.Fleet.QEV = oc.Fleet.QEV;
P.Fleet.speed_km_per_h = oc.Fleet.speed_km_per_h;
P.Fleet.speed_km_per_min = oc.Fleet.speed_km_per_min;
P.Fleet.cCV = oc.Fleet.cCV;
P.Fleet.cEV = oc.Fleet.cEV;
P.Fleet.mCV = oc.Fleet.mCV;
P.Fleet.mEV = oc.Fleet.mEV;
P.Fleet.nCV = oc.Fleet.nCV;
P.Fleet.nEV = oc.Fleet.nEV;

% ---- 模型/运行开关（会进入 param_signature） ----
P.Model = struct();
P.Model.serviceTime_min = oc.Model.ST_min;
P.Model.allowCharging = true;
P.Model.forceChargeOnce = false;
P.Model.forceChargePolicy = 'ANY_EV';
P.Model.useReachableReserve = true;
P.Model.reserveE_mode = 'nearestStationOnly';
P.Model.visual2opt = logical(oc.Model.visual2opt);
P.Model.initInjectRatio = oc.Model.initInjectRatio;
P.Model.paperMode = logical(paperMode);

% ---- 算法选项（G.opt，以 opt27 为真源；PAPER 模式在此处做禁用） ----
P.Gopt = oc.Gopt;
if paperMode
    P.Gopt.enableEliteLS     = false;
    P.Gopt.crossTrials       = 0;
    P.Gopt.allowWorseLS      = false;
    P.Gopt.enableRelocate    = false;
    P.Gopt.enableSwap        = false;
    P.Gopt.enableImmigration = false;
    P.Gopt.enableKick        = false;

    if isfield(P.Gopt,'paperRepairSimplify') && P.Gopt.paperRepairSimplify
        P.Gopt.strongRepairProb        = 0.0;
        P.Gopt.secondRepairProb        = 0.0;
        P.Gopt.initSecondRepairProb    = 0.0;
        P.Gopt.heuristicRepairProb     = 1.0;
        P.Gopt.initHeuristicRepairProb = 1.0;
    end
end

% ---- CV-only 增强开关（仅在 nEV==0 时使用；仍计入 param_signature，避免跨口径缓存污染） ----
P.CVOnlyOpt = oc.CVOnlyOpt;

% ---- CMEM（用于 CV 油耗与碳排口径） ----
P.CMEM = oc.CMEM;

% ---- Section 默认配置（禁止 section 内硬编码；统一从 ctx 读取） ----
P.Section532 = struct();
if isfield(oc,'Section532') && isstruct(oc.Section532)
    P.Section532.custom_nCV = oc.Section532.custom_nCV;
    P.Section532.custom_nEV = oc.Section532.custom_nEV;
    tag = '';
    if isfield(oc.Section532,'custom_case_tag')
        tag = char(string(oc.Section532.custom_case_tag));
    end
    if isempty(tag)
        tag = sprintf('FLEET_%d_%d', round(P.Section532.custom_nCV), round(P.Section532.custom_nEV));
    end
    P.Section532.custom_case_tag = tag;
else
    P.Section532.custom_nCV = 3;
    P.Section532.custom_nEV = 0;
    P.Section532.custom_case_tag = 'FLEET_3_0';
end

P.Section533 = struct();
P.Section533.incPctVec = oc.Section533.incPctVec;
if isfield(oc.Section533, 'paperIndependent')
    P.Section533.paperIndependent = logical(oc.Section533.paperIndependent);
else
    P.Section533.paperIndependent = true;
end
if isfield(oc.Section533, 'paperLineMode')
    P.Section533.paperLineMode = char(string(oc.Section533.paperLineMode));
else
    P.Section533.paperLineMode = 'pointBest';
end

% ===================== 1) SolverCfg（统一 GA/SA 参数与开关） =====================
SolverCfg = struct();
SolverCfg.NP = oc.Solver.NP;
SolverCfg.MaxGen = oc.Solver.MaxGen;
SolverCfg.Pc = oc.Solver.Pc;
SolverCfg.Pm = oc.Solver.Pm;
SolverCfg.Pe = oc.Solver.Pe;
SolverCfg.T0 = oc.Solver.T0;
SolverCfg.alpha = oc.Solver.alpha;
SolverCfg.Tmin = oc.Solver.Tmin;
SolverCfg.STOP_BY_TMIN = logical(oc.Solver.STOP_BY_TMIN);
SolverCfg.NRun = oc.Solver.NRun;
SolverCfg.forceRecompute = logical(opt.ForceRecompute);

% ===================== 2) Data（统一数据入口与派生量） =====================
% 内部数据已废除，强制使用 xlsx 文件
[data, dataInfo] = load_data_auto('ProjectRoot', projectRoot);
coord = data(:, 1:2);
q = data(:, 3);
LT = data(:, 4);
RT = data(:, 5);
D = pairwise_dist_fast(coord);

Data = struct();
Data.raw = data;
Data.info = dataInfo;
Data.coord = coord;
Data.q = q;
Data.LT = LT;
Data.RT = RT;
Data.E = dataInfo.E;
Data.n = dataInfo.n;
Data.D = D;
Data.ST = P.Model.serviceTime_min;

% ===================== 3) Meta（可追溯信息） =====================
Meta = struct();
Meta.projectRoot = projectRoot;
Meta.timestamp = datestr(now, 'yyyymmddTHHMMSS');
Meta.runTag = char(string(opt.RunTag));
Meta.modeLabel = modeLabel;
Meta.pipelineVersion = 'unified_ctx_v3_truth_module';
try
    Meta.matlabRelease = version('-release');
catch
    Meta.matlabRelease = '';
end
if isfield(oc,'Source') && isstruct(oc.Source)
    Meta.truthSource = oc.Source;
else
    Meta.truthSource = struct('name','truth_baseline', 'found', true, 'path', '', 'message', '固化参数真源');
end

% 可选：对照 opt27.m（仅用于核验，不改变真源）
if opt.VerifyOpt27
    try
        ocOpt = opt27_constants('Opt27Path', opt.Opt27Path);
        diffs = compare_truth_(oc, ocOpt);
        if isempty(diffs)
            fprintf('[核验] 固化真源与 opt27 一致。\n');
        else
            fprintf('[核验] 固化真源与 opt27 存在差异（%d 项）：\n', numel(diffs));
            for i = 1:min(numel(diffs), 50)
                fprintf('  - %s\n', diffs{i});
            end
        end
    catch ME
        fprintf('[核验] opt27 对照失败（不影响运行）：%s\n', ME.message);
    end
end

% ===================== ctx =====================
ctx = struct();
ctx.P = P;
ctx.SolverCfg = SolverCfg;
ctx.Data = Data;
ctx.Meta = Meta;

ctx = assert_config(ctx);
end

function diffs = compare_truth_(a, b)
% compare_truth_ - 只比较“影响结果”的关键字段（用于 opt27 对照核验）
diffs = {};
diffs = [diffs; cmp_num_(a, b, 'EV.B0_kWh')]; %#ok<AGROW>
diffs = [diffs; cmp_num_(a, b, 'EV.Bmin_kWh')]; %#ok<AGROW>
diffs = [diffs; cmp_num_(a, b, 'EV.Bchg_kWh')]; %#ok<AGROW>
diffs = [diffs; cmp_num_(a, b, 'EV.gE_kWh_per_km')]; %#ok<AGROW>
diffs = [diffs; cmp_num_(a, b, 'EV.rg_kWh_per_h')]; %#ok<AGROW>
diffs = [diffs; cmp_num_(a, b, 'Price.elec_CNY_per_kWh')]; %#ok<AGROW>
diffs = [diffs; cmp_num_(a, b, 'Price.fuel_CNY_per_L')]; %#ok<AGROW>
diffs = [diffs; cmp_num_(a, b, 'Price.carbon_CNY_per_kgCO2')]; %#ok<AGROW>
diffs = [diffs; cmp_num_(a, b, 'Fleet.QCV')]; %#ok<AGROW>
diffs = [diffs; cmp_num_(a, b, 'Fleet.QEV')]; %#ok<AGROW>
diffs = [diffs; cmp_num_(a, b, 'Fleet.speed_km_per_h')]; %#ok<AGROW>
diffs = [diffs; cmp_num_(a, b, 'Fleet.cCV')]; %#ok<AGROW>
diffs = [diffs; cmp_num_(a, b, 'Fleet.cEV')]; %#ok<AGROW>
diffs = [diffs; cmp_num_(a, b, 'Fleet.mCV')]; %#ok<AGROW>
diffs = [diffs; cmp_num_(a, b, 'Fleet.mEV')]; %#ok<AGROW>
diffs = [diffs; cmp_num_(a, b, 'Fleet.nCV')]; %#ok<AGROW>
diffs = [diffs; cmp_num_(a, b, 'Fleet.nEV')]; %#ok<AGROW>
diffs = [diffs; cmp_num_(a, b, 'Model.ST_min')]; %#ok<AGROW>
diffs = [diffs; cmp_num_(a, b, 'Solver.NP')]; %#ok<AGROW>
diffs = [diffs; cmp_num_(a, b, 'Solver.MaxGen')]; %#ok<AGROW>
diffs = [diffs; cmp_num_(a, b, 'Solver.NRun')]; %#ok<AGROW>
diffs = diffs(~cellfun(@isempty, diffs));
end

function out = cmp_num_(a, b, path)
[va, okA] = get_path_(a, path);
[vb, okB] = get_path_(b, path);
if ~okA || ~okB
    out = sprintf('%s: 缺字段(模块=%d, opt27=%d)', path, okA, okB);
    return;
end
if isnumeric(va) && isnumeric(vb) && isscalar(va) && isscalar(vb)
    if ~(isfinite(va) && isfinite(vb) && abs(va - vb) < 1e-12)
        out = sprintf('%s: 模块=%g, opt27=%g', path, va, vb);
    else
        out = '';
    end
else
    out = '';
end
end

function [v, ok] = get_path_(s, path)
v = [];
ok = false;
try
    parts = strsplit(path, '.');
    v = s;
    for i = 1:numel(parts)
        if ~isstruct(v) || ~isfield(v, parts{i})
            ok = false;
            return;
        end
        v = v.(parts{i});
    end
    ok = true;
catch
    ok = false;
end
end

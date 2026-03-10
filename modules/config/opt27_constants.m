function oc = opt27_constants(varargin)
% 修改日志
% - v1 2026-01-21: 新增 opt27_constants：从 `opt27.m` 提取“唯一真源”参数（EV/价格/车队/算法/G.opt/CV-only/敏感性扫描向量）。
% - v2 2026-01-21: 补充解析 CMEM/Section532 等字段与字符串提取；解析失败则回退兜底并在 oc.Source 标记原因（避免静默口径漂移）。

    p = inputParser();
    p.addParameter('Opt27Path', '', @(s) ischar(s) || isstring(s));
    p.parse(varargin{:});
    opt = p.Results;

    projectRoot = project_root_dir();
    opt27Path = char(string(opt.Opt27Path));
    if isempty(opt27Path)
        opt27Path = fullfile(projectRoot, 'opt27.m');
    end

    oc = fallback_();
    oc.Source = struct('found', false, 'path', opt27Path, 'message', '');

    if exist(opt27Path, 'file') ~= 2
        oc.Source.message = 'opt27.m not found -> fallback';
        return;
    end

    txt = '';
    try
        txt = read_text_utf8_(opt27Path);
    catch ME
        oc.Source.message = sprintf('opt27.m read failed -> fallback: %s', ME.message);
        return;
    end

    oc.Source.found = true;
    oc.Source.message = 'parsed';

    % ===== 数据源开关 =====
    oc.Data.useInternal = extract_bool_(txt, '^\\s*USE_INTERNAL_PAPER_DATA\\s*=\\s*(true|false)\\s*;', oc.Data.useInternal);

    % ===== 基础车队与模型 =====
    oc.Fleet.nCV = extract_int_(txt, '\\bnCV\\s*=\\s*(\\d+)\\s*;', oc.Fleet.nCV);
    oc.Fleet.nEV = extract_int_(txt, '\\bnEV\\s*=\\s*(\\d+)\\s*;', oc.Fleet.nEV);
    oc.Fleet.QCV = extract_num_(txt, '^\\s*QCV\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.Fleet.QCV);
    oc.Fleet.QEV = extract_num_(txt, '^\\s*QEV\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.Fleet.QEV);
    oc.Model.ST_min = extract_num_(txt, '^\\s*ST\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.Model.ST_min);

    [speedMin, speedH] = extract_speed_(txt, oc.Fleet.speed_km_per_min);
    oc.Fleet.speed_km_per_min = speedMin;
    oc.Fleet.speed_km_per_h = speedH;

    % c/m（从向量构造式提取）
    [cCV, cEV] = extract_two_from_vec_(txt, '^\\s*c\\s*=\\s*\\[(?<a>[0-9eE+\\-\\.]+)\\*ones\\(1,nCV\\)\\s*,\\s*(?<b>[0-9eE+\\-\\.]+)\\*ones\\(1,nEV\\)\\s*\\]\\s*;', oc.Fleet.cCV, oc.Fleet.cEV);
    [mCV, mEV] = extract_two_from_vec_(txt, '^\\s*m\\s*=\\s*\\[(?<a>[0-9eE+\\-\\.]+)\\*ones\\(1,nCV\\)\\s*,\\s*(?<b>[0-9eE+\\-\\.]+)\\*ones\\(1,nEV\\)\\s*\\]\\s*;', oc.Fleet.mCV, oc.Fleet.mEV);
    oc.Fleet.cCV = cCV; oc.Fleet.cEV = cEV;
    oc.Fleet.mCV = mCV; oc.Fleet.mEV = mEV;

    % ===== EV 参数 =====
    oc.EV.B0_kWh = extract_num_(txt, '^\\s*B0\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.EV.B0_kWh);
    oc.EV.Bmin_kWh = extract_num_(txt, '^\\s*Bmin\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.EV.Bmin_kWh);
    oc.EV.Bchg_kWh = extract_num_(txt, '^\\s*Bchg\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.EV.Bchg_kWh);
    oc.EV.gE_kWh_per_km = extract_num_(txt, '^\\s*gE\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.EV.gE_kWh_per_km);
    oc.EV.rg_kWh_per_h = extract_num_(txt, '^\\s*rg\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.EV.rg_kWh_per_h);

    % ===== 价格/排放 =====
    oc.Price.fuel_CNY_per_L = extract_num_(txt, '^\\s*fuel_price\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.Price.fuel_CNY_per_L);
    oc.Price.elec_CNY_per_kWh = extract_num_(txt, '^\\s*elec_price\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.Price.elec_CNY_per_kWh);
    oc.Price.carbon_CNY_per_kgCO2 = extract_num_(txt, '^\\s*carbon_price\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.Price.carbon_CNY_per_kgCO2);
    oc.Price.eCO2_kg_per_L = extract_num_(txt, '^\\s*emission_factor\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.Price.eCO2_kg_per_L);

    % ===== CMEM（论文表5.1，CV 油耗/碳排口径） =====
    oc.CMEM.mu = extract_num_(txt, '^\\s*CMEM\\.mu\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.CMEM.mu);
    oc.CMEM.phi = extract_num_(txt, '^\\s*CMEM\\.phi\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.CMEM.phi);
    oc.CMEM.lam = extract_num_(txt, '^\\s*CMEM\\.lam\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.CMEM.lam);
    oc.CMEM.H = extract_num_(txt, '^\\s*CMEM\\.H\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.CMEM.H);
    oc.CMEM.V = extract_num_(txt, '^\\s*CMEM\\.V\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.CMEM.V);
    oc.CMEM.eta = extract_num_(txt, '^\\s*CMEM\\.eta\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.CMEM.eta);
    oc.CMEM.eps = extract_num_(txt, '^\\s*CMEM\\.eps\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.CMEM.eps);
    oc.CMEM.zeta = extract_num_(txt, '^\\s*CMEM\\.zeta\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.CMEM.zeta);
    oc.CMEM.eCO2 = extract_num_(txt, '^\\s*CMEM\\.eCO2\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.CMEM.eCO2);
    oc.CMEM.rho_air = extract_num_(txt, '^\\s*CMEM\\.rho_air\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.CMEM.rho_air);
    oc.CMEM.Cr = extract_num_(txt, '^\\s*CMEM\\.Cr\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.CMEM.Cr);
    oc.CMEM.CdA = extract_num_(txt, '^\\s*CMEM\\.CdA\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.CMEM.CdA);
    oc.CMEM.m_empty = extract_num_(txt, '^\\s*CMEM\\.m_empty\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.CMEM.m_empty);
    oc.CMEM.rho_fuel = extract_num_(txt, '^\\s*CMEM\\.rho_fuel\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.CMEM.rho_fuel);

    % ===== 求解器参数 =====
    oc.Solver.NP = extract_int_(txt, '^\\s*NP\\s*=\\s*(\\d+)\\s*;', oc.Solver.NP);
    oc.Solver.MaxGen = extract_int_(txt, '^\\s*MaxGen\\s*=\\s*(\\d+)\\s*;', oc.Solver.MaxGen);
    oc.Solver.Pc = extract_num_(txt, '^\\s*Pc\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.Solver.Pc);
    oc.Solver.Pm = extract_num_(txt, '^\\s*Pm\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.Solver.Pm);
    oc.Solver.Pe = extract_num_(txt, '^\\s*Pe\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.Solver.Pe);
    oc.Solver.T0 = extract_num_(txt, '^\\s*T0\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.Solver.T0);
    oc.Solver.Tmin = extract_num_(txt, '^\\s*Tmin\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.Solver.Tmin);
    oc.Solver.alpha = extract_num_(txt, '^\\s*alpha\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.Solver.alpha);
    oc.Solver.STOP_BY_TMIN = extract_bool_(txt, '^\\s*STOP_BY_TMIN\\s*=\\s*(true|false)\\s*;', oc.Solver.STOP_BY_TMIN);
    oc.Solver.NRun = extract_int_(txt, '^\\s*NRun\\s*=\\s*(\\d+)\\s*;', oc.Solver.NRun);

    % ===== 模式与注入比例 =====
    oc.Model.paperModeDefault = extract_bool_(txt, '^\\s*G\\.paperMode\\s*=\\s*(true|false)\\s*;', oc.Model.paperModeDefault);
    oc.Model.initInjectRatio = extract_num_(txt, '^\\s*G\\.initInjectRatio\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.Model.initInjectRatio);
    oc.Model.visual2opt = extract_bool_(txt, '^\\s*G\\.visual2opt\\s*=\\s*(true|false)\\s*;', oc.Model.visual2opt);

    % ===== G.opt（基线值；PAPER_STRICT 的禁用逻辑由 get_config 应用）=====
    oc.Gopt.paperRepairSimplify = extract_bool_(txt, '^\\s*G\\.opt\\.paperRepairSimplify\\s*=\\s*(true|false)\\s*;', oc.Gopt.paperRepairSimplify);
    oc.Gopt.enableEliteLS = extract_bool_(txt, '^\\s*G\\.opt\\.enableEliteLS\\s*=\\s*(true|false)\\s*;', oc.Gopt.enableEliteLS);
    oc.Gopt.eliteTopN = extract_int_(txt, '^\\s*G\\.opt\\.eliteTopN\\s*=\\s*(\\d+)\\s*;', oc.Gopt.eliteTopN);
    oc.Gopt.ls2optIter = extract_int_(txt, '^\\s*G\\.opt\\.ls2optIter\\s*=\\s*(\\d+)\\s*;', oc.Gopt.ls2optIter);
    oc.Gopt.lsOrOptTrials = extract_int_(txt, '^\\s*G\\.opt\\.lsOrOptTrials\\s*=\\s*(\\d+)\\s*;', oc.Gopt.lsOrOptTrials);
    oc.Gopt.crossTrials = extract_int_(txt, '^\\s*G\\.opt\\.crossTrials\\s*=\\s*(\\d+)\\s*;', oc.Gopt.crossTrials);
    oc.Gopt.allowWorseLS = extract_bool_(txt, '^\\s*G\\.opt\\.allowWorseLS\\s*=\\s*(true|false)\\s*;', oc.Gopt.allowWorseLS);
    oc.Gopt.enableRelocate = extract_bool_(txt, '^\\s*G\\.opt\\.enableRelocate\\s*=\\s*(true|false)\\s*;', oc.Gopt.enableRelocate);
    oc.Gopt.enableSwap = extract_bool_(txt, '^\\s*G\\.opt\\.enableSwap\\s*=\\s*(true|false)\\s*;', oc.Gopt.enableSwap);
    oc.Gopt.heuristicRepairProb = extract_num_(txt, '^\\s*G\\.opt\\.heuristicRepairProb\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.Gopt.heuristicRepairProb);
    oc.Gopt.strongRepairProb = extract_num_(txt, '^\\s*G\\.opt\\.strongRepairProb\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.Gopt.strongRepairProb);
    oc.Gopt.secondRepairProb = extract_num_(txt, '^\\s*G\\.opt\\.secondRepairProb\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.Gopt.secondRepairProb);
    oc.Gopt.initHeuristicRepairProb = extract_num_(txt, '^\\s*G\\.opt\\.initHeuristicRepairProb\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.Gopt.initHeuristicRepairProb);
    oc.Gopt.initSecondRepairProb = extract_num_(txt, '^\\s*G\\.opt\\.initSecondRepairProb\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.Gopt.initSecondRepairProb);
    oc.Gopt.enableImmigration = extract_bool_(txt, '^\\s*G\\.opt\\.enableImmigration\\s*=\\s*(true|false)\\s*;', oc.Gopt.enableImmigration);
    oc.Gopt.immigrationPeriod = extract_int_(txt, '^\\s*G\\.opt\\.immigrationPeriod\\s*=\\s*(\\d+)\\s*;', oc.Gopt.immigrationPeriod);
    oc.Gopt.immigrationRatio = extract_num_(txt, '^\\s*G\\.opt\\.immigrationRatio\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.Gopt.immigrationRatio);
    oc.Gopt.enableKick = extract_bool_(txt, '^\\s*G\\.opt\\.enableKick\\s*=\\s*(true|false)\\s*;', oc.Gopt.enableKick);
    oc.Gopt.stagnationGen = extract_int_(txt, '^\\s*G\\.opt\\.stagnationGen\\s*=\\s*(\\d+)\\s*;', oc.Gopt.stagnationGen);
    oc.Gopt.kickProb = extract_num_(txt, '^\\s*G\\.opt\\.kickProb\\s*=\\s*([0-9eE+\\-\\.]+)\\s*;', oc.Gopt.kickProb);
    oc.Gopt.kickStrength = extract_int_(txt, '^\\s*G\\.opt\\.kickStrength\\s*=\\s*(\\d+)\\s*;', oc.Gopt.kickStrength);

    % ===== CV-only 增强 =====
    oc.CVOnlyOpt.enableCVOnlyImprove = extract_bool_(txt, '^\\s*G\\.cvOnlyOpt\\.enableCVOnlyImprove\\s*=\\s*(true|false)\\s*;', oc.CVOnlyOpt.enableCVOnlyImprove);
    oc.CVOnlyOpt.enableSAFitnessAccept = extract_bool_(txt, '^\\s*G\\.cvOnlyOpt\\.enableSAFitnessAccept\\s*=\\s*(true|false)\\s*;', oc.CVOnlyOpt.enableSAFitnessAccept);
    oc.CVOnlyOpt.maxIter2optCVOnly = extract_int_(txt, '^\\s*G\\.cvOnlyOpt\\.maxIter2optCVOnly\\s*=\\s*(\\d+)\\s*;', oc.CVOnlyOpt.maxIter2optCVOnly);
    oc.CVOnlyOpt.cvOnlyCrossIters = extract_int_(txt, '^\\s*G\\.cvOnlyOpt\\.cvOnlyCrossIters\\s*=\\s*(\\d+)\\s*;', oc.CVOnlyOpt.cvOnlyCrossIters);
    oc.CVOnlyOpt.crossDetMaxEvals = extract_int_(txt, '^\\s*G\\.cvOnlyOpt\\.crossDetMaxEvals\\s*=\\s*(\\d+)\\s*;', oc.CVOnlyOpt.crossDetMaxEvals);
    oc.CVOnlyOpt.initCapacityFix = extract_bool_(txt, '^\\s*G\\.cvOnlyOpt\\.initCapacityFix\\s*=\\s*(true|false)\\s*;', oc.CVOnlyOpt.initCapacityFix);
    oc.CVOnlyOpt.seed2optIter = extract_int_(txt, '^\\s*G\\.cvOnlyOpt\\.seed2optIter\\s*=\\s*(\\d+)\\s*;', oc.CVOnlyOpt.seed2optIter);
    oc.CVOnlyOpt.lnsIters = extract_int_(txt, '^\\s*G\\.cvOnlyOpt\\.lnsIters\\s*=\\s*(\\d+)\\s*;', oc.CVOnlyOpt.lnsIters);
    oc.CVOnlyOpt.lnsDestroyMin = extract_int_(txt, '^\\s*G\\.cvOnlyOpt\\.lnsDestroyMin\\s*=\\s*(\\d+)\\s*;', oc.CVOnlyOpt.lnsDestroyMin);
    oc.CVOnlyOpt.lnsDestroyMax = extract_int_(txt, '^\\s*G\\.cvOnlyOpt\\.lnsDestroyMax\\s*=\\s*(\\d+)\\s*;', oc.CVOnlyOpt.lnsDestroyMax);
    oc.CVOnlyOpt.chainIters = extract_int_(txt, '^\\s*G\\.cvOnlyOpt\\.chainIters\\s*=\\s*(\\d+)\\s*;', oc.CVOnlyOpt.chainIters);
    oc.CVOnlyOpt.chainLenMin = extract_int_(txt, '^\\s*G\\.cvOnlyOpt\\.chainLenMin\\s*=\\s*(\\d+)\\s*;', oc.CVOnlyOpt.chainLenMin);
    oc.CVOnlyOpt.chainLenMax = extract_int_(txt, '^\\s*G\\.cvOnlyOpt\\.chainLenMax\\s*=\\s*(\\d+)\\s*;', oc.CVOnlyOpt.chainLenMax);
    oc.CVOnlyOpt.injectCount = min(10, floor(oc.Solver.NP/5));

    % ===== 5.3.2 自定义车队（论文表5.5） =====
    oc.Section532.custom_nCV = extract_int_(txt, '^\\s*CUSTOM_NCV\\s*=\\s*(\\d+)\\s*;', oc.Section532.custom_nCV);
    oc.Section532.custom_nEV = extract_int_(txt, '^\\s*CUSTOM_NEV\\s*=\\s*(\\d+)\\s*;', oc.Section532.custom_nEV);
    oc.Section532.custom_case_tag = extract_string_(txt, '^\\s*CUSTOM_CASE_TAG\\s*=\\s*''(?<v>[^'']*)''\\s*;', oc.Section532.custom_case_tag);

    % ===== 5.3.3 增量向量 =====
    oc.Section533.incPctVec = extract_num_vec_(txt, '^\\s*INC_VEC_533\\s*=\\s*\\[(?<v>[^\\]]+)\\]\\s*;', oc.Section533.incPctVec);
end

% ===================== helpers =====================
function oc = fallback_()
oc = struct();
oc.EV = struct('B0_kWh', 100, 'Bmin_kWh', 0, 'Bchg_kWh', 100, 'gE_kWh_per_km', 1.0, 'rg_kWh_per_h', 100);
oc.Price = struct('elec_CNY_per_kWh', 0.8, 'fuel_CNY_per_L', 7.5, 'carbon_CNY_per_kgCO2', 0.1, 'eCO2_kg_per_L', 3.09);
oc.Fleet = struct('nCV', 2, 'nEV', 2, 'QCV', 1500, 'QEV', 1000, ...
    'speed_km_per_h', 40, 'speed_km_per_min', 40/60, 'cCV', 100, 'cEV', 200, 'mCV', 20, 'mEV', 10);
oc.CMEM = struct('mu',44,'phi',1,'lam',0.2,'H',35,'V',5,'eta',0.9,'eps',0.4,'zeta',737,'eCO2',3.09, ...
    'rho_air',1.225,'Cr',0.010,'CdA',3.0,'m_empty',3000,'rho_fuel',0.84);
oc.Model = struct('ST_min', 20, 'paperModeDefault', false, 'initInjectRatio', 0.0, 'visual2opt', true);
oc.Solver = struct('NP', 200, 'MaxGen', 300, 'Pc', 0.9, 'Pm', 0.1, 'Pe', 0, 'T0', 500, 'Tmin', 0.01, 'alpha', 0.95, 'STOP_BY_TMIN', true, 'NRun', 10);
oc.Gopt = struct( ...
    'paperRepairSimplify', false, ...
    'enableEliteLS', true, ...
    'eliteTopN', 8, ...
    'ls2optIter', 25, ...
    'lsOrOptTrials', 20, ...
    'crossTrials', 10, ...
    'allowWorseLS', true, ...
    'enableRelocate', true, ...
    'enableSwap', true, ...
    'heuristicRepairProb', 0.70, ...
    'strongRepairProb', 0.08, ...
    'secondRepairProb', 0.55, ...
    'initHeuristicRepairProb', 0.85, ...
    'initSecondRepairProb', 0.90, ...
    'enableImmigration', true, ...
    'immigrationPeriod', 25, ...
    'immigrationRatio', 0.05, ...
    'enableKick', true, ...
    'stagnationGen', 35, ...
    'kickProb', 0.30, ...
    'kickStrength', 3 ...
    );
oc.CVOnlyOpt = struct('enableCVOnlyImprove', true, 'enableSAFitnessAccept', true, 'maxIter2optCVOnly', 2000, ...
    'cvOnlyCrossIters', 1000, 'crossDetMaxEvals', 8000, 'injectCount', min(10, floor(200/5)), 'initCapacityFix', true, ...
    'seed2optIter', 200, 'lnsIters', 120, 'lnsDestroyMin', 3, 'lnsDestroyMax', 7, 'chainIters', 120, 'chainLenMin', 2, 'chainLenMax', 4);
oc.Section532 = struct('custom_nCV', 3, 'custom_nEV', 0, 'custom_case_tag', '');
oc.Section533 = struct('incPctVec', [0 20 40 60 80 100]);
oc.Data = struct('useInternal', true);
end

function txt = read_text_utf8_(p)
fid = fopen(p, 'r', 'n', 'UTF-8');
if fid < 0
    error('opt27_constants:openFailed', 'cannot open: %s', p);
end
cleanup = onCleanup(@() fclose(fid));
txt = fread(fid, '*char')';
end

function v = extract_num_(txt, pat, fallback)
m = regexp(txt, ['(?m)' pat], 'tokens', 'once');
if isempty(m), v = fallback; return; end
v = str2double(m{1});
if ~isfinite(v), v = fallback; end
end

function v = extract_int_(txt, pat, fallback)
v = round(extract_num_(txt, pat, fallback));
end

function v = extract_bool_(txt, pat, fallback)
m = regexp(txt, ['(?m)' pat], 'tokens', 'once');
if isempty(m), v = fallback; return; end
s = lower(strtrim(m{1}));
if strcmp(s,'true'), v = true;
elseif strcmp(s,'false'), v = false;
else, v = fallback;
end
end

function s = extract_string_(txt, pat, fallback)
m = regexp(txt, ['(?m)' pat], 'names', 'once');
if isempty(m)
    s = fallback;
    return;
end
if isfield(m,'v')
    s = m.v;
else
    s = fallback;
end
end

function [a, b] = extract_two_from_vec_(txt, pat, fa, fb)
m = regexp(txt, ['(?m)' pat], 'names', 'once');
if isempty(m)
    a = fa; b = fb; return;
end
a = str2double(m.a); b = str2double(m.b);
if ~isfinite(a), a = fa; end
if ~isfinite(b), b = fb; end
end

function [speed_km_per_min, speed_km_per_h] = extract_speed_(txt, fallbackSpeedMin)
speed_km_per_min = fallbackSpeedMin;
speed_km_per_h = speed_km_per_min * 60;

% Speed = (40/60) * ones(1,K)
m = regexp(txt, '(?m)^\\s*Speed\\s*=\\s*\\((?<num>[0-9eE+\\-\\.]+)\\s*/\\s*(?<den>[0-9eE+\\-\\.]+)\\)\\s*\\*\\s*ones\\(1,K\\)\\s*;', 'names', 'once');
if ~isempty(m)
    num = str2double(m.num);
    den = str2double(m.den);
    if isfinite(num) && isfinite(den) && den ~= 0
        speed_km_per_min = num / den;
        speed_km_per_h = speed_km_per_min * 60;
        return;
    end
end

% Speed = 0.6667 * ones(1,K)
m = regexp(txt, '(?m)^\\s*Speed\\s*=\\s*(?<v>[0-9eE+\\-\\.]+)\\s*\\*\\s*ones\\(1,K\\)\\s*;', 'names', 'once');
if ~isempty(m)
    v = str2double(m.v);
    if isfinite(v)
        speed_km_per_min = v;
        speed_km_per_h = v * 60;
    end
end
end

function v = extract_num_vec_(txt, pat, fallback)
m = regexp(txt, ['(?m)' pat], 'names', 'once');
if isempty(m)
    v = fallback;
    return;
end
raw = strtrim(m.v);
raw = regexprep(raw, '[,;]', ' ');
nums = regexp(raw, '[-+]?\\d*\\.?\\d+(?:[eE][-+]?\\d+)?', 'match');
if isempty(nums)
    v = fallback;
    return;
end
v = cellfun(@str2double, nums);
if any(~isfinite(v))
    v = fallback;
end
end

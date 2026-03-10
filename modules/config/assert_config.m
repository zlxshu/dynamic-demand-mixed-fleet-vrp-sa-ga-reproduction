function ctx = assert_config(ctx)
% 修改日志
% - v1 2026-01-21: 新增 assert_config(ctx)；缺字段/NaN/单位冲突直接报错，防止口径漂移与缓存污染。
% - v1 2026-01-21: 自动补齐派生字段（如 CV-only injectCount 依赖 NP）。

    requiredTop = {'P','SolverCfg','Data','Meta'};
    for i = 1:numel(requiredTop)
        if ~isfield(ctx, requiredTop{i})
            error('assert_config:missingTop', 'ctx 缺少字段: ctx.%s', requiredTop{i});
        end
    end

    % ---------------- P.EV ----------------
    reqEV = {'B0_kWh','Bmin_kWh','Bchg_kWh','gE_kWh_per_km','rg_kWh_per_h'};
    for i = 1:numel(reqEV)
        must_num_scalar_(ctx.P.EV, reqEV{i}, 'ctx.P.EV');
    end
    if ctx.P.EV.B0_kWh <= 0, error('assert_config:badEV', 'B0_kWh 必须>0'); end
    if ctx.P.EV.Bchg_kWh <= 0, error('assert_config:badEV', 'Bchg_kWh 必须>0'); end
    if ctx.P.EV.gE_kWh_per_km <= 0, error('assert_config:badEV', 'gE_kWh_per_km 必须>0'); end
    if ctx.P.EV.rg_kWh_per_h <= 0, error('assert_config:badEV', 'rg_kWh_per_h 必须>0'); end

    % ---------------- P.Price ----------------
    reqPrice = {'elec_CNY_per_kWh','fuel_CNY_per_L','carbon_CNY_per_kgCO2'};
    for i = 1:numel(reqPrice)
        must_num_scalar_(ctx.P.Price, reqPrice{i}, 'ctx.P.Price');
    end

    % ---------------- P.Fleet ----------------
    reqFleet = {'QCV','QEV','speed_km_per_h','speed_km_per_min','cCV','cEV','mCV','mEV','nCV','nEV'};
    for i = 1:numel(reqFleet)
        must_num_scalar_(ctx.P.Fleet, reqFleet{i}, 'ctx.P.Fleet');
    end
    if abs(ctx.P.Fleet.speed_km_per_min*60 - ctx.P.Fleet.speed_km_per_h) > 1e-9
        error('assert_config:speedUnit', 'speed_km_per_h 与 speed_km_per_min 单位不一致(期望 speed_km_per_min=speed_km_per_h/60)');
    end
    if ctx.P.Fleet.speed_km_per_h <= 0
        error('assert_config:speed', 'speed_km_per_h 必须>0');
    end
    if ctx.P.Fleet.nCV < 0 || ctx.P.Fleet.nEV < 0 || (ctx.P.Fleet.nCV + ctx.P.Fleet.nEV) < 1
        error('assert_config:fleetCount', '车队数量无效: nCV=%g nEV=%g', ctx.P.Fleet.nCV, ctx.P.Fleet.nEV);
    end

    % ---------------- P.Model ----------------
    reqModel = {'serviceTime_min','allowCharging','forceChargeOnce','forceChargePolicy','useReachableReserve','reserveE_mode','visual2opt','initInjectRatio'};
    for i = 1:numel(reqModel)
        if ~isfield(ctx.P.Model, reqModel{i})
            error('assert_config:missingModel', 'ctx.P.Model 缺少字段: %s', reqModel{i});
        end
    end
    if ~islogical(ctx.P.Model.allowCharging), error('assert_config:modelType', 'allowCharging 必须是 logical'); end
    if ~islogical(ctx.P.Model.forceChargeOnce), error('assert_config:modelType', 'forceChargeOnce 必须是 logical'); end
    if ~ischar(ctx.P.Model.forceChargePolicy) && ~isstring(ctx.P.Model.forceChargePolicy)
        error('assert_config:modelType', 'forceChargePolicy 必须是 char/string');
    end
    must_num_scalar_(ctx.P.Model, 'serviceTime_min', 'ctx.P.Model');
    must_num_scalar_(ctx.P.Model, 'initInjectRatio', 'ctx.P.Model');

    % ---------------- P.Gopt ----------------
    if ~isfield(ctx.P,'Gopt') || ~isstruct(ctx.P.Gopt)
        error('assert_config:missingGopt', 'ctx.P.Gopt 缺失或非 struct');
    end

    % ---------------- P.CVOnlyOpt ----------------
    if ~isfield(ctx.P,'CVOnlyOpt') || ~isstruct(ctx.P.CVOnlyOpt)
        error('assert_config:missingCVOnlyOpt', 'ctx.P.CVOnlyOpt 缺失或非 struct');
    end

    % injectCount 由 NP 派生（统一口径：min(10,floor(NP/5))）
    if ~isfinite(ctx.P.CVOnlyOpt.injectCount)
        ctx.P.CVOnlyOpt.injectCount = min(10, floor(ctx.SolverCfg.NP/5));
    end

    % ---------------- SolverCfg ----------------
    reqSolver = {'NP','MaxGen','Pc','Pm','Pe','T0','alpha','Tmin','STOP_BY_TMIN','NRun','forceRecompute'};
    for i = 1:numel(reqSolver)
        if ~isfield(ctx.SolverCfg, reqSolver{i})
            error('assert_config:missingSolver', 'ctx.SolverCfg 缺少字段: %s', reqSolver{i});
        end
    end
    must_num_scalar_(ctx.SolverCfg, 'NP', 'ctx.SolverCfg');
    must_num_scalar_(ctx.SolverCfg, 'MaxGen', 'ctx.SolverCfg');
    must_num_scalar_(ctx.SolverCfg, 'Pc', 'ctx.SolverCfg');
    must_num_scalar_(ctx.SolverCfg, 'Pm', 'ctx.SolverCfg');
    must_num_scalar_(ctx.SolverCfg, 'Pe', 'ctx.SolverCfg');
    must_num_scalar_(ctx.SolverCfg, 'T0', 'ctx.SolverCfg');
    must_num_scalar_(ctx.SolverCfg, 'alpha', 'ctx.SolverCfg');
    must_num_scalar_(ctx.SolverCfg, 'Tmin', 'ctx.SolverCfg');
    must_num_scalar_(ctx.SolverCfg, 'NRun', 'ctx.SolverCfg');
    if ctx.SolverCfg.NP < 2, error('assert_config:solver', 'NP 必须>=2'); end
    if ctx.SolverCfg.MaxGen < 1, error('assert_config:solver', 'MaxGen 必须>=1'); end
    if ctx.SolverCfg.NRun < 1, error('assert_config:solver', 'NRun 必须>=1'); end
    if ctx.SolverCfg.Pc < 0 || ctx.SolverCfg.Pc > 1, error('assert_config:solver', 'Pc 必须在[0,1]'); end
    if ctx.SolverCfg.Pm < 0 || ctx.SolverCfg.Pm > 1, error('assert_config:solver', 'Pm 必须在[0,1]'); end
    if ~islogical(ctx.SolverCfg.STOP_BY_TMIN), error('assert_config:solverType', 'STOP_BY_TMIN 必须是 logical'); end
    if ~islogical(ctx.SolverCfg.forceRecompute), error('assert_config:solverType', 'forceRecompute 必须是 logical'); end

    % ---------------- Data ----------------
    reqData = {'raw','info','coord','q','LT','RT','E','n','D','ST'};
    for i = 1:numel(reqData)
        if ~isfield(ctx.Data, reqData{i})
            error('assert_config:missingData', 'ctx.Data 缺少字段: %s', reqData{i});
        end
    end
    if size(ctx.Data.coord,2) ~= 2
        error('assert_config:dataShape', 'coord 需为 N×2');
    end
    if size(ctx.Data.D,1) ~= size(ctx.Data.D,2)
        error('assert_config:dataShape', 'D 需为方阵');
    end
    if size(ctx.Data.D,1) ~= size(ctx.Data.coord,1)
        error('assert_config:dataShape', 'D 尺寸需与 coord 行数一致');
    end
    must_num_scalar_(ctx.Data, 'E', 'ctx.Data');
    must_num_scalar_(ctx.Data, 'n', 'ctx.Data');
    must_num_scalar_(ctx.Data, 'ST', 'ctx.Data');

    % ---------------- Meta ----------------
    reqMeta = {'projectRoot','timestamp','runTag','modeLabel','pipelineVersion','matlabRelease'};
    for i = 1:numel(reqMeta)
        if ~isfield(ctx.Meta, reqMeta{i})
            error('assert_config:missingMeta', 'ctx.Meta 缺少字段: %s', reqMeta{i});
        end
    end

    % ---------------- Section defaults ----------------
    if ~isfield(ctx.P,'Section532') || ~isstruct(ctx.P.Section532)
        error('assert_config:missingSection', 'ctx.P.Section532 缺失或非 struct');
    end
    if ~isfield(ctx.P,'Section533') || ~isstruct(ctx.P.Section533)
        error('assert_config:missingSection', 'ctx.P.Section533 缺失或非 struct');
    end
end

function must_num_scalar_(s, field, where)
if ~isfield(s, field)
    error('assert_config:missingField', '%s 缺少字段: %s', where, field);
end
v = s.(field);
if ~isnumeric(v) || ~isscalar(v) || ~isfinite(v)
    error('assert_config:badField', '%s.%s 必须是有限 numeric scalar', where, field);
end
end


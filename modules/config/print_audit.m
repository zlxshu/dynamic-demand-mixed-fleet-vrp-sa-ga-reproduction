function auditText = print_audit(ctx, varargin)
% 修改日志
% - v1 2026-01-21: 新增统一审计输出 print_audit(ctx)；固定格式打印关键参数/单位/签名/模式标签。
% - v2 2026-01-21: 增加 truthSource 审计行；支持传入 sectionName/paths，便于 runner 将审计落盘到 audit.txt。

    p = inputParser();
    p.addParameter('SectionName', '', @(s) ischar(s) || isstring(s));
    p.addParameter('ParamSig', struct(), @(s) isstruct(s));
    p.addParameter('DataSig', struct(), @(s) isstruct(s));
    p.addParameter('Paths', struct(), @(s) isstruct(s));
    p.parse(varargin{:});
    opt = p.Results;

    sectionName = char(string(opt.SectionName));

    paramSigShort = get_sig_field_(opt.ParamSig, 'short');
    paramSigFull  = get_sig_field_(opt.ParamSig, 'full');
    dataSigShort  = get_sig_field_(opt.DataSig, 'short');
    dataSigFull   = get_sig_field_(opt.DataSig, 'full');

    lines = {};
    lines{end+1} = sprintf('================== AUDIT ==================');
    if ~isempty(sectionName)
        lines{end+1} = sprintf('[SECTION] %s', sectionName);
    end
    lines{end+1} = sprintf('[RUN_TAG] %s', ctx.Meta.runTag);
    lines{end+1} = sprintf('[MODE_LABEL] %s', ctx.Meta.modeLabel);
    try
        if isfield(ctx.Meta,'algoProfile') && ~isempty(ctx.Meta.algoProfile)
            lines{end+1} = sprintf('[ALGO_PROFILE] %s', ctx.Meta.algoProfile);
        end
    catch
    end
    lines{end+1} = sprintf('[TIMESTAMP] %s', ctx.Meta.timestamp);
    lines{end+1} = sprintf('[PIPELINE] %s', ctx.Meta.pipelineVersion);
    if ~isempty(ctx.Meta.matlabRelease)
        lines{end+1} = sprintf('[MATLAB] %s', ctx.Meta.matlabRelease);
    end
    try
        if isfield(ctx.Meta,'truthSource') && isstruct(ctx.Meta.truthSource)
            ts = ctx.Meta.truthSource;
            lines{end+1} = sprintf('[TRUTH] %s | found=%d | path=%s | msg=%s', ...
                safe_str_(ts.name), double(ts.found), safe_str_(ts.path), safe_str_(ts.message));
        end
    catch
    end
    if ~isempty(paramSigFull)
        lines{end+1} = sprintf('[param_signature] %s | %s', paramSigShort, paramSigFull);
    end
    if ~isempty(dataSigFull)
        lines{end+1} = sprintf('[data_signature ] %s | %s', dataSigShort, dataSigFull);
    end

    % Data provenance
    try
        di = ctx.Data.info;
        lines{end+1} = sprintf('[DATA] source=%s | n=%d | E=%d | message=%s', safe_str_(di.source), ctx.Data.n, ctx.Data.E, safe_str_(di.message));
        if isfield(di,'pickedPath') && ~isempty(di.pickedPath)
            lines{end+1} = sprintf('[DATA] pickedPath=%s', di.pickedPath);
        end
    catch
    end

    % EV params
    lines{end+1} = sprintf('[EV] B0=%.1f kWh | Bmin=%.1f kWh | Bchg=%.1f kWh | gE=%.3f kWh/km | rg=%.1f kWh/h', ...
        ctx.P.EV.B0_kWh, ctx.P.EV.Bmin_kWh, ctx.P.EV.Bchg_kWh, ctx.P.EV.gE_kWh_per_km, ctx.P.EV.rg_kWh_per_h);

    % Prices
    lines{end+1} = sprintf('[PRICE] elec=%.3f CNY/kWh | fuel=%.3f CNY/L | carbon=%.3f CNY/kgCO2', ...
        ctx.P.Price.elec_CNY_per_kWh, ctx.P.Price.fuel_CNY_per_L, ctx.P.Price.carbon_CNY_per_kgCO2);

    % Fleet
    lines{end+1} = sprintf('[FLEET] nCV=%d nEV=%d | QCV=%g QEV=%g | speed=%.1f km/h (%.4f km/min) | cCV=%g cEV=%g | mCV=%g mEV=%g', ...
        round(ctx.P.Fleet.nCV), round(ctx.P.Fleet.nEV), ctx.P.Fleet.QCV, ctx.P.Fleet.QEV, ...
        ctx.P.Fleet.speed_km_per_h, ctx.P.Fleet.speed_km_per_min, ctx.P.Fleet.cCV, ctx.P.Fleet.cEV, ctx.P.Fleet.mCV, ctx.P.Fleet.mEV);

    % Solver
    lines{end+1} = sprintf('[SOLVER] NP=%d MaxGen=%d Pc=%.2f Pm=%.2f Pe=%.2f | T0=%.3g alpha=%.3g Tmin=%.3g | NRun=%d | forceRecompute=%d', ...
        round(ctx.SolverCfg.NP), round(ctx.SolverCfg.MaxGen), ctx.SolverCfg.Pc, ctx.SolverCfg.Pm, ctx.SolverCfg.Pe, ...
        ctx.SolverCfg.T0, ctx.SolverCfg.alpha, ctx.SolverCfg.Tmin, round(ctx.SolverCfg.NRun), double(ctx.SolverCfg.forceRecompute));

    % Model switches
    lines{end+1} = sprintf('[MODEL] allowCharging=%d forceChargeOnce=%d policy=%s | serviceTime=%g min | useReachableReserve=%d', ...
        double(ctx.P.Model.allowCharging), double(ctx.P.Model.forceChargeOnce), safe_str_(ctx.P.Model.forceChargePolicy), ...
        ctx.P.Model.serviceTime_min, double(ctx.P.Model.useReachableReserve));

    % G.opt highlight
    try
        o = ctx.P.Gopt;
        lines{end+1} = sprintf('[G.opt] eliteLS=%d relocate=%d swap=%d | repair(h=%.2f s=%.2f 2nd=%.2f) init(h=%.2f 2nd=%.2f) | immigration=%d kick=%d', ...
            double(o.enableEliteLS), double(o.enableRelocate), double(o.enableSwap), ...
            o.heuristicRepairProb, o.strongRepairProb, o.secondRepairProb, o.initHeuristicRepairProb, o.initSecondRepairProb, ...
            double(o.enableImmigration), double(o.enableKick));
    catch
    end

    % Paths (optional)
    try
        if isfield(opt.Paths,'root') && ~isempty(opt.Paths.root)
            lines{end+1} = sprintf('[OUTPUT_ROOT] %s', opt.Paths.root);
        end
    catch
    end

    lines{end+1} = sprintf('================================================');

    auditText = strjoin(lines, newline);
    fprintf('%s\n', auditText);
end

function s = safe_str_(x)
try
    s = char(string(x));
catch
    s = '';
end
end

function v = get_sig_field_(s, f)
v = '';
try
    if isfield(s, f)
        v = char(string(s.(f)));
    end
catch
end
end



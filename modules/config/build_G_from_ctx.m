function G = build_G_from_ctx(ctx, varargin)
% 修改日志
% - v1 2026-01-21: 新增 build_G_from_ctx(ctx)；统一构造算法全局结构 G（数据/车队/成本/EV/站点/预计算/选项）。
% - v1 2026-01-21: 站点 reserveE/nearStation 等预计算集中化，确保所有 section 口径一致。

    p = inputParser();
    p.addParameter('nCV', ctx.P.Fleet.nCV, @(x) isnumeric(x) && isscalar(x));
    p.addParameter('nEV', ctx.P.Fleet.nEV, @(x) isnumeric(x) && isscalar(x));
    p.addParameter('AllowCharging', ctx.P.Model.allowCharging, @(x) islogical(x) && isscalar(x));
    p.addParameter('ForceChargeOnce', ctx.P.Model.forceChargeOnce, @(x) islogical(x) && isscalar(x));
    p.addParameter('ForceChargePolicy', ctx.P.Model.forceChargePolicy, @(s) ischar(s) || isstring(s));
    p.parse(varargin{:});
    opt = p.Results;

    nCV = round(opt.nCV);
    nEV = round(opt.nEV);

    baseFleet = struct();
    baseFleet.QCV = ctx.P.Fleet.QCV;
    baseFleet.QEV = ctx.P.Fleet.QEV;
    baseFleet.speed = ctx.P.Fleet.speed_km_per_min; % km/min（算法内部口径）
    baseFleet.cCV = ctx.P.Fleet.cCV;
    baseFleet.cEV = ctx.P.Fleet.cEV;
    baseFleet.mCV = ctx.P.Fleet.mCV;
    baseFleet.mEV = ctx.P.Fleet.mEV;

    [K, Qmax, Speed, c, m] = build_fleet_arrays(nCV, nEV, baseFleet);

    % ---------------- Data ----------------
    n = ctx.Data.n;
    E = ctx.Data.E;

    G = struct();
    G.n = n;
    G.E = E;
    G.K = K;
    G.coord = ctx.Data.coord;
    G.D = ctx.Data.D;
    G.q = ctx.Data.q;
    G.LT = ctx.Data.LT;
    G.RT = ctx.Data.RT;
    G.ST = ctx.Data.ST;

    % ---------------- Fleet ----------------
    G = apply_fleet_to_global(G, nCV, nEV, K, Qmax, Speed, c, m);

    % ---------------- EV params ----------------
    G.B0 = ctx.P.EV.B0_kWh;
    G.Bmin = ctx.P.EV.Bmin_kWh;
    G.Bchg = ctx.P.EV.Bchg_kWh;
    G.gE = ctx.P.EV.gE_kWh_per_km;
    G.rg = ctx.P.EV.rg_kWh_per_h;

    % ---------------- Prices ----------------
    G.elec_price = ctx.P.Price.elec_CNY_per_kWh;
    G.fuel_price = ctx.P.Price.fuel_CNY_per_L;
    G.carbon_price = ctx.P.Price.carbon_CNY_per_kgCO2;

    % ---------------- CMEM ----------------
    if isfield(ctx.P,'CMEM') && isstruct(ctx.P.CMEM)
        G.CMEM = ctx.P.CMEM;
    end

    % ---------------- Switches ----------------
    G.allowCharging = logical(opt.AllowCharging);
    G.forceChargeOnce = logical(opt.ForceChargeOnce);
    G.forceChargePolicy = char(string(opt.ForceChargePolicy));
    G.useReachableReserve = logical(ctx.P.Model.useReachableReserve);
    G.visual2opt = logical(ctx.P.Model.visual2opt);
    G.initInjectRatio = ctx.P.Model.initInjectRatio;

    % ---------------- Stations & reserveE ----------------
    G.stationNodes = (n+1):(n+E);
    stationIdx = G.stationNodes + 1;
    nearDist = zeros(n+1, 1);
    nearSt = zeros(n+1, 1);
    for node = 0:n
        [nearDist(node+1), ii] = min(G.D(node+1, stationIdx));
        nearSt(node+1) = G.stationNodes(ii);
    end
    G.nearStationDist = nearDist;
    G.nearStation = nearSt;
    G.reserveE = nearDist * G.gE;
    G.reserveE_mode = ctx.P.Model.reserveE_mode;

    % ---------------- Options ----------------
    G.opt = ctx.P.Gopt;
    G.cvOnlyOpt = ctx.P.CVOnlyOpt;
    % 算法档位（仅流程增强，不改参数）
    try
        if isfield(ctx,'Meta') && isfield(ctx.Meta,'algoProfile')
            G.algoProfile = upper(strtrim(char(string(ctx.Meta.algoProfile))));
        end
    catch
    end
end



function result = section_template(varargin)
% section_template - New section template (auto data logic)
%
% Usage:
%   section_template()             % auto-load data and run default logic
%   section_template('Name',Value) % optional overrides (see below)

% ---- Unified project folders (auto for new sections) ----
% 所有新 section 默认：
% - 输出写入根目录 OUT/<sectionName>/时间戳_标签/
% - 缓存写入根目录 CACHE/<sectionName>/<cacheKey>_时间戳.mat，并维护 <cacheKey>_best.mat
rootDir = project_root_dir(); %#ok<NASGU>
sectionName = mfilename();
outDir = out_make_dir(sectionName, '');

% ---- Optional overrides ----
p = inputParser();
p.addParameter('NP', 200, @(x) isnumeric(x) && isscalar(x));
p.addParameter('MaxGen', 300, @(x) isnumeric(x) && isscalar(x));
p.addParameter('NRun', 10, @(x) isnumeric(x) && isscalar(x));
p.addParameter('UseCache', true, @(x) islogical(x) && isscalar(x));
p.parse(varargin{:});
cfg = p.Results;

% ---- Unified data logic: data/ -> copy -> fallback ----
[data, info] = load_data_auto();
fprintf('[DATA] %s\n', info.message);

coord = data(:,1:2);
q     = data(:,3);
LT    = data(:,4);
RT    = data(:,5);
E     = info.E;
n     = info.n;
D     = pairwise_dist_fast(coord);
ST    = 20;

% ---- Minimal fleet/G (adjust as needed) ----
baseFleet = struct('QCV',1500,'QEV',1000,'speed',(40/60),'cCV',100,'cEV',200,'mCV',20,'mEV',10);
nCV = 2; nEV = 2;
[K, Qmax, Speed, c, m] = build_fleet_arrays(nCV, nEV, baseFleet);

G = struct();
G.n = n; G.K = K; G.E = E;
G.nCV = nCV; G.nEV = nEV;
G.isEV = false(1,K); if nEV>0, G.isEV(nCV+1:end) = true; end
G.coord = coord; G.D = D; G.q = q; G.LT = LT; G.RT = RT; G.ST = ST; G.Speed = Speed; G.Qmax = Qmax;
G.B0 = 100; G.Bmin = 0; G.Bchg = 100; G.gE = 1.0; G.rg = 100;
G.c = c; G.m = m;
G.opt = struct('enableEliteLS',true,'eliteTopN',8,'ls2optIter',25,'lsOrOptTrials',20,'crossTrials',10, ...
    'allowWorseLS',true,'enableRelocate',true,'enableSwap',true,'heuristicRepairProb',0.70,'strongRepairProb',0.08, ...
    'secondRepairProb',0.55,'initHeuristicRepairProb',0.85,'initSecondRepairProb',0.90,'enableImmigration',true, ...
    'immigrationPeriod',25,'immigrationRatio',0.05,'enableKick',true,'stagnationGen',35,'kickProb',0.30,'kickStrength',3);
G.initInjectRatio = 0.3;

% ---- Solver parameters ----
NP = cfg.NP;
MaxGen = cfg.MaxGen;
Pc = 0.9; Pm = 0.10; Pe = 0;
T0 = 500; Tmin = 0.01; alpha = 0.95; STOP_BY_TMIN = true;
NRun = cfg.NRun;

% ---- Optional cache hook (example) ----
% 若你的 section 可直接复用“混合车队”之类的缓存，可以启用这段逻辑
% cacheKey = 'default';
% if cfg.UseCache
%     [cached, bestPath, bestCost] = cache_load_best(sectionName, cacheKey, 'result');
%     if ~isempty(cached)
%         fprintf('[CACHE] loaded: %s | cost=%.6f\n', bestPath, bestCost);
%         result = cached;
%         return;
%     end
% end

% ---- Example run loop (customize for your section logic) ----
bestCost = inf;
for run = 1:NRun
    rng(run);
    out = one_run_gsaa(NP, MaxGen, Pc, Pm, Pe, T0, Tmin, alpha, STOP_BY_TMIN, G);
    if out.bestFeasibleFound && out.bestCost < bestCost
        bestCost = out.bestCost;
    end
end

result = struct('bestCost', bestCost, 'nRun', NRun);

% ---- Save section outputs (example) ----
try
    save(fullfile(outDir, [sectionName '_result.mat']), 'result');
catch
end

% ---- Save cache (example) ----
% if cfg.UseCache
%     result.bestCost = bestCost;
%     cache_save_versioned(sectionName, cacheKey, 'result', result, bestCost);
% end
end


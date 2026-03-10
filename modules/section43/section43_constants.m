function cfg = section43_constants()
% 修改日志
% - v26 2026-02-11: paired_run 默认选run策略升级为 min_shape_score_nonflat，优先排除整段平线候选，减少图4.8“假直线”观感。
% - v25 2026-02-11: 新增 curvePolicyUnified 默认开关（默认 true），用于统一图展示与领先判定口径；可由 run_modes 显式关闭。
% - v24 2026-02-11: repro_baseline 默认关闭 figureHardGateEnable（PDF锚点硬门槛降为诊断），避免图锚点误差阻断真实求解基线。
% - v23 2026-02-11: 复现基线止损修复：paperGsaaEnsureOps 默认回退为 false；recoverMaxTry 提升到 5000，降低 SA 偶发 NaN。
% - v22 2026-02-11: paperGsaaEnsureOps 默认改为 true，避免论文模式下 GSAA 关键算子因默认值误关。
% - v21 2026-02-11: 4.3 默认算法套件改为 paper_suite（真实复现基线默认值）；仅流程开关，不改论文参数。
% - v20 2026-02-10: 新增4.3分轨流程字段（trackMode/algoSuite/postRecoveryPolicy/resultSourceForTable/dominanceMode/dominanceCurvePolicy）；仅流程控制，不改论文参数。
% - v19 2026-02-10: 新增 GSAA 全程领先硬门槛流程配置（dominanceHardEnable/dominanceMinRatio）；仅影响复现判定，不改论文参数。
% - v18 2026-02-10: paperGsaaEnsureOps 默认改回 false（保留开关能力），避免 GSAA 过强化导致偏离论文目标容差与时间顺序门槛。
% - v17 2026-02-10: 新增 paperGsaaEnsureOps 开关（默认 true）；仅用于修复论文模式下 GSAA 关键算子被全局 PAPER 档误关的问题，不改论文参数值。
% - v16 2026-02-10: 新增 parallelLogLevel 并行顺序日志级别流程开关（none/summary/detailed），仅影响日志可读性，不改论文参数与算法语义。
% - v15 2026-02-09: 新增 gatePolicy 流程开关（two_stage/single_stage），用于“先表后图”两阶段门控；不改论文参数与算法语义。
% - v14 2026-02-09: 新增并行执行流程开关（parallelEnable/parallelWorkers），仅优化NRun运行效率，不改论文参数与模型语义。
% - v13 2026-02-09: 新增 earlyStopOnPass 复现流程开关（仅控制批次调度，不改论文参数）；默认关闭，由 run_modes 显式托管覆盖。
% - v12 2026-02-08: 固化图4.8同run曲线口径与图形硬门槛（锚点/末代误差），并启用图表双门槛联合PASS。
% - v11 2026-02-08: 新增平台期进度判据（累计降幅达到85%视为进入平台），避免被后期微小改进拖晚平台代数。
% - v10 2026-02-07: 新增4.3流程开关（SA论文模式预算倍率/是否跑满MaxGen/回补曲线注入策略），用于抑制SA过快与末代突降曲线污染。
% - v9 2026-02-07: 强化4.3复现回补强度（recoverMaxTry/restartPeriod）并放宽平台相对容差到1%以匹配论文图像级平台判读。
% - v8 2026-02-07: 时间口径改为 NRun 累计时间（修正单次测时误读）；新增统一回补随机重启参数。
% - v7 2026-02-07: 新增平台期相对容差参数 plateauRelTol，避免“近平台”被误判为未平台。
% - v6 2026-02-06: 新增4.3严格复现批次配置（maxBatches/seed策略/目标值容差/时间与曲线硬门槛）；曲线聚合默认改为 best_run。
% - v5 2026-02-06: fail-fast 默认关闭（保留审计报告）；仅在论文测试模式下强制论文对齐判定。
% - v4 2026-02-06: 新增论文4.3复现审计基线与硬门槛（可行率/成本带/GAP 偏差）；新增曲线聚合与前置 NaN 处理开关。
% - v3 2026-02-04: Pe 撤销为 0.0（与用户要求一致；改由 SA 邻域简化实现公平对比）。
% - v2 2026-02-04: Pe 由 0.0 改为 0.1（论文未规定；与作者参考代码一致，改善 GSAA 精英保留）。
% - v1 2026-02-03: 新增 section43_constants；论文4.3节算法对比实验的参数硬校验（表4.2）。
%
% 说明：
% - 本文件是 section_43 的唯一参数真源，所有参数必须与论文表4.2完全一致。
% - 禁止在其他文件中硬编码这些参数；仅允许通过本文件读取。
% - 参数含义与论文对齐，不得擅自修改。
%
% 论文表4.2 参数设置：
%   popsize (NP)    = 200   种群规模
%   MaxGen          = 300   最大迭代次数
%   Pc              = 0.9   交叉概率
%   Pm              = 0.1   变异概率
%   T0              = 500   初始温度
%   Tmin            = 0.01  终止温度
%   alpha           = 0.95  温度衰减系数
%   NRun            = 10    独立运行次数

cfg = struct();

% ===== 论文表4.2 算法参数（硬编码，禁止修改）=====
cfg.NP = 200;           % 种群规模 popsize
cfg.MaxGen = 300;       % 最大迭代次数
cfg.Pc = 0.9;           % 交叉概率
cfg.Pm = 0.1;           % 变异概率
cfg.Pe = 0.0;           % 精英保留比例（论文未明确，GSAA使用0）
cfg.T0 = 500;           % 初始温度
cfg.Tmin = 0.01;        % 终止温度
cfg.alpha = 0.95;       % 温度衰减系数
cfg.NRun = 10;          % 独立运行次数
cfg.STOP_BY_TMIN = true; % 温度低于Tmin时停止

% ===== 数据源配置 =====
cfg.dataFileName = '论文示例静态节点数据.xlsx';  % 论文表4.1数据

% ===== 期望的数据规格（用于一致性校验）=====
cfg.expected_n = 20;    % 客户节点数
cfg.expected_E = 5;     % 充电站数
cfg.expected_depot_coord = [56, 56];  % 配送中心坐标

% ===== 车队配置（与5.3.x一致）=====
cfg.nCV = 2;
cfg.nEV = 2;

% ===== 输出控制（由环境变量覆盖）=====
cfg.verbose = true;
cfg.keepFigures = true;
cfg.printTables = true;

% ===== 图表配置 =====
cfg.curveMode = 'cummin';  % 迭代曲线模式：cummin（累积最优）
cfg.curveAggregate = 'best_run'; % 迭代曲线聚合：best_run | first_run | median | mean（只影响展示，不影响求解）
cfg.fillLeadingNaN = false; % 是否回填开头连续 NaN（默认否，避免人为美化）
cfg.colors = struct( ...
    'GSAA', [0 0.4470 0.7410], ...    % 蓝色
    'GA',   [0.8500 0.3250 0.0980], ... % 红色
    'SA',   [0.9290 0.6940 0.1250] ...  % 黄色
    );

% ===== 数据硬校验（论文4.1）=====
cfg.requireStrictData = true; % 数据规格/配送中心坐标不一致时直接报错

% ===== 论文4.3基线（表4.3 最优值行）=====
cfg.paperBaseline = struct();
cfg.paperBaseline.GSAA_Cost = 10048.89;
cfg.paperBaseline.GA_Cost = 10204.41;
cfg.paperBaseline.SA_Cost = 10070.96;
cfg.paperBaseline.GAP_GA = -1.52;
cfg.paperBaseline.GAP_SA = -0.08;

% ===== 复现结果验收门槛（用于拒绝不可接受结果；不用于调参）=====
cfg.acceptance = struct();
cfg.acceptance.enableFailFast = false;     % true: 触发门槛即 error（默认关闭，避免中断产物导出）
cfg.acceptance.minFeasibleRate = 1.0;      % 每算法最低可行率（论文4.3对比需 10/10）
cfg.acceptance.maxSaNanCount = 0;          % SA 成本 NaN 个数上限
cfg.acceptance.costBand = [8000, 20000];   % 成本合理区间（防止误把罚函数当成本）
cfg.acceptance.requirePaperOrder = true;   % 仅论文测试模式生效：GSAA 最优（MIN 行需不高于 GA/SA）
cfg.acceptance.maxAbsGapGaVsPaper = 5.0;   % |GAP_GA(min)-论文值| 上限（百分点）
cfg.acceptance.maxAbsGapSaVsPaper = 5.0;   % |GAP_SA(min)-论文值| 上限（百分点）

% ===== 严格复现批次配置（仅控制复现流程，不改论文参数）=====
cfg.repro = struct();
cfg.repro.maxBatches = 20;  % 复现最大批次数
cfg.repro.earlyStopOnPass = false;  % 命中首个PASS批次后是否提前停止（流程开关，默认由 run_modes 覆盖）
cfg.repro.gatePolicy = 'two_stage';  % 门控策略：two_stage=先表预检再触发图检；single_stage=每批都图检（流程开关）
cfg.repro.trackMode = 'repro_baseline';  % 4.3分轨：repro_baseline=真实复现基线；dominance_experiment=全程领先实验（流程开关）
cfg.repro.algoSuite = 'paper_suite';  % 算法套件：paper_suite|opensource_suite|opensource_strict（流程开关）
cfg.repro.postRecoveryPolicy = 'diag_only';  % 后置恢复策略：off|diag_only|apply_to_all（流程开关）
cfg.repro.resultSourceForTable = 'raw';  % 表4.3主口径：raw|recovered（流程开关，默认raw）
cfg.repro.dominanceMode = 'diag';  % 全程领先模式：off|diag|hard（流程开关）
cfg.repro.dominanceCurvePolicy = 'paired_run';  % 全程领先判定曲线口径：paired_run（流程开关）
cfg.repro.curvePolicyUnified = true;  % 曲线口径统一开关：true=展示与领先判定统一（paired_run）；false=允许分离
cfg.repro.parallelEnable = false;  % 是否并行执行 NRun 独立运行（流程优化开关）
cfg.repro.parallelWorkers = 0;  % 并行 worker 数：0 自动，>0 指定数量
cfg.repro.parallelLogLevel = 'detailed';  % 并行顺序日志级别：none | summary | detailed（仅日志展示）
cfg.repro.seedList = 1:10;  % 单批10次独立运行的基准seed列表
cfg.repro.batchSeedStride = 1000;  % 批次seed偏移步长（batch b 使用 seed + (b-1)*stride）
cfg.repro.algorithmSeedOffset = struct('GSAA', 11, 'GA', 22, 'SA', 33); % 同run内算法独立子seed偏移
cfg.repro.targetCostTolPct = 0.02;  % 目标值容差（相对论文MIN值）
cfg.repro.pickPolicy = 'closest_after_all_batches';  % 批次选取策略
cfg.repro.curveAggregate = 'best_run';  % 兼容字段（paired_run启用时不使用）
cfg.repro.curveSelectionPolicy = 'paired_run';  % 图4.8曲线口径：同一个run索引对比三算法
cfg.repro.curvePairedRunPick = 'min_shape_score_nonflat';  % 同run候选选择策略：先过滤平线候选再按图形误差分选取
cfg.repro.curveOrderRule = 'gsaa_lowest_only';  % 曲线末代排序规则：仅GSAA最低
cfg.repro.plateauProfile = 'paper_approx';  % 平台期阈值配置：paper_approx(80/130/130)
cfg.repro.paperGsaaEnsureOps = false;  % 论文模式下仅对GSAA恢复关键流程算子（默认关闭；由 run_modes 显式开启）
cfg.repro.plateauRelTol = 0.03;  % 平台判定相对容差（相对最终值的3%内视为平台，按图像级平台判读）
cfg.repro.plateauProgressRatio = 0.80;  % 平台进度判据（累计降幅达到80%即视为进入平台）
cfg.repro.figureHardGateEnable = false;  % 图4.8形态硬门槛开关（baseline默认关闭，作为诊断；实验轨可显式开启）
cfg.repro.figureRefSource = 'pdf_extract';  % 图4.8参考源：论文PDF自动抽取
cfg.repro.figureAnchorGens = [1 10 20 30 40 50 80 100 130 300];  % 图4.8形态锚点代数
cfg.repro.figureAnchorRelTol = 0.03;  % 图4.8锚点相对误差阈值
cfg.repro.figureEndpointRelTol = 0.02;  % 图4.8末代相对误差阈值
cfg.repro.passRequiresFigureAndTable = true;  % PASS 规则：图门槛与表门槛必须同时通过
cfg.repro.dominanceHardEnable = false;  % GSAA全程领先硬门槛开关（true=阻断PASS；false=仅诊断）
cfg.repro.dominanceMinRatio = 0.95;  % GSAA领先比例阈值（dominanceHardEnable=true时生效）
cfg.repro.timeMetric = 'nrun_cumulative';  % 时间口径：按单批 NRun 次结果累计时间
cfg.repro.timeBenchmarkRepeats = 3;  % 时间基准重复次数
cfg.repro.timeOrderHard = true;  % 时间排序是否作为硬门槛（GA < GSAA < SA）
cfg.repro.recoverMaxTry = 5000;  % 统一回补最大尝试次数（随机重启+强修复，提升 SA 可行率稳定性）
cfg.repro.recoverRestartPeriod = 10;  % 回补重启周期（每N次强制随机重启）
cfg.repro.recoveryCurveInjectMode = 'all_nan_only';  % 回补成本注入曲线策略：仅当原曲线全NaN时注入，避免末代突降污染平台期
cfg.repro.saPaperMarkovMultiplier = 2;  % SA论文模式每温度邻域预算倍率（不改NP参数，仅控制每温度采样次数）
cfg.repro.saPaperUseFullMaxGen = true;  % SA论文模式是否跑满MaxGen（true: 不因T<Tmin提前停止）

end

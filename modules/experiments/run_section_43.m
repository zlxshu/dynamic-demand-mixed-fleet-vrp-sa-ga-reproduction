function out = run_section_43(ctx)
% 修改日志
% - v38 2026-02-11: paired_run 新增 nonflat 选run策略（min_shape_score_nonflat），优先排除“整段平线”候选再按形态分选取，避免图4.8出现伪退化直线观感。
% - v37 2026-02-11: 新增曲线口径统一开关（SECTION43_CURVE_POLICY_UNIFIED）；默认统一为 paired_run，可显式切换为不统一口径。
% - v36 2026-02-11: 全程领先比率函数改为严格小于（GSAA<GA 且 GSAA<SA），与 AGENTS 最小化语义一致。
% - v35 2026-02-11: SECTION43_PAPER_GSAA_ENSURE_OPS 环境默认值改为 true，避免 run_modes 外部调用时 GSAA 关键算子默认误关。
% - v34 2026-02-11: 修复并行 workers 日志显示：parallel.Pool 对象读取 NumWorkers 由对象属性专用函数获取，避免误显示 workers=1。
% - v33 2026-02-11: 修复4.3分轨稳健性：algoSuite 缺省回退 paper_suite；dominance_experiment 下 paper_suite 自动启用 GSAA 关键算子保真；two_stage 预检失败时移除误导性 figure_hard_gate_disabled 并改为显式 skipped 诊断；不改论文参数。
% - v31 2026-02-10: 新增“真实复现基线/全程领先实验”分轨开关与 raw/recovered 分账口径；全程领先硬判改为 paired_run 专用口径；不改论文参数。
% - v30 2026-02-10: 新增 GSAA 全程领先硬门槛（可选）与无参考源下的基础图形阻断判定；修复 figure_hard_gate_disabled 导致的“图门槛空过”假PASS。
% - v29 2026-02-10: 新增论文模式 GSAA 算子保真修补（仅43内对 GSAA 上下文恢复关键流程算子）；补充算法阶段前置日志；并行时关闭内核细粒度日志避免终端交叉污染。
% - v28 2026-02-10: 定稿收口：默认关闭非必要附加导出/重型校验（由 run_modes 控制）；批次审计终端输出回归简洁版，保留审计文件完整诊断。
% - v27 2026-02-10: 细化 run 级算法日志前缀为统一格式 `[section][batch][run][ALG]`，确保每条迭代前日志可直接识别当前算法（仅日志展示，不改算法）。
% - v26 2026-02-10: 修复 gsaa_dominance_ratio_43_ 作用域错误（补齐 last_finite_ 的 end 配对），消除运行期“函数无法识别”崩溃。
% - v25 2026-02-10: 新增强制可见算法套件标识日志（[section_43][ALGO_SUITE]），并在开始/批次/结束三处打印，不受 verbose 开关影响。
% - v24 2026-02-10: 统一 section_43 终端日志结构（算法套件声明 + run级统一字段）；新增“GSAA全程领先比例”诊断项（仅诊断不参与通过判定）。
% - v23 2026-02-10: 新增 SECTION43_PARALLEL_LOG_LEVEL；并行批次执行改为按 run 顺序输出详细日志（none/summary/detailed），保证终端可读且不交叉。
% - v22 2026-02-09: 新增 two_stage 门控策略（先表预检再图检）与惰性图参考加载；仅在 table_precheck 通过时触发图严格校验，支持首个“图表双通过”即停。
% - v21 2026-02-09: 新增 section_43 并行执行开关（run_modes 唯一托管）；在不改论文参数/口径前提下并行化 NRun 独立运行并失败回退串行。
% - v20 2026-02-09: 新增 earlyStopOnPass 批次提前停止（由 run_modes 唯一开关控制）；命中首个PASS批次后提前结束，降低4.3复现耗时。
% - v19 2026-02-09: 修复 <missing> 导致的字符串化崩溃；新增 curveMeta 缺失清洗与诊断（告警不阻断），并统一安全字符串输出。
% - v18 2026-02-09: 新增曲线口径与图门槛开关的 run_modes 托管（CURVE_SELECTION_POLICY/CURVE_PAIRED_RUN_PICK/FIGURE_HARD_GATE_ENABLE）；无参考源时禁止 paired_run 退化偏差，自动回退 best_run 并关闭图锚点硬门槛。
% - v17 2026-02-08: section_43 图参考源与缓存策略收口到 run_modes（none|pdf_extract + cacheEnable/forceRefresh）；参考曲线缓存统一到 outputs/section_43/cache（签名隔离）。
% - v16 2026-02-08: 修复参考曲线缺失时 paired_run 退化到 run1 的问题；新增无参考时同run选取 fallback（按论文三算法成本误差最小）。
% - v15 2026-02-08: 图4.8切换为同run曲线口径（paired_run）；接入PDF参考曲线锚点硬门槛并与表格审计联合判定PASS。
% - v14 2026-02-08: 平台期判定改为“终值容差 + 累计降幅进度”双判据（取更早代数），降低后期微小改进导致的平台期误判。
% - v13 2026-02-07: SA论文模式接入复现流程开关（预算倍率/满代运行）；回补曲线注入改为可配置，默认仅在原曲线全NaN时注入，避免末代突降污染平台判定。
% - v12 2026-02-07: 统一回补支持随机冷启动兜底与更强多次搜索；回补耗时计入累计时间，增强可行率与时间口径一致性。
% - v11 2026-02-07: 时间硬门槛改为 NRun 累计时间口径；统一回补增加随机重启强修复，提升20批复现可行率。
% - v10 2026-02-07: 修复MIN行GAP口径联动后评分偏差；GA改可行优先筛选；统一不可行回补；平台期改相对容差；评分对NaN/Inf鲁棒。
% - v9 2026-02-06: 实现4.3严格真实复现调度器（最多20批、固定seed批次、硬门槛审计、全批评分选批）；新增批次汇总审计。
% - v8 2026-02-06: modeTag 按纸面模式区分（reproMode/algoCompare）；导出前隐藏坐标区工具栏，消除 exportgraphics 警告。
% - v7 2026-02-06: 复现审计口径修正：论文对齐项仅在 SECTION43_USE_PAPER_TEST=true 时启用；fail-fast 默认仅告警不终止。
% - v6 2026-02-06: 新增论文4.3复现硬门槛审计（可行率/成本带/GAP）；曲线改为多次运行聚合，避免首轮抽样偏差；数据规格不一致支持 fail-fast。
% - v1 2026-02-03: 新增 run_section_43；论文4.3节算法检验主逻辑。
%
% run_section_43 - 论文4.3节算法检验（GSAA vs GA vs SA）
%
% 功能：
% - 论文参数固定前提下，执行严格复现批次调度（默认最多20批）；
% - 每批10次独立运行，算法子seed隔离，避免随机流耦合；
% - 先导出审计与产物，再按硬门槛判断PASS/FAIL；
% - 若20批无通过批次，导出“最接近批次”证据并最终报错。

sectionName = 'section_43';
modeTag = 'algoCompare';

% ===== 从环境变量读取输出控制开关（由 run_modes.m 设置）=====
cfg_verbose = env_bool_or_default_('SECTION43_VERBOSE', true);
cfg_keepFigures = env_bool_or_default_('SECTION43_KEEP_FIGURES', true);
cfg_printTables = env_bool_or_default_('SECTION43_PRINT_TABLES', true);
cfg_usePaperTest = env_bool_or_default_('SECTION43_USE_PAPER_TEST', false);
cfg_exportRichTable = env_bool_or_default_('SECTION43_EXPORT_RICH_TABLE', false);
cfg_verifyEnable = env_bool_or_default_('SECTION43_VERIFY_ENABLE', false);
cfg_refPdf = env_str_or_default_('SECTION43_REF_PDF', '');
cfg_figureRefSource = env_str_or_default_('SECTION43_FIGURE_REF_SOURCE', '');
cfg_refCacheEnable = env_bool_or_default_('SECTION43_REF_CACHE_ENABLE', true);
cfg_refCacheForceRefresh = env_bool_or_default_('SECTION43_REF_CACHE_FORCE_REFRESH', false);
cfg_curveSelectionPolicy = env_str_or_default_('SECTION43_CURVE_SELECTION_POLICY', '');
cfg_curvePairedRunPick = env_str_or_default_('SECTION43_CURVE_PAIRED_RUN_PICK', '');
cfg_figureHardGateEnable = env_bool_or_default_('SECTION43_FIGURE_HARD_GATE_ENABLE', true);
cfg_paperGsaaEnsureOps = env_bool_or_default_('SECTION43_PAPER_GSAA_ENSURE_OPS', true);
cfg_trackMode = env_str_or_default_('SECTION43_TRACK_MODE', '');
cfg_algoSuite = env_str_or_default_('SECTION43_ALGO_SUITE', '');
cfg_postRecoveryPolicy = env_str_or_default_('SECTION43_POST_RECOVERY_POLICY', '');
cfg_resultSourceForTable = env_str_or_default_('SECTION43_RESULT_SOURCE_FOR_TABLE', '');
cfg_dominanceMode = env_str_or_default_('SECTION43_DOMINANCE_MODE', '');
cfg_dominanceCurvePolicy = env_str_or_default_('SECTION43_DOMINANCE_CURVE_POLICY', '');
cfg_curvePolicyUnified = env_bool_or_default_('SECTION43_CURVE_POLICY_UNIFIED', true);
cfg_dominanceHardEnable = env_bool_or_default_('SECTION43_DOMINANCE_HARD_ENABLE', false);
cfg_dominanceMinRatio = env_double_or_default_('SECTION43_DOMINANCE_MIN_RATIO', NaN);
cfg_parallelEnable = env_bool_or_default_('SECTION43_PARALLEL_ENABLE', false);
cfg_parallelWorkers = env_int_or_default_('SECTION43_PARALLEL_WORKERS', NaN);
cfg_parallelLogLevel = env_str_or_default_('SECTION43_PARALLEL_LOG_LEVEL', '');

% 严格复现流程开关（不涉及论文参数）
env_maxBatches = env_int_or_default_('SECTION43_REPRO_MAX_BATCHES', NaN);
env_earlyStopOnPass = env_bool_or_default_('SECTION43_REPRO_EARLY_STOP_ON_PASS', false);
env_gatePolicy = env_str_or_default_('SECTION43_REPRO_GATE_POLICY', '');
env_pickPolicy = env_str_or_default_('SECTION43_REPRO_PICK_POLICY', '');
env_costTolPct = env_double_or_default_('SECTION43_COST_TOL_PCT', NaN);
env_timeBenchRepeats = env_int_or_default_('SECTION43_TIME_BENCH_REPEATS', NaN);
env_curvePlateauProfile = env_str_or_default_('SECTION43_CURVE_PLATEAU_PROFILE', '');

if cfg_usePaperTest
    modeTag = 'reproMode';
else
    modeTag = 'algoCompare';
end

% ===== 加载 section43 专用参数（论文表4.2硬校验）=====
cfg43 = section43_constants();
cfg43.projectRoot = ctx.Meta.projectRoot;

% ===== 复现流程覆盖（仅流程，不改论文参数）=====
if ~isfield(cfg43, 'repro') || ~isstruct(cfg43.repro)
    cfg43.repro = struct();
end
if ~isfield(cfg43.repro, 'trackMode') || isempty(cfg43.repro.trackMode)
    cfg43.repro.trackMode = 'repro_baseline';
end
if ~isempty(strtrim(cfg_trackMode))
    cfg43.repro.trackMode = char(string(cfg_trackMode));
end
cfg43.repro.trackMode = lower(strtrim(stringify_safe_(cfg43.repro.trackMode)));
if ~any(strcmp(cfg43.repro.trackMode, {'repro_baseline', 'dominance_experiment'}))
    warning('run_section_43:invalidTrackMode', ...
        'SECTION43_TRACK_MODE=%s 无效，已回退为 repro_baseline。', stringify_safe_(cfg43.repro.trackMode));
    cfg43.repro.trackMode = 'repro_baseline';
end
if ~isfield(cfg43.repro, 'algoSuite') || isempty(cfg43.repro.algoSuite)
    cfg43.repro.algoSuite = 'paper_suite';
end
if ~isempty(strtrim(cfg_algoSuite))
    cfg43.repro.algoSuite = char(string(cfg_algoSuite));
end
cfg43.repro.algoSuite = lower(strtrim(stringify_safe_(cfg43.repro.algoSuite)));
if ~isfield(cfg43.repro, 'postRecoveryPolicy') || isempty(cfg43.repro.postRecoveryPolicy)
    cfg43.repro.postRecoveryPolicy = 'diag_only';
end
if ~isempty(strtrim(cfg_postRecoveryPolicy))
    cfg43.repro.postRecoveryPolicy = char(string(cfg_postRecoveryPolicy));
end
cfg43.repro.postRecoveryPolicy = normalize_post_recovery_policy_43_(cfg43.repro.postRecoveryPolicy);
if ~isfield(cfg43.repro, 'resultSourceForTable') || isempty(cfg43.repro.resultSourceForTable)
    cfg43.repro.resultSourceForTable = 'raw';
end
if ~isempty(strtrim(cfg_resultSourceForTable))
    cfg43.repro.resultSourceForTable = char(string(cfg_resultSourceForTable));
end
cfg43.repro.resultSourceForTable = normalize_result_source_43_(cfg43.repro.resultSourceForTable);
if ~isfield(cfg43.repro, 'dominanceMode') || isempty(cfg43.repro.dominanceMode)
    cfg43.repro.dominanceMode = 'diag';
end
if ~isempty(strtrim(cfg_dominanceMode))
    cfg43.repro.dominanceMode = char(string(cfg_dominanceMode));
end
cfg43.repro.dominanceMode = normalize_dominance_mode_43_(cfg43.repro.dominanceMode);
if ~isfield(cfg43.repro, 'dominanceCurvePolicy') || isempty(cfg43.repro.dominanceCurvePolicy)
    cfg43.repro.dominanceCurvePolicy = 'paired_run';
end
if ~isempty(strtrim(cfg_dominanceCurvePolicy))
    cfg43.repro.dominanceCurvePolicy = char(string(cfg_dominanceCurvePolicy));
end
cfg43.repro.dominanceCurvePolicy = normalize_dominance_curve_policy_43_(cfg43.repro.dominanceCurvePolicy);
if ~isfield(cfg43.repro, 'curvePolicyUnified')
    cfg43.repro.curvePolicyUnified = true;
end
cfg43.repro.curvePolicyUnified = logical(cfg_curvePolicyUnified);

if isfinite(env_maxBatches) && env_maxBatches > 0
    cfg43.repro.maxBatches = round(env_maxBatches);
end
if ~isfield(cfg43.repro, 'earlyStopOnPass')
    cfg43.repro.earlyStopOnPass = false;
end
cfg43.repro.earlyStopOnPass = logical(env_earlyStopOnPass);
if ~isfield(cfg43.repro, 'gatePolicy') || isempty(cfg43.repro.gatePolicy)
    cfg43.repro.gatePolicy = 'two_stage';
end
if ~isempty(strtrim(env_gatePolicy))
    cfg43.repro.gatePolicy = char(string(env_gatePolicy));
end
cfg43.repro.gatePolicy = lower(strtrim(char(string(cfg43.repro.gatePolicy))));
if ~any(strcmp(cfg43.repro.gatePolicy, {'two_stage', 'single_stage'}))
    warning('run_section_43:invalidGatePolicy', ...
        'SECTION43_REPRO_GATE_POLICY=%s 无效，已回退为 two_stage。', stringify_safe_(cfg43.repro.gatePolicy));
    cfg43.repro.gatePolicy = 'two_stage';
end
if ~isfield(cfg43.repro, 'parallelEnable')
    cfg43.repro.parallelEnable = false;
end
cfg43.repro.parallelEnable = logical(cfg_parallelEnable);
if ~isfield(cfg43.repro, 'parallelWorkers')
    cfg43.repro.parallelWorkers = 0;
end
if isfinite(cfg_parallelWorkers) && cfg_parallelWorkers >= 0
    cfg43.repro.parallelWorkers = round(double(cfg_parallelWorkers));
end
if ~isfield(cfg43.repro, 'parallelLogLevel') || isempty(cfg43.repro.parallelLogLevel)
    cfg43.repro.parallelLogLevel = 'detailed';
end
if ~isempty(strtrim(cfg_parallelLogLevel))
    cfg43.repro.parallelLogLevel = char(string(cfg_parallelLogLevel));
end
cfg43.repro.parallelLogLevel = normalize_parallel_log_level_43_(cfg43.repro.parallelLogLevel);
if ~isfield(cfg43.repro, 'paperGsaaEnsureOps')
    cfg43.repro.paperGsaaEnsureOps = true;
end
cfg43.repro.paperGsaaEnsureOps = logical(cfg_paperGsaaEnsureOps);
if ~isfield(cfg43.repro, 'dominanceHardEnable')
    cfg43.repro.dominanceHardEnable = false;
end
cfg43.repro.dominanceHardEnable = logical(cfg_dominanceHardEnable);
if ~isfield(cfg43.repro, 'dominanceMinRatio') || ~isfinite(double(cfg43.repro.dominanceMinRatio))
    cfg43.repro.dominanceMinRatio = 0.95;
end
if isfinite(cfg_dominanceMinRatio) && cfg_dominanceMinRatio >= 0 && cfg_dominanceMinRatio <= 1
    cfg43.repro.dominanceMinRatio = double(cfg_dominanceMinRatio);
end
if strcmp(cfg43.repro.dominanceMode, 'off') || strcmp(cfg43.repro.dominanceMode, 'diag')
    cfg43.repro.dominanceHardEnable = false;
elseif strcmp(cfg43.repro.dominanceMode, 'hard')
    cfg43.repro.dominanceHardEnable = true;
end

if strcmp(cfg43.repro.trackMode, 'repro_baseline')
    cfg43.repro.postRecoveryPolicy = 'diag_only';
    cfg43.repro.resultSourceForTable = 'raw';
    if strcmp(cfg43.repro.dominanceMode, 'hard')
        cfg43.repro.dominanceMode = 'diag';
        cfg43.repro.dominanceHardEnable = false;
    end
end
cfg43.repro.paperGsaaEnsureOpsAuto = false;
if strcmp(cfg43.repro.trackMode, 'dominance_experiment') && strcmp(cfg43.repro.algoSuite, 'paper_suite') && ~cfg43.repro.paperGsaaEnsureOps
    cfg43.repro.paperGsaaEnsureOps = true;
    cfg43.repro.paperGsaaEnsureOpsAuto = true;
end
if ~isempty(strtrim(env_pickPolicy))
    cfg43.repro.pickPolicy = char(string(env_pickPolicy));
end
if isfinite(env_costTolPct) && env_costTolPct > 0
    cfg43.repro.targetCostTolPct = double(env_costTolPct);
end
if isfinite(env_timeBenchRepeats) && env_timeBenchRepeats > 0
    cfg43.repro.timeBenchmarkRepeats = round(env_timeBenchRepeats);
end
if ~isempty(strtrim(env_curvePlateauProfile))
    cfg43.repro.plateauProfile = char(string(env_curvePlateauProfile));
end

if ~isfield(cfg43.repro, 'curveAggregate') || isempty(cfg43.repro.curveAggregate)
    cfg43.repro.curveAggregate = 'best_run';
end
if ~isfield(cfg43.repro, 'curveSelectionPolicy') || isempty(cfg43.repro.curveSelectionPolicy)
    cfg43.repro.curveSelectionPolicy = 'paired_run';
end
if ~isempty(strtrim(cfg_curveSelectionPolicy))
    cfg43.repro.curveSelectionPolicy = char(string(cfg_curveSelectionPolicy));
end
if logical(getfield_safe_(cfg43.repro, 'curvePolicyUnified', true))
    % 统一口径：展示曲线与领先判定均使用 paired_run，避免“图和判定口径分离”。
    cfg43.repro.curveSelectionPolicy = 'paired_run';
    cfg43.repro.dominanceCurvePolicy = 'paired_run';
end
if ~isfield(cfg43.repro, 'curvePairedRunPick') || isempty(cfg43.repro.curvePairedRunPick)
    cfg43.repro.curvePairedRunPick = 'min_shape_score';
end
if ~isempty(strtrim(cfg_curvePairedRunPick))
    cfg43.repro.curvePairedRunPick = char(string(cfg_curvePairedRunPick));
end
if ~isfield(cfg43.repro, 'figureHardGateEnable')
    cfg43.repro.figureHardGateEnable = true;
end
cfg43.repro.figureHardGateEnable = logical(cfg_figureHardGateEnable);
if ~isfield(cfg43.repro, 'figureRefSource') || isempty(cfg43.repro.figureRefSource)
    cfg43.repro.figureRefSource = 'pdf_extract';
end
if ~isempty(strtrim(cfg_figureRefSource))
    cfg43.repro.figureRefSource = char(string(cfg_figureRefSource));
end
if strcmpi(strtrim(char(string(cfg43.repro.figureRefSource))), 'none')
    if strcmpi(strtrim(char(string(cfg43.repro.curveSelectionPolicy))), 'paired_run')
        warning('run_section_43:pairedRunWithoutRef', ...
            'SECTION43_FIGURE_REF_SOURCE=none 时，paired_run 会导致图表口径错位；已自动回退为 best_run（与表MIN一致）。');
        cfg43.repro.curveSelectionPolicy = 'best_run';
    end
    if strcmpi(strtrim(char(string(cfg43.repro.dominanceCurvePolicy))), 'paired_run')
        warning('run_section_43:dominancePairedRunWithoutRef', ...
            'SECTION43_FIGURE_REF_SOURCE=none 时，dominanceCurvePolicy=paired_run 会与展示曲线口径错位；已自动回退为 best_run。');
        cfg43.repro.dominanceCurvePolicy = 'best_run';
    end
    if cfg43.repro.figureHardGateEnable
        warning('run_section_43:figureHardGateWithoutRef', ...
            'SECTION43_FIGURE_REF_SOURCE=none 时无法执行锚点硬门槛；已自动关闭 figureHardGateEnable（仍执行基础图形门槛）。');
        cfg43.repro.figureHardGateEnable = false;
    end
end
if ~isfield(cfg43.repro, 'figureAnchorGens') || isempty(cfg43.repro.figureAnchorGens)
    cfg43.repro.figureAnchorGens = [1 10 20 30 40 50 80 100 130 cfg43.MaxGen];
end
if ~isfield(cfg43.repro, 'figureAnchorRelTol') || ~isfinite(double(cfg43.repro.figureAnchorRelTol))
    cfg43.repro.figureAnchorRelTol = 0.03;
end
if ~isfield(cfg43.repro, 'figureEndpointRelTol') || ~isfinite(double(cfg43.repro.figureEndpointRelTol))
    cfg43.repro.figureEndpointRelTol = 0.02;
end
if ~isfield(cfg43.repro, 'passRequiresFigureAndTable')
    cfg43.repro.passRequiresFigureAndTable = true;
end
cfg43.curveAggregate = cfg43.repro.curveAggregate; % 兼容字段

suiteInfo = algo_suite_info_43_(cfg_usePaperTest, cfg43.repro.algoSuite);
cfg_usePaperTest = logical(getfield_safe_(suiteInfo, 'usePaperTestChecks', cfg_usePaperTest));
if strcmp(cfg43.repro.trackMode, 'dominance_experiment')
    modeTag = 'dominanceMode';
elseif cfg_usePaperTest
    modeTag = 'reproMode';
else
    modeTag = 'algoCompare';
end

% ===== 数据源一致性校验 =====
fprintf('\n');
fprintf('=====================================================\n');
fprintf('[%s] 论文4.3节算法检验 - 数据源与参数校验\n', sectionName);
fprintf('=====================================================\n');
fprintf('[数据源] 文件名: %s\n', cfg43.dataFileName);
fprintf('[数据源] 完整路径: %s\n', fullfile(ctx.Meta.projectRoot, 'data', cfg43.dataFileName));
fprintf('[运行模式] SECTION43_USE_PAPER_TEST = %s\n', mat2str(cfg_usePaperTest));

fprintf('[数据校验] 期望客户数 n=%d, 充电站数 E=%d\n', cfg43.expected_n, cfg43.expected_E);
fprintf('[数据校验] 实际客户数 n=%d, 充电站数 E=%d\n', ctx.Data.n, ctx.Data.E);
specOk = (ctx.Data.n == cfg43.expected_n) && (ctx.Data.E == cfg43.expected_E);

depotCoord = ctx.Data.coord(1, :);
fprintf('[数据校验] 期望配送中心坐标: [%d, %d]\n', cfg43.expected_depot_coord(1), cfg43.expected_depot_coord(2));
fprintf('[数据校验] 实际配送中心坐标: [%.1f, %.1f]\n', depotCoord(1), depotCoord(2));
depotOk = all(abs(double(depotCoord(:)') - double(cfg43.expected_depot_coord(:)')) <= 1e-9);

if specOk && depotOk
    fprintf('[校验通过] 数据规格与论文4.1口径一致。\n');
else
    msg = sprintf('[数据校验失败] specOk=%d depotOk=%d。请检查 data/%s 与上下文数据口径。', specOk, depotOk, cfg43.dataFileName);
    if isfield(cfg43, 'requireStrictData') && cfg43.requireStrictData
        error('run_section_43:dataMismatch', '%s', msg);
    else
        warning('run_section_43:dataMismatch', '%s', msg);
    end
end

% ===== 参数打印（论文表4.2）=====
fprintf('\n[参数校验] 论文表4.2参数设置:\n');
fprintf('  种群规模 NP = %d\n', cfg43.NP);
fprintf('  最大迭代次数 MaxGen = %d\n', cfg43.MaxGen);
fprintf('  交叉概率 Pc = %.2f\n', cfg43.Pc);
fprintf('  变异概率 Pm = %.2f\n', cfg43.Pm);
fprintf('  初始温度 T0 = %d\n', cfg43.T0);
fprintf('  终止温度 Tmin = %.2f\n', cfg43.Tmin);
fprintf('  温度衰减系数 alpha = %.2f\n', cfg43.alpha);
fprintf('  独立运行次数 NRun = %d\n', cfg43.NRun);
fprintf('=====================================================\n\n');

% ===== 构建 G 结构体 =====
G = build_G_from_ctx(ctx, ...
    'nCV', cfg43.nCV, ...
    'nEV', cfg43.nEV, ...
    'AllowCharging', true, ...
    'ForceChargeOnce', false, ...
    'ForceChargePolicy', 'ANY_EV');
algoCtxTemplate = build_algo_contexts_43_(G, cfg43, suiteInfo);

% ===== 输出路径 =====
paths = output_paths(ctx.Meta.projectRoot, sectionName, ctx.Meta.runTag);
sig = build_signature(ctx);

if cfg_verbose
    fprintf('[%s] runTag=%s | modeTag=%s | paramSig=%s\n', ...
        sectionName, ctx.Meta.runTag, modeTag, sig.param.short);
    fprintf('[%s] 分轨配置：trackMode=%s | algoSuite=%s | postRecoveryPolicy=%s | resultSource=%s | dominanceMode=%s(%s)\n', ...
        sectionName, stringify_safe_(cfg43.repro.trackMode), stringify_safe_(suiteInfo.tag), ...
        stringify_safe_(cfg43.repro.postRecoveryPolicy), stringify_safe_(cfg43.repro.resultSourceForTable), ...
        stringify_safe_(cfg43.repro.dominanceMode), stringify_safe_(cfg43.repro.dominanceCurvePolicy));
    fprintf('[%s] 曲线口径统一开关：curvePolicyUnified=%d\n', ...
        sectionName, logical(getfield_safe_(cfg43.repro, 'curvePolicyUnified', true)));
    if logical(getfield_safe_(cfg43.repro, 'paperGsaaEnsureOpsAuto', false))
        fprintf('[%s] dominance_experiment 检测：paper_suite 下已自动启用 GSAA 关键算子保真（SECTION43_PAPER_GSAA_ENSURE_OPS=1）。\n', sectionName);
    end
    fprintf('[%s] 批次复现配置：maxBatches=%d | earlyStopOnPass=%d | gatePolicy=%s | pickPolicy=%s | targetCostTol=%.2f%% | parallel=%d(workers=%d) | parallelLogLevel=%s\n', ...
        sectionName, cfg43.repro.maxBatches, logical(cfg43.repro.earlyStopOnPass), ...
        stringify_safe_(cfg43.repro.gatePolicy), ...
        stringify_safe_(cfg43.repro.pickPolicy), 100*cfg43.repro.targetCostTolPct, ...
        logical(cfg43.repro.parallelEnable), round(double(cfg43.repro.parallelWorkers)), stringify_safe_(cfg43.repro.parallelLogLevel));
    fprintf('[%s] GSAA领先门槛：enable=%d | minRatio=%.2f\n', ...
        sectionName, logical(cfg43.repro.dominanceHardEnable), double(cfg43.repro.dominanceMinRatio));
    fprintf('[%s] 算法套件: %s | GSAA=%s | GA=%s | SA=%s\n', ...
        sectionName, suiteInfo.tag, suiteInfo.gsaaImpl, suiteInfo.gaImpl, suiteInfo.saImpl);
    print_algo_context_diag_43_(sectionName, suiteInfo, algoCtxTemplate, cfg43);
    fprintf('[%s] 日志字段统一: feasible/recovered/best/time/initFeas/firstFeasGen/stopGen/penaltyBest\n', sectionName);
end
fprintf('[%s][ALGO_SUITE] tag=%s | GSAA=%s | GA=%s | SA=%s\n', ...
    sectionName, suiteInfo.tag, suiteInfo.gsaaImpl, suiteInfo.gaImpl, suiteInfo.saImpl);

maxBatches = max(1, round(double(cfg43.repro.maxBatches)));
batchRecords = repmat(init_batch_record_(), maxBatches, 1);
executedBatches = 0;
earlyStopTriggered = false;
earlyStopBatch = NaN;
firstFullPassBatch = NaN;
parallelCtl = resolve_parallel_control_(cfg43, cfg_verbose, sectionName);
if cfg_usePaperTest
    refCtl = struct('source', char(string(cfg43.repro.figureRefSource)), ...
        'cacheEnable', logical(cfg_refCacheEnable), 'cacheForceRefresh', logical(cfg_refCacheForceRefresh));
    figureRef = struct('available', false, 'source', stringify_safe_(cfg43.repro.figureRefSource), 'sig', '', ...
        'reason', 'lazy_not_requested', 'curves', struct('GSAA', [], 'GA', [], 'SA', []), ...
        'path', '', 'reportPath', '');
    figureRefLoaded = false;
    if strcmpi(cfg43.repro.gatePolicy, 'single_stage')
        figureRef = load_figure_ref_43_(ctx, cfg43, cfg_refPdf, paths, sig, refCtl);
        figureRefLoaded = true;
    end
else
    figureRef = struct('available', false, 'source', 'disabled_non_paper_test', 'sig', '', ...
        'reason', 'skipped_non_paper_test', 'curves', struct('GSAA', [], 'GA', [], 'SA', []), ...
        'path', '', 'reportPath', '');
    figureRefLoaded = true;
end
if cfg_verbose
    fprintf('[%s] 批次与运行关系：每批NRun=%d；总运行次数=%d（每算法，NRun*maxBatches）\n', ...
        sectionName, cfg43.NRun, cfg43.NRun * maxBatches);
    fprintf('[%s] 图4.8口径: gatePolicy=%s | curveSelectionPolicy=%s | curvePairedRunPick=%s | figureHardGateEnable=%d | dominanceHardEnable=%d(min=%.2f) | figureRefSource=%s | refCacheEnable=%d | refCacheForceRefresh=%d | refAvailable=%d\n', ...
        sectionName, stringify_safe_(cfg43.repro.gatePolicy), ...
        stringify_safe_(cfg43.repro.curveSelectionPolicy), stringify_safe_(cfg43.repro.curvePairedRunPick), logical(cfg43.repro.figureHardGateEnable), ...
        logical(cfg43.repro.dominanceHardEnable), double(cfg43.repro.dominanceMinRatio), ...
        stringify_safe_(cfg43.repro.figureRefSource), ...
        logical(cfg_refCacheEnable), logical(cfg_refCacheForceRefresh), logical(figureRef.available));
end

for batch = 1:maxBatches
    modeTagBatch = sprintf('%s_batch%02d', modeTag, batch);

    fprintf('\n[%s] ===== 批次 %d/%d (%s) | suite=%s =====\n', ...
        sectionName, batch, maxBatches, modeTagBatch, suiteInfo.tag);

    [results, runSeedInfo] = run_single_batch_(batch, cfg43, cfg_usePaperTest, cfg_verbose, sectionName, parallelCtl, suiteInfo, algoCtxTemplate);

    tbl43_raw = build_table43(results);
    [tbl43, tbl43MinInfo] = table43_add_min_summary_row_43(tbl43_raw, 'MIN');

    benchTimes = benchmark_time_order_(results, batch, cfg43, algoCtxTemplate, suiteInfo, cfg_usePaperTest);

    tablePrecheck = true;
    figureCheckTriggered = false;
    figureCheckReason = 'single_stage';

    if cfg_usePaperTest && strcmpi(cfg43.repro.gatePolicy, 'two_stage')
        cfg43Pre = cfg43;
        cfg43Pre.repro.figureHardGateEnable = false;
        cfg43Pre.repro.passRequiresFigureAndTable = false;

        [gsaaCurvePlot, gaCurvePlot, saCurvePlot, curveMeta] = build_curve_plots_(results, cfg43Pre, figureRef);
        [curveMeta, curveMetaDiag] = sanitize_curve_meta_(curveMeta);
        curveMeta.missingDiag = curveMetaDiag;

        preAudit = build_repro_audit_43_(results, tbl43MinInfo, cfg43Pre, cfg_usePaperTest, benchTimes, ...
            gsaaCurvePlot, gaCurvePlot, saCurvePlot, curveMeta);
        tablePrecheck = logical(getfield_safe_(preAudit, 'tablePass', false));

        if tablePrecheck
            figureCheckTriggered = true;
            figureCheckReason = 'triggered_by_table_precheck_pass';

            if ~figureRefLoaded
                figureRef = load_figure_ref_43_(ctx, cfg43, cfg_refPdf, paths, sig, refCtl);
                figureRefLoaded = true;
                if cfg_verbose
                    fprintf('[%s] 批次%d 触发图严格校验，已加载图参考 source=%s available=%d\n', ...
                        sectionName, batch, stringify_safe_(getfield_safe_(figureRef, 'source', '')), logical(getfield_safe_(figureRef, 'available', false)));
                end
            end

            [gsaaCurvePlot, gaCurvePlot, saCurvePlot, curveMeta] = build_curve_plots_(results, cfg43, figureRef);
            [curveMeta, curveMetaDiag] = sanitize_curve_meta_(curveMeta);
            curveMeta.missingDiag = curveMetaDiag;

            audit = build_repro_audit_43_(results, tbl43MinInfo, cfg43, cfg_usePaperTest, benchTimes, ...
                gsaaCurvePlot, gaCurvePlot, saCurvePlot, curveMeta);
        else
            figureCheckReason = 'skipped_table_precheck_failed';
            audit = preAudit;
            audit.checks = remove_check_by_name_(getfield_safe_(audit, 'checks', struct('name',{},'pass',{},'actual',{},'expected',{},'group',{})), 'figure_hard_gate_disabled');
            audit.checks = append_check_(audit.checks, 'figure_check_skipped_table_precheck', ...
                true, 'tablePrecheck=false', 'skip strict figure checks in two_stage', 'diag');
            audit.figurePass = false;
            audit.pass = false;
        end
    else
        if cfg_usePaperTest && ~figureRefLoaded
            figureRef = load_figure_ref_43_(ctx, cfg43, cfg_refPdf, paths, sig, refCtl);
            figureRefLoaded = true;
        end

        [gsaaCurvePlot, gaCurvePlot, saCurvePlot, curveMeta] = build_curve_plots_(results, cfg43, figureRef);
        [curveMeta, curveMetaDiag] = sanitize_curve_meta_(curveMeta);
        curveMeta.missingDiag = curveMetaDiag;

        audit = build_repro_audit_43_(results, tbl43MinInfo, cfg43, cfg_usePaperTest, benchTimes, ...
            gsaaCurvePlot, gaCurvePlot, saCurvePlot, curveMeta);
        tablePrecheck = logical(getfield_safe_(audit, 'tablePass', false));
        if cfg_usePaperTest
            figureCheckTriggered = true;
            figureCheckReason = 'single_stage_triggered';
        else
            figureCheckTriggered = false;
            figureCheckReason = 'skipped_non_paper_test';
        end
    end
    audit = apply_gate_metadata_(audit, cfg43.repro.gatePolicy, tablePrecheck, figureCheckTriggered, figureCheckReason);
    results.curves = struct('GSAA', results.gsaaCurves, 'GA', results.gaCurves, 'SA', results.saCurves, ...
        'plotGSAA', gsaaCurvePlot, 'plotGA', gaCurvePlot, 'plotSA', saCurvePlot, ...
        'aggregateMode', stringify_safe_(cfg43.repro.curveSelectionPolicy), 'curveMeta', curveMeta, 'figureRef', figureRef);
    audit.score = score_batch_(audit, cfg43);

    auditPath = fullfile(paths.logs, artifact_filename('section43_repro_audit', sectionName, modeTagBatch, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.txt'));
    write_repro_audit_report_(auditPath, audit);

    batchMatPath = fullfile(paths.mats, artifact_filename('section43_batch_results', sectionName, modeTagBatch, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.mat'));
    try
        save(batchMatPath, 'results', 'tbl43', 'tbl43_raw', 'tbl43MinInfo', 'audit', 'benchTimes', 'curveMeta', 'runSeedInfo');
    catch
        batchMatPath = '';
    end

    batchRecords(batch).batch = batch;
    batchRecords(batch).modeTag = modeTagBatch;
    batchRecords(batch).results = results;
    batchRecords(batch).tbl43 = tbl43;
    batchRecords(batch).tbl43_raw = tbl43_raw;
    batchRecords(batch).tbl43MinInfo = tbl43MinInfo;
    batchRecords(batch).curvePlot = struct('GSAA', gsaaCurvePlot, 'GA', gaCurvePlot, 'SA', saCurvePlot);
    batchRecords(batch).curveMeta = curveMeta;
    batchRecords(batch).benchTimes = benchTimes;
    batchRecords(batch).audit = audit;
    batchRecords(batch).auditPath = auditPath;
    batchRecords(batch).batchMatPath = batchMatPath;
    batchRecords(batch).runSeedInfo = runSeedInfo;
    executedBatches = batch;
    if isnan(firstFullPassBatch) && logical(audit.pass)
        firstFullPassBatch = batch;
    end

    if cfg_verbose
        fprintf('[%s] 批次%d审计: %s | score=%.6f | 报告=%s\n', ...
            sectionName, batch, ternary_str_(audit.pass, 'PASS', 'FAIL'), audit.score, auditPath);
    end

    if cfg_usePaperTest && logical(cfg43.repro.earlyStopOnPass) && audit.pass
        earlyStopTriggered = true;
        earlyStopBatch = batch;
        if cfg_verbose
            fprintf('[%s] 批次%d 首次达到PASS，按 earlyStopOnPass=true 提前结束后续批次。\n', sectionName, batch);
        end
        break;
    end
end

if executedBatches < 1
    error('run_section_43:noBatchExecuted', '未执行任何批次，无法生成 section_43 结果。');
end
batchRecordsEval = batchRecords(1:executedBatches);
[selectedBatch, selectedReason, passBatchIdx] = pick_batch_(batchRecordsEval, cfg43.repro.pickPolicy);
selected = batchRecordsEval(selectedBatch);
if ~isempty(passBatchIdx)
    passBatchIdx = arrayfun(@(k) getfield_safe_(batchRecordsEval(k), 'batch', k), passBatchIdx(:)');
end
selectedBatch = getfield_safe_(selected, 'batch', selectedBatch);
if earlyStopTriggered
    selectedReason = sprintf('policy=%s; early_stop_on_pass=true, stopped at first PASS batch=%d', ...
        stringify_safe_(cfg43.repro.pickPolicy), earlyStopBatch);
end
[selected.curveMeta, curveMetaDiagFinal] = sanitize_curve_meta_(selected.curveMeta);
selected.curveMeta.missingDiag = curveMetaDiagFinal;

% ===== 选中批次数据签名 =====
dataIntegrity = compute_data_integrity_(selected.results);
try
    integrityPath = fullfile(paths.mats, artifact_filename('SECTION43_数据完整性签名', sectionName, selected.modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.mat'));
    save(integrityPath, 'dataIntegrity');
catch
end

if cfg_printTables
    fprintf('\n===== 表4.3 算法对比（选中批次 batch=%d）=====\n', selectedBatch);
    disp(selected.tbl43_raw);

    fprintf('\n===== 汇总统计（选中批次）=====\n');
    fprintf('GSAA: 最小成本=%.2f, 累计时间=%.2fs\n', finite_min_(selected.results.gsaaCosts), finite_sum_(selected.results.gsaaTimes));
    fprintf('GA:   最小成本=%.2f, 累计时间=%.2fs\n', finite_min_(selected.results.gaCosts), finite_sum_(selected.results.gaTimes));
    fprintf('SA:   最小成本=%.2f, 累计时间=%.2fs\n', finite_min_(selected.results.saCosts), finite_sum_(selected.results.saTimes));
    fprintf('可行率: GSAA=%.0f%%, GA=%.0f%%, SA=%.0f%%\n', ...
        100*mean(selected.results.gsaaFeasible), 100*mean(selected.results.gaFeasible), 100*mean(selected.results.saFeasible));
    minGsaaCost = finite_min_(selected.results.gsaaCosts);
    minGaCost = finite_min_(selected.results.gaCosts);
    minSaCost = finite_min_(selected.results.saCosts);
    fprintf('最小GAP(GA)=%.2f%%, 最小GAP(SA)=%.2f%%\n', ...
        gap_from_mins_(minGsaaCost, minGaCost), gap_from_mins_(minGsaaCost, minSaCost));

    fprintf('\n===== 表4.3（追加MIN汇总行，选中批次）=====\n');
    disp(selected.tbl43);
end

% ===== 导出最终表格（带batch标签） =====
t43BaseXlsxPath = fullfile(paths.tables, artifact_filename('算法对比', sectionName, selected.modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.xlsx'));
artTable = export_table43_artifacts_43(selected.tbl43, selected.tbl43MinInfo, paths, sectionName, selected.modeTag, sig, ctx.Meta.timestamp, ...
    'BaseXlsxPath', t43BaseXlsxPath, 'ExportRich', cfg_exportRichTable);
t43Path = artTable.tablePath;

% ===== 绘制并导出图4.8（选中批次） =====
cfgPlot = cfg43;
cfgPlot.curveLineage = getfield_safe_(selected.curveMeta, 'curvePolicy', '');
cfgPlot.curveRunIdx = getfield_safe_(selected.curveMeta, 'curveRunIdx', NaN);
cfgPlot.figureRefSig = getfield_safe_(selected.curveMeta, 'figureRefSig', '');
fig = plot_iteration_curve_43(selected.curvePlot.GSAA, selected.curvePlot.GA, selected.curvePlot.SA, cfgPlot);
figPath = fullfile(paths.figures, artifact_filename('算法迭代曲线', sectionName, selected.modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.png'));
hide_axes_toolbar_(fig);
try
    exportgraphics(fig, figPath, 'Resolution', 300);
catch
    saveas(fig, figPath);
end
if ~cfg_keepFigures
    close(fig);
end

% ===== 验证报告（选中批次） =====
verifyReportPath = '';
verify = struct();
if cfg_verifyEnable
    verifyOutDir = fullfile(paths.logs, 'verify');
    verify = verify_section43_artifacts_43(ctx.Meta.projectRoot, cfg_refPdf, paths, sig, ctx.Meta.timestamp, ...
        'GeneratedFigPath', figPath, ...
        'GeneratedTableArtifacts', artTable, ...
        'OutDir', verifyOutDir, ...
        'DataIntegrity', dataIntegrity);
    verifyReportPath = verify.reportPath;
end

% ===== 批次汇总审计 =====
batchSummaryPath = fullfile(paths.logs, artifact_filename('section43_repro_batch_summary', sectionName, modeTag, sig.param.short, sig.data.short, ctx.Meta.timestamp, '.txt'));
summaryCtl = struct('configuredMaxBatches', maxBatches, 'executedBatches', executedBatches, ...
    'earlyStopOnPass', logical(cfg43.repro.earlyStopOnPass), ...
    'earlyStopTriggered', earlyStopTriggered, 'earlyStopBatch', earlyStopBatch, ...
    'gatePolicy', stringify_safe_(cfg43.repro.gatePolicy), ...
    'trackMode', stringify_safe_(getfield_safe_(cfg43.repro, 'trackMode', 'repro_baseline')), ...
    'algoSuite', stringify_safe_(getfield_safe_(suiteInfo, 'tag', '')), ...
    'postRecoveryPolicy', stringify_safe_(getfield_safe_(cfg43.repro, 'postRecoveryPolicy', 'diag_only')), ...
    'resultSourceForTable', stringify_safe_(getfield_safe_(selected.results, 'resultSourceForTable', getfield_safe_(cfg43.repro, 'resultSourceForTable', 'raw'))), ...
    'firstFullPassBatch', firstFullPassBatch, ...
    'paperGsaaEnsureOps', logical(getfield_safe_(cfg43.repro, 'paperGsaaEnsureOps', false)), ...
    'paperGsaaOpsApplied', logical(getfield_safe_(algoCtxTemplate, 'paperGsaaOpsApplied', false)), ...
    'paperGsaaOpsNote', stringify_safe_(getfield_safe_(algoCtxTemplate, 'note', '')), ...
    'parallelEnable', logical(getfield_safe_(parallelCtl, 'enabled', false)), ...
    'parallelWorkers', double(getfield_safe_(parallelCtl, 'workersActive', 1)), ...
    'parallelReason', stringify_safe_(getfield_safe_(parallelCtl, 'reason', '')), ...
    'parallelLogLevel', stringify_safe_(getfield_safe_(cfg43.repro, 'parallelLogLevel', 'detailed')));
write_repro_batch_summary_report_(batchSummaryPath, batchRecordsEval, selectedBatch, selectedReason, passBatchIdx, cfg43, cfg_usePaperTest, summaryCtl);

% ===== 输出结果 =====
out = struct();
out.meta = struct('sectionName', sectionName, 'modeTag', selected.modeTag, 'runTag', ctx.Meta.runTag, ...
    'timestamp', ctx.Meta.timestamp, 'paramSig', sig.param, 'dataSig', sig.data, ...
    'selectedBatch', selectedBatch, 'pickPolicy', stringify_safe_(cfg43.repro.pickPolicy), ...
    'trackMode', stringify_safe_(getfield_safe_(cfg43.repro, 'trackMode', 'repro_baseline')), ...
    'algoSuite', stringify_safe_(getfield_safe_(suiteInfo, 'tag', '')), ...
    'postRecoveryPolicy', stringify_safe_(getfield_safe_(cfg43.repro, 'postRecoveryPolicy', 'diag_only')), ...
    'resultSourceForTable', stringify_safe_(getfield_safe_(selected.results, 'resultSourceForTable', getfield_safe_(cfg43.repro, 'resultSourceForTable', 'raw'))), ...
    'maxBatches', maxBatches, 'executedBatches', executedBatches, ...
    'gatePolicy', stringify_safe_(cfg43.repro.gatePolicy), ...
    'firstFullPassBatch', firstFullPassBatch, ...
    'earlyStopOnPass', logical(cfg43.repro.earlyStopOnPass), ...
    'earlyStopTriggered', earlyStopTriggered, 'earlyStopBatch', earlyStopBatch, ...
    'paperGsaaEnsureOps', logical(getfield_safe_(cfg43.repro, 'paperGsaaEnsureOps', false)), ...
    'paperGsaaOpsApplied', logical(getfield_safe_(algoCtxTemplate, 'paperGsaaOpsApplied', false)), ...
    'paperGsaaOpsNote', stringify_safe_(getfield_safe_(algoCtxTemplate, 'note', '')), ...
    'parallelEnable', logical(getfield_safe_(parallelCtl, 'enabled', false)), ...
    'parallelWorkers', double(getfield_safe_(parallelCtl, 'workersActive', 1)), ...
    'parallelReason', stringify_safe_(getfield_safe_(parallelCtl, 'reason', '')), ...
    'parallelLogLevel', stringify_safe_(getfield_safe_(cfg43.repro, 'parallelLogLevel', 'detailed')), ...
    'passedBatchCount', numel(passBatchIdx), ...
    'curveLineage', stringify_safe_(getfield_safe_(selected.curveMeta, 'curvePolicy', '')), ...
    'curveRunIdx', getfield_safe_(selected.curveMeta, 'curveRunIdx', NaN), ...
    'figureRefSig', stringify_safe_(getfield_safe_(selected.curveMeta, 'figureRefSig', '')), ...
    'dominanceMode', stringify_safe_(getfield_safe_(cfg43.repro, 'dominanceMode', 'diag')), ...
    'dominanceCurvePolicy', stringify_safe_(getfield_safe_(cfg43.repro, 'dominanceCurvePolicy', 'paired_run')), ...
    'dominanceHardEnable', logical(getfield_safe_(cfg43.repro, 'dominanceHardEnable', false)), ...
    'dominanceMinRatio', double(getfield_safe_(cfg43.repro, 'dominanceMinRatio', 0.95)));
out.meta.features = {'algoCompare', 'GSAA', 'GA', 'SA', 'reproBatchScheduler'};
out.paths = paths;
out.results = selected.results;
out.table43 = selected.tbl43;
out.table43_raw = selected.tbl43_raw;
out.batchRecords = batchRecordsEval;
out.reproAudit = selected.audit;
out.batchSummaryPath = batchSummaryPath;
out.verify = verify;
out.artifacts = struct('table43', t43Path, 'table43Artifacts', artTable, 'figPath', figPath, ...
    'verifyReport', verifyReportPath, 'reproAuditReport', selected.auditPath, 'batchSummaryReport', batchSummaryPath, ...
    'figureRefCurvePath', getfield_safe_(figureRef, 'path', ''), 'figureRefCurveReport', getfield_safe_(figureRef, 'reportPath', ''));

fprintf('\n[%s] 完成。输出文件:\n', sectionName);
fprintf('  选中批次: %d (%s)\n', selectedBatch, selected.modeTag);
fprintf('  选批理由: %s\n', selectedReason);
fprintf('  批次执行: %d/%d (earlyStopOnPass=%d, triggered=%d)\n', ...
    executedBatches, maxBatches, logical(cfg43.repro.earlyStopOnPass), earlyStopTriggered);
fprintf('  门控策略: %s | 首个图表双通过批次: %s\n', ...
    stringify_safe_(cfg43.repro.gatePolicy), stringify_safe_(firstFullPassBatch));
fprintf('  分轨模式: %s | 算法套件: %s | 表口径: %s | 恢复策略: %s\n', ...
    stringify_safe_(getfield_safe_(cfg43.repro, 'trackMode', 'repro_baseline')), ...
    stringify_safe_(suiteInfo.tag), ...
    stringify_safe_(getfield_safe_(selected.results, 'resultSourceForTable', getfield_safe_(cfg43.repro, 'resultSourceForTable', 'raw'))), ...
    stringify_safe_(getfield_safe_(cfg43.repro, 'postRecoveryPolicy', 'diag_only')));
fprintf('  并行执行: %d | workers=%d | logLevel=%s | reason=%s\n', ...
    logical(getfield_safe_(parallelCtl, 'enabled', false)), ...
    round(double(getfield_safe_(parallelCtl, 'workersActive', 1))), ...
    stringify_safe_(getfield_safe_(cfg43.repro, 'parallelLogLevel', 'detailed')), ...
    stringify_safe_(getfield_safe_(parallelCtl, 'reason', '')));
fprintf('  算法套件: %s | GSAA=%s | GA=%s | SA=%s\n', ...
    suiteInfo.tag, suiteInfo.gsaaImpl, suiteInfo.gaImpl, suiteInfo.saImpl);
    fprintf('  GSAA算子保真修补: enable=%d | applied=%d | note=%s\n', ...
    logical(getfield_safe_(cfg43.repro, 'paperGsaaEnsureOps', false)), ...
    logical(getfield_safe_(algoCtxTemplate, 'paperGsaaOpsApplied', false)), ...
    stringify_safe_(getfield_safe_(algoCtxTemplate, 'note', '')));
try
    fprintf('  曲线口径: %s | 同run索引: %s | refSig: %s\n', ...
        stringify_safe_(getfield_safe_(selected.curveMeta, 'curvePolicy', '')), ...
        stringify_safe_(getfield_safe_(selected.curveMeta, 'curveRunIdx', NaN)), ...
        stringify_safe_(getfield_safe_(selected.curveMeta, 'figureRefSig', '')));
catch ME
    warning('run_section_43:printCurveMeta', ...
        '曲线元信息打印失败（不中断）：%s', stringify_safe_(ME.message));
end
fprintf('  全程领先硬门槛: enable=%d | minRatio=%.2f\n', ...
    logical(getfield_safe_(cfg43.repro, 'dominanceHardEnable', false)), ...
    double(getfield_safe_(cfg43.repro, 'dominanceMinRatio', 0.95)));
fprintf('  全程领先口径: mode=%s | curvePolicy=%s\n', ...
    stringify_safe_(getfield_safe_(cfg43.repro, 'dominanceMode', 'diag')), ...
    stringify_safe_(getfield_safe_(cfg43.repro, 'dominanceCurvePolicy', 'paired_run')));
domPctFinal = 100 * double(getfield_safe_(getfield_safe_(selected.audit, 'metrics', struct()), 'gsaaDominanceRatio', NaN));
domCntFinal = double(getfield_safe_(getfield_safe_(selected.audit, 'metrics', struct()), 'gsaaDominanceCount', NaN));
domTotFinal = double(getfield_safe_(getfield_safe_(selected.audit, 'metrics', struct()), 'gsaaDominanceTotal', NaN));
if isfinite(domPctFinal) && isfinite(domCntFinal) && isfinite(domTotFinal) && domTotFinal > 0
    fprintf('  论文理想态诊断: GSAA全程领先比例=%.2f%% (%d/%d)\n', domPctFinal, round(domCntFinal), round(domTotFinal));
else
    fprintf('  论文理想态诊断: GSAA全程领先比例=NA\n');
end
fprintf('  表格: %s\n', t43Path);
fprintf('  图片: %s\n', figPath);
fprintf('  图参考曲线: %s\n', stringify_safe_(getfield_safe_(figureRef, 'path', '')));
fprintf('  批次审计: %s\n', selected.auditPath);
fprintf('  汇总审计: %s\n', batchSummaryPath);

if cfg_usePaperTest && ~selected.audit.pass
    error('run_section_43:reproAuditFailed', ...
        '%d批内无全量达标批次；已导出最接近批次=%d。失败摘要：%s', executedBatches, selectedBatch, selected.audit.failSummary);
elseif ~selected.audit.pass
    warning('run_section_43:reproAuditWarn', ...
        '非论文测试模式存在未达标检查项（已导出产物）。失败摘要：%s', selected.audit.failSummary);
end

end

% ===== 主流程辅助函数 =====
function rec = init_batch_record_()
rec = struct('batch', NaN, 'modeTag', '', 'results', struct(), 'tbl43', table(), ...
    'tbl43_raw', table(), 'tbl43MinInfo', struct(), 'curvePlot', struct(), 'curveMeta', struct(), ...
    'benchTimes', struct(), 'audit', struct(), 'auditPath', '', 'batchMatPath', '', 'runSeedInfo', struct());
end

function figureRef = load_figure_ref_43_(ctx, cfg43, cfg_refPdf, paths, sig, refCtl)
figureRef = struct('available', false, 'source', 'pdf_extract', 'sig', '', 'reason', 'not_loaded', ...
    'curves', struct('GSAA', [], 'GA', [], 'SA', []), 'path', '', 'reportPath', '');

if nargin < 6 || ~isstruct(refCtl)
    refCtl = struct();
end
refSource = lower(strtrim(stringify_safe_(getfield_safe_(refCtl, 'source', getfield_safe_(cfg43.repro, 'figureRefSource', 'pdf_extract')))));
if isempty(refSource)
    refSource = 'pdf_extract';
end
cacheEnable = logical(getfield_safe_(refCtl, 'cacheEnable', true));
cacheForceRefresh = logical(getfield_safe_(refCtl, 'cacheForceRefresh', false));

figureRef.source = refSource;

if strcmpi(refSource, 'none')
    figureRef.available = false;
    figureRef.reason = 'disabled_by_run_modes';
    return;
end

if ~strcmpi(refSource, 'pdf_extract')
    figureRef.available = false;
    figureRef.reason = ['unsupported_figure_ref_source:' refSource];
    return;
end

try
    if cacheEnable && ~cacheForceRefresh
        [cacheHit, cachePath, cacheRef] = load_ref_curve_cache_(paths.cache, sig);
        if cacheHit
            figureRef = cacheRef;
            figureRef.source = stringify_safe_(getfield_safe_(cacheRef, 'source', 'pdf_extract_cache'));
            figureRef.reason = 'loaded_from_cache';
            figureRef.path = cachePath;
            return;
        end
    end

    verifyOutDir = fullfile(paths.logs, 'verify');
    refOnly = verify_section43_artifacts_43(ctx.Meta.projectRoot, cfg_refPdf, paths, sig, ctx.Meta.timestamp, ...
        'OutDir', verifyOutDir, 'ReferenceOnly', true, 'MaxGen', cfg43.MaxGen);

    if isfield(refOnly, 'ref') && isfield(refOnly.ref, 'curveRef')
        c = refOnly.ref.curveRef;
        figureRef.available = logical(getfield_safe_(c, 'available', false));
        figureRef.source = stringify_safe_(getfield_safe_(c, 'source', 'pdf_extract'));
        figureRef.sig = stringify_safe_(getfield_safe_(c, 'sig', ''));
        figureRef.reason = stringify_safe_(getfield_safe_(c, 'reason', ''));
        figureRef.path = stringify_safe_(getfield_safe_(refOnly.ref, 'curveRefPath', ''));
        figureRef.reportPath = stringify_safe_(getfield_safe_(refOnly, 'reportPath', ''));
        if isfield(c, 'curves')
            figureRef.curves = c.curves;
        end

        if cacheEnable && figureRef.available && is_valid_curve_ref_(figureRef)
            save_ref_curve_cache_(paths.cache, sig, cfg43, figureRef, refOnly);
        end
    else
        figureRef.reason = 'ref_curve_not_returned';
    end
catch ME
    figureRef.available = false;
    figureRef.reason = ['ref_extract_exception: ' char(string(ME.message))];
end
end

function [ok, pathOut, ref] = load_ref_curve_cache_(cacheDir, sig)
ok = false;
pathOut = '';
ref = struct();
try
    [payload, cachePath] = cache_load_best(cacheDir, 'section43_figure_ref', sig.param.full, sig.data.full, 'ForceRecompute', false);
    if isempty(payload) || ~isstruct(payload)
        return;
    end

    if isfield(payload, 'figureRef') && isstruct(payload.figureRef)
        cand = payload.figureRef;
    elseif isfield(payload, 'curveRef') && isstruct(payload.curveRef)
        cand = struct('available', logical(getfield_safe_(payload.curveRef, 'available', false)), ...
            'source', stringify_safe_(getfield_safe_(payload.curveRef, 'source', 'pdf_extract_cache')), ...
            'sig', stringify_safe_(getfield_safe_(payload.curveRef, 'sig', '')), ...
            'reason', stringify_safe_(getfield_safe_(payload.curveRef, 'reason', '')), ...
            'curves', getfield_safe_(payload.curveRef, 'curves', struct('GSAA', [], 'GA', [], 'SA', [])), ...
            'path', stringify_safe_(getfield_safe_(payload, 'curveRefPath', '')), ...
            'reportPath', stringify_safe_(getfield_safe_(payload, 'reportPath', '')));
    else
        return;
    end

    if ~logical(getfield_safe_(cand, 'available', false)) || ~is_valid_curve_ref_(cand)
        return;
    end

    ok = true;
    pathOut = cachePath;
    ref = cand;
catch
    ok = false;
    pathOut = '';
    ref = struct();
end
end

function save_ref_curve_cache_(cacheDir, sig, cfg43, figureRef, refOnly)
try
    payload = struct();
    payload.figureRef = figureRef;
    payload.curveRefPath = stringify_safe_(getfield_safe_(getfield_safe_(refOnly, 'ref', struct()), 'curveRefPath', getfield_safe_(figureRef, 'path', '')));
    payload.reportPath = stringify_safe_(getfield_safe_(refOnly, 'reportPath', getfield_safe_(figureRef, 'reportPath', '')));

    meta = struct();
    meta.sectionName = 'section_43';
    meta.modeTag = 'verify';
    meta.timestamp = datestr(now, 'yyyymmddTHHMMSS');
    meta.paramSig = sig.param;
    meta.dataSig = sig.data;
    meta.source = stringify_safe_(getfield_safe_(figureRef, 'source', 'pdf_extract'));
    meta.maxGen = double(getfield_safe_(cfg43, 'MaxGen', 300));
    meta.extractorVersion = 'section43_ref_cache_v1';

    cache_save(cacheDir, 'section43_figure_ref', payload, meta);
catch
end
end

function tf = is_valid_curve_ref_(figureRef)
tf = false;
try
    if ~isstruct(figureRef) || ~isfield(figureRef, 'curves')
        return;
    end
    c = figureRef.curves;
    if ~(isfield(c, 'GSAA') && isfield(c, 'GA') && isfield(c, 'SA'))
        return;
    end
    tf = ~isempty(c.GSAA) && ~isempty(c.GA) && ~isempty(c.SA);
catch
    tf = false;
end
end

function ctl = resolve_parallel_control_(cfg43, cfg_verbose, sectionName)
ctl = struct('requested', false, 'enabled', false, 'workersRequested', 0, ...
    'workersActive', 1, 'reason', 'disabled_by_switch');
try
    ctl.requested = logical(getfield_safe_(cfg43.repro, 'parallelEnable', false));
catch
    ctl.requested = false;
end
try
    w = double(getfield_safe_(cfg43.repro, 'parallelWorkers', 0));
    if ~isfinite(w) || w < 0
        w = 0;
    end
    ctl.workersRequested = round(w);
catch
    ctl.workersRequested = 0;
end

if ~ctl.requested
    return;
end

if exist('parpool', 'file') ~= 2
    ctl.reason = 'parpool_not_available';
    return;
end

try
    hasParallelLicense = logical(license('test', 'Distrib_Computing_Toolbox'));
catch
    hasParallelLicense = false;
end
if ~hasParallelLicense
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
    ctl.workersActive = get_pool_workers_43_(pool, 1);
    ctl.reason = 'enabled';
catch ME
    ctl.enabled = false;
    ctl.workersActive = 1;
    ctl.reason = ['parallel_fallback_serial:' stringify_safe_(ME.identifier)];
    if cfg_verbose
        warning('run_section_43:parallelFallback', ...
            '[%s] 并行池初始化失败，已回退串行执行：%s', sectionName, stringify_safe_(ME.message));
    end
end
end

function n = get_pool_workers_43_(pool, def)
n = def;
try
    if ~isempty(pool) && isprop(pool, 'NumWorkers')
        v = double(pool.NumWorkers);
        if isfinite(v) && v >= 1
            n = v;
            return;
        end
    end
catch
end
end

function [results, runSeedInfo] = run_single_batch_(batch, cfg43, cfg_usePaperTest, cfg_verbose, sectionName, parallelCtl, suiteInfo, algoCtxTemplate)
NRun = cfg43.NRun;
parallelLogLevel = normalize_parallel_log_level_43_(getfield_safe_(cfg43.repro, 'parallelLogLevel', 'detailed'));

seedList = double(cfg43.repro.seedList(:)');
if numel(seedList) < NRun
    seedList = [seedList, 1:(NRun-numel(seedList))];
end
seedList = seedList(1:NRun);

offsetGSAA = double(cfg43.repro.algorithmSeedOffset.GSAA);
offsetGA = double(cfg43.repro.algorithmSeedOffset.GA);
offsetSA = double(cfg43.repro.algorithmSeedOffset.SA);
stride = double(cfg43.repro.batchSeedStride);

runDiag = repmat(init_run_diag_43_(cfg43.MaxGen), NRun, 1);

baseSeedVec = seedList(:) + (batch-1) * stride;
seedGSAAVec = baseSeedVec + offsetGSAA;
seedGAVec = baseSeedVec + offsetGA;
seedSAVec = baseSeedVec + offsetSA;
runSeedInfo = struct('baseSeed', baseSeedVec(:), 'seedGSAA', seedGSAAVec(:), 'seedGA', seedGAVec(:), 'seedSA', seedSAVec(:));

useParallel = false;
if nargin >= 7 && isstruct(parallelCtl)
    useParallel = logical(getfield_safe_(parallelCtl, 'enabled', false));
end
if NRun <= 1
    useParallel = false;
end

if nargin < 7 || ~isstruct(suiteInfo)
    suiteInfo = algo_suite_info_43_(cfg_usePaperTest, '');
end
if nargin < 8 || ~isstruct(algoCtxTemplate)
    error('run_section_43:missingAlgoContext', 'run_single_batch_ 缺少算法上下文模板（algoCtxTemplate）。');
end

logCtx = struct();
logCtx.enable = logical(cfg_verbose) && ~useParallel && strcmp(parallelLogLevel, 'detailed');
logCtx.sectionName = sectionName;
logCtx.batch = batch;
logCtx.nRun = NRun;
logCtx.suiteTag = stringify_safe_(suiteInfo.tag);

algoCtxRuntime = algoCtxTemplate;
if useParallel
    algoCtxRuntime = set_console_verbose_43_(algoCtxRuntime, false);
end

if useParallel
    if cfg_verbose
        fprintf('[%s] 批次%d 并行执行 NRun=%d (workers=%d)\n', ...
            sectionName, batch, NRun, round(double(getfield_safe_(parallelCtl, 'workersActive', 1))));
    end
    parfor run = 1:NRun
        runDiag(run) = run_single_replica_(seedGSAAVec(run), seedGAVec(run), seedSAVec(run), cfg43, algoCtxRuntime, suiteInfo, logCtx, run);
    end
else
    for run = 1:NRun
        runDiag(run) = run_single_replica_(seedGSAAVec(run), seedGAVec(run), seedSAVec(run), cfg43, algoCtxRuntime, suiteInfo, logCtx, run);
    end
end

if cfg_verbose
    emit_run_logs_43_(sectionName, batch, NRun, runSeedInfo, runDiag, parallelLogLevel, useParallel, suiteInfo);
end

src = normalize_result_source_43_(getfield_safe_(cfg43.repro, 'resultSourceForTable', 'raw'));
[resultsRaw, resultsRecovered, resultsActive] = compose_results_sources_43_(runDiag, cfg43, batch, src);
results = resultsActive;
results.raw = resultsRaw;
results.recovered = resultsRecovered;
results.resultSourceForTable = src;
results.postRecoveryPolicy = normalize_post_recovery_policy_43_(getfield_safe_(cfg43.repro, 'postRecoveryPolicy', 'diag_only'));
results.algoSuiteResolved = stringify_safe_(getfield_safe_(suiteInfo, 'tag', ''));
results.runDiag = runDiag;
end

function runDiag = run_single_replica_(seedGSAA, seedGA, seedSA, cfg43, algoCtx, suiteInfo, logCtx, runIdx)

if nargin < 7 || ~isstruct(logCtx)
    logCtx = struct('enable', false, 'sectionName', 'section_43', 'batch', NaN, 'nRun', NaN, 'suiteTag', '');
end
if nargin < 8 || ~isfinite(runIdx)
    runIdx = NaN;
end
if nargin < 5 || ~isstruct(algoCtx)
    error('run_section_43:missingAlgoContext', 'run_single_replica_ 缺少算法上下文（algoCtx）。');
end
if nargin < 6 || ~isstruct(suiteInfo)
    error('run_section_43:missingSuiteInfo', 'run_single_replica_ 缺少算法套件信息（suiteInfo）。');
end
if ~isfield(algoCtx, 'gsaa') || ~isstruct(algoCtx.gsaa)
    error('run_section_43:missingGsaaContext', 'algoCtx.gsaa 缺失，无法执行 GSAA。');
end
if ~isfield(algoCtx, 'ga') || ~isstruct(algoCtx.ga)
    algoCtx.ga = algoCtx.gsaa;
end
if ~isfield(algoCtx, 'sa') || ~isstruct(algoCtx.sa)
    algoCtx.sa = algoCtx.gsaa;
end

if logical(getfield_safe_(logCtx, 'enable', false))
    print_algo_start_43_(logCtx, runIdx, 'GSAA', seedGSAA);
end
[outGSAA, tGSAA] = solve_algo_with_seed_('GSAA', seedGSAA, cfg43, algoCtx.gsaa, suiteInfo);
if logical(getfield_safe_(logCtx, 'enable', false))
    print_algo_done_43_(logCtx, runIdx, 'GSAA', outGSAA, tGSAA);
end

if logical(getfield_safe_(logCtx, 'enable', false))
    print_algo_start_43_(logCtx, runIdx, 'GA', seedGA);
end
[outGA, tGA] = solve_algo_with_seed_('GA', seedGA, cfg43, algoCtx.ga, suiteInfo);
if logical(getfield_safe_(logCtx, 'enable', false))
    print_algo_done_43_(logCtx, runIdx, 'GA', outGA, tGA);
end

if logical(getfield_safe_(logCtx, 'enable', false))
    print_algo_start_43_(logCtx, runIdx, 'SA', seedSA);
end
[outSA, tSA] = solve_algo_with_seed_('SA', seedSA, cfg43, algoCtx.sa, suiteInfo);
if logical(getfield_safe_(logCtx, 'enable', false))
    print_algo_done_43_(logCtx, runIdx, 'SA', outSA, tSA);
end

rawGsaaCost = cost_from_out_(outGSAA);
rawGaCost = cost_from_out_(outGA);
rawSaCost = cost_from_out_(outSA);
rawGsaaCurve = curve_from_out_(outGSAA, cfg43.MaxGen);
rawGaCurve = curve_from_out_(outGA, cfg43.MaxGen);
rawSaCurve = curve_from_out_(outSA, cfg43.MaxGen);
rawDiag = struct();
rawDiag.gsaa = build_algo_diag_43_(outGSAA, rawGsaaCost, tGSAA, false);
rawDiag.ga = build_algo_diag_43_(outGA, rawGaCost, tGA, false);
rawDiag.sa = build_algo_diag_43_(outSA, rawSaCost, tSA, false);

outGSAARecovered = outGSAA;
outGARecovered = outGA;
outSARecovered = outSA;
gsaaRec = false;
gaRec = false;
saRec = false;
tGSAARecovered = tGSAA;
tGARecovered = tGA;
tSARecovered = tSA;

postRecoveryPolicy = normalize_post_recovery_policy_43_(getfield_safe_(cfg43.repro, 'postRecoveryPolicy', 'diag_only'));
if ~strcmp(postRecoveryPolicy, 'off')
    rng(double(seedGSAA) + 900001, 'twister');
    tRec = tic;
    [outGSAARecovered, gsaaRec] = recover_infeasible_result_(outGSAA, algoCtx.gsaa, cfg43.repro);
    tGSAARecovered = tGSAARecovered + toc(tRec);

    rng(double(seedGA) + 900001, 'twister');
    tRec = tic;
    [outGARecovered, gaRec] = recover_infeasible_result_(outGA, algoCtx.ga, cfg43.repro);
    tGARecovered = tGARecovered + toc(tRec);

    rng(double(seedSA) + 900001, 'twister');
    tRec = tic;
    [outSARecovered, saRec] = recover_infeasible_result_(outSA, algoCtx.sa, cfg43.repro);
    tSARecovered = tSARecovered + toc(tRec);
end

recoveredGsaaCost = cost_from_out_(outGSAARecovered);
recoveredGaCost = cost_from_out_(outGARecovered);
recoveredSaCost = cost_from_out_(outSARecovered);
recoveredGsaaCurve = curve_from_out_(outGSAARecovered, cfg43.MaxGen);
recoveredGaCurve = curve_from_out_(outGARecovered, cfg43.MaxGen);
recoveredSaCurve = curve_from_out_(outSARecovered, cfg43.MaxGen);
recoveredDiag = struct();
recoveredDiag.gsaa = build_algo_diag_43_(outGSAARecovered, recoveredGsaaCost, tGSAARecovered, gsaaRec);
recoveredDiag.ga = build_algo_diag_43_(outGARecovered, recoveredGaCost, tGARecovered, gaRec);
recoveredDiag.sa = build_algo_diag_43_(outSARecovered, recoveredSaCost, tSARecovered, saRec);

selectedSource = normalize_result_source_43_(getfield_safe_(cfg43.repro, 'resultSourceForTable', 'raw'));
if strcmp(selectedSource, 'recovered')
    selectedDiag = recoveredDiag;
    selectedGsaaCurve = recoveredGsaaCurve;
    selectedGaCurve = recoveredGaCurve;
    selectedSaCurve = recoveredSaCurve;
else
    selectedDiag = rawDiag;
    selectedGsaaCurve = rawGsaaCurve;
    selectedGaCurve = rawGaCurve;
    selectedSaCurve = rawSaCurve;
end

runDiag = init_run_diag_43_(cfg43.MaxGen);
runDiag.gsaa = selectedDiag.gsaa;
runDiag.ga = selectedDiag.ga;
runDiag.sa = selectedDiag.sa;
runDiag.raw = rawDiag;
runDiag.recovered = recoveredDiag;
runDiag.curveGSAA = selectedGsaaCurve;
runDiag.curveGA = selectedGaCurve;
runDiag.curveSA = selectedSaCurve;
runDiag.curveRawGSAA = rawGsaaCurve;
runDiag.curveRawGA = rawGaCurve;
runDiag.curveRawSA = rawSaCurve;
runDiag.curveRecoveredGSAA = recoveredGsaaCurve;
runDiag.curveRecoveredGA = recoveredGaCurve;
runDiag.curveRecoveredSA = recoveredSaCurve;
runDiag.resultSource = selectedSource;
runDiag.postRecoveryPolicy = postRecoveryPolicy;
end

function [rawResults, recoveredResults, activeResults] = compose_results_sources_43_(runDiag, cfg43, batch, source)
NRun = numel(runDiag);
rawResults = init_results_container_43_(NRun, cfg43.MaxGen, batch);
recoveredResults = init_results_container_43_(NRun, cfg43.MaxGen, batch);

for i = 1:NRun
    rec = runDiag(i);
    rawNode = getfield_safe_(rec, 'raw', struct());
    rawGsaa = getfield_safe_(rawNode, 'gsaa', struct());
    rawGa = getfield_safe_(rawNode, 'ga', struct());
    rawSa = getfield_safe_(rawNode, 'sa', struct());
    rawResults.gsaaCosts(i) = getfield_safe_(rawGsaa, 'cost', NaN);
    rawResults.gsaaTimes(i) = getfield_safe_(rawGsaa, 'time', NaN);
    rawResults.gaCosts(i) = getfield_safe_(rawGa, 'cost', NaN);
    rawResults.gaTimes(i) = getfield_safe_(rawGa, 'time', NaN);
    rawResults.saCosts(i) = getfield_safe_(rawSa, 'cost', NaN);
    rawResults.saTimes(i) = getfield_safe_(rawSa, 'time', NaN);
    rawResults.gsaaFeasible(i) = logical(getfield_safe_(rawGsaa, 'feasible', false));
    rawResults.gaFeasible(i) = logical(getfield_safe_(rawGa, 'feasible', false));
    rawResults.saFeasible(i) = logical(getfield_safe_(rawSa, 'feasible', false));
    rawResults.gsaaRecovered(i) = logical(getfield_safe_(rawGsaa, 'recovered', false));
    rawResults.gaRecovered(i) = logical(getfield_safe_(rawGa, 'recovered', false));
    rawResults.saRecovered(i) = logical(getfield_safe_(rawSa, 'recovered', false));
    rawResults.gsaaCurves(:, i) = normalize_curve_len_(getfield_safe_(rec, 'curveRawGSAA', NaN(cfg43.MaxGen,1)), cfg43.MaxGen);
    rawResults.gaCurves(:, i) = normalize_curve_len_(getfield_safe_(rec, 'curveRawGA', NaN(cfg43.MaxGen,1)), cfg43.MaxGen);
    rawResults.saCurves(:, i) = normalize_curve_len_(getfield_safe_(rec, 'curveRawSA', NaN(cfg43.MaxGen,1)), cfg43.MaxGen);

    recoveredNode = getfield_safe_(rec, 'recovered', struct());
    recGsaa = getfield_safe_(recoveredNode, 'gsaa', struct());
    recGa = getfield_safe_(recoveredNode, 'ga', struct());
    recSa = getfield_safe_(recoveredNode, 'sa', struct());
    recoveredResults.gsaaCosts(i) = getfield_safe_(recGsaa, 'cost', NaN);
    recoveredResults.gsaaTimes(i) = getfield_safe_(recGsaa, 'time', NaN);
    recoveredResults.gaCosts(i) = getfield_safe_(recGa, 'cost', NaN);
    recoveredResults.gaTimes(i) = getfield_safe_(recGa, 'time', NaN);
    recoveredResults.saCosts(i) = getfield_safe_(recSa, 'cost', NaN);
    recoveredResults.saTimes(i) = getfield_safe_(recSa, 'time', NaN);
    recoveredResults.gsaaFeasible(i) = logical(getfield_safe_(recGsaa, 'feasible', false));
    recoveredResults.gaFeasible(i) = logical(getfield_safe_(recGa, 'feasible', false));
    recoveredResults.saFeasible(i) = logical(getfield_safe_(recSa, 'feasible', false));
    recoveredResults.gsaaRecovered(i) = logical(getfield_safe_(recGsaa, 'recovered', false));
    recoveredResults.gaRecovered(i) = logical(getfield_safe_(recGa, 'recovered', false));
    recoveredResults.saRecovered(i) = logical(getfield_safe_(recSa, 'recovered', false));
    recoveredResults.gsaaCurves(:, i) = normalize_curve_len_(getfield_safe_(rec, 'curveRecoveredGSAA', NaN(cfg43.MaxGen,1)), cfg43.MaxGen);
    recoveredResults.gaCurves(:, i) = normalize_curve_len_(getfield_safe_(rec, 'curveRecoveredGA', NaN(cfg43.MaxGen,1)), cfg43.MaxGen);
    recoveredResults.saCurves(:, i) = normalize_curve_len_(getfield_safe_(rec, 'curveRecoveredSA', NaN(cfg43.MaxGen,1)), cfg43.MaxGen);
end

rawResults.curves = struct('GSAA', rawResults.gsaaCurves, 'GA', rawResults.gaCurves, 'SA', rawResults.saCurves, ...
    'aggregateMode', 'raw', 'curveMeta', struct('curvePolicy', 'raw'));
recoveredResults.curves = struct('GSAA', recoveredResults.gsaaCurves, 'GA', recoveredResults.gaCurves, 'SA', recoveredResults.saCurves, ...
    'aggregateMode', 'recovered', 'curveMeta', struct('curvePolicy', 'recovered'));

if strcmp(source, 'recovered')
    activeResults = recoveredResults;
else
    activeResults = rawResults;
end
end

function results = init_results_container_43_(NRun, maxGen, batch)
results = struct();
results.NRun = NRun;
results.batch = batch;
results.gsaaCosts = NaN(NRun, 1);
results.gsaaTimes = NaN(NRun, 1);
results.gaCosts = NaN(NRun, 1);
results.gaTimes = NaN(NRun, 1);
results.saCosts = NaN(NRun, 1);
results.saTimes = NaN(NRun, 1);
results.gsaaFeasible = false(NRun, 1);
results.gaFeasible = false(NRun, 1);
results.saFeasible = false(NRun, 1);
results.gsaaRecovered = false(NRun, 1);
results.gaRecovered = false(NRun, 1);
results.saRecovered = false(NRun, 1);
results.gsaaCurves = NaN(maxGen, NRun);
results.gaCurves = NaN(maxGen, NRun);
results.saCurves = NaN(maxGen, NRun);
results.runDiag = struct([]);
end

function diag = init_run_diag_43_(maxGen)
if nargin < 1 || ~isfinite(maxGen) || maxGen <= 0
    maxGen = 300;
end
diag = struct();
diag.gsaa = struct('feasible', false, 'cost', NaN, 'time', NaN, 'recovered', false, ...
    'initStrictFeasible', NaN, 'firstFeasibleGen', NaN, 'stopGen', NaN, 'penaltyCost', NaN);
diag.ga = struct('feasible', false, 'cost', NaN, 'time', NaN, 'recovered', false, ...
    'initStrictFeasible', NaN, 'firstFeasibleGen', NaN, 'stopGen', NaN, 'penaltyCost', NaN);
diag.sa = struct('feasible', false, 'cost', NaN, 'time', NaN, 'recovered', false, ...
    'initStrictFeasible', NaN, 'firstFeasibleGen', NaN, 'stopGen', NaN, 'penaltyCost', NaN);
diag.raw = struct('gsaa', diag.gsaa, 'ga', diag.ga, 'sa', diag.sa);
diag.recovered = struct('gsaa', diag.gsaa, 'ga', diag.ga, 'sa', diag.sa);
diag.curveGSAA = NaN(maxGen, 1);
diag.curveGA = NaN(maxGen, 1);
diag.curveSA = NaN(maxGen, 1);
diag.curveRawGSAA = NaN(maxGen, 1);
diag.curveRawGA = NaN(maxGen, 1);
diag.curveRawSA = NaN(maxGen, 1);
diag.curveRecoveredGSAA = NaN(maxGen, 1);
diag.curveRecoveredGA = NaN(maxGen, 1);
diag.curveRecoveredSA = NaN(maxGen, 1);
diag.resultSource = 'raw';
diag.postRecoveryPolicy = 'diag_only';
end

function diag = build_algo_diag_43_(outAlgo, bestCost, elapsed, recovered)
diag = struct('feasible', isfinite(bestCost), 'cost', bestCost, 'time', elapsed, 'recovered', logical(recovered), ...
    'initStrictFeasible', NaN, 'firstFeasibleGen', NaN, 'stopGen', NaN, 'penaltyCost', NaN);
try
    if isfield(outAlgo, 'initStrictFeasible')
        diag.initStrictFeasible = outAlgo.initStrictFeasible;
    end
    if isfield(outAlgo, 'firstFeasibleGen')
        diag.firstFeasibleGen = outAlgo.firstFeasibleGen;
    end
    if isfield(outAlgo, 'stopGen')
        diag.stopGen = outAlgo.stopGen;
    end
    if isfield(outAlgo, 'bestPenaltyCost') && isfinite(outAlgo.bestPenaltyCost)
        diag.penaltyCost = outAlgo.bestPenaltyCost;
    end
catch
end
end

function emit_run_logs_43_(sectionName, batch, nRun, runSeedInfo, runDiag, logLevel, useParallel, suiteInfo)
if strcmp(logLevel, 'none')
    return;
end
fprintf('[%s] 批次%d 运行明细: suite=%s | exec=%s | logLevel=%s | schema=run->GSAA/GA/SA\n', ...
    sectionName, batch, suiteInfo.tag, ternary_str_(logical(useParallel), 'parallel', 'serial'), logLevel);
if nRun >= 1
    fprintf('[%s] 批次%d 结果口径: resultSource=%s | postRecoveryPolicy=%s\n', ...
        sectionName, batch, stringify_safe_(getfield_safe_(runDiag(1), 'resultSource', 'raw')), ...
        stringify_safe_(getfield_safe_(runDiag(1), 'postRecoveryPolicy', 'diag_only')));
end
fprintf('[%s] 批次%d 实现映射: GSAA=%s | GA=%s | SA=%s\n', ...
    sectionName, batch, suiteInfo.gsaaImpl, suiteInfo.gaImpl, suiteInfo.saImpl);
baseSeed = getfield_safe_(runSeedInfo, 'baseSeed', NaN(nRun,1));
seedGSAA = getfield_safe_(runSeedInfo, 'seedGSAA', NaN(nRun,1));
seedGA = getfield_safe_(runSeedInfo, 'seedGA', NaN(nRun,1));
seedSA = getfield_safe_(runSeedInfo, 'seedSA', NaN(nRun,1));
for run = 1:nRun
    rec = runDiag(run);
    if strcmp(logLevel, 'summary')
        fprintf('[%s] 批次%d run%02d/%02d | baseSeed=%s | GSAA=%s(%ss,f=%d,r=%d) | GA=%s(%ss,f=%d,r=%d) | SA=%s(%ss,f=%d,r=%d)\n', ...
            sectionName, batch, run, nRun, ...
            fmt_num_43_(baseSeed(run)), ...
            fmt_num_43_(rec.gsaa.cost), fmt_num_43_(rec.gsaa.time), double(rec.gsaa.feasible), double(rec.gsaa.recovered), ...
            fmt_num_43_(rec.ga.cost), fmt_num_43_(rec.ga.time), double(rec.ga.feasible), double(rec.ga.recovered), ...
            fmt_num_43_(rec.sa.cost), fmt_num_43_(rec.sa.time), double(rec.sa.feasible), double(rec.sa.recovered));
    else
        fprintf('[%s] 批次%d run%02d/%02d | seeds{base=%s, GSAA=%s, GA=%s, SA=%s}\n', ...
            sectionName, batch, run, nRun, ...
            fmt_num_43_(baseSeed(run)), fmt_num_43_(seedGSAA(run)), fmt_num_43_(seedGA(run)), fmt_num_43_(seedSA(run)));
        print_algo_diag_line_43_(sectionName, batch, run, nRun, 'GSAA', rec.gsaa);
        print_algo_diag_line_43_(sectionName, batch, run, nRun, 'GA', rec.ga);
        print_algo_diag_line_43_(sectionName, batch, run, nRun, 'SA', rec.sa);
    end
end
end

function print_algo_diag_line_43_(sectionName, batch, run, nRun, algoTag, rec)
fprintf('[%s][batch%02d][run%02d/%02d][%-4s] feasible=%d | recovered=%d | best=%s | time=%ss | initFeas=%s | firstFeasGen=%s | stopGen=%s | penaltyBest=%s\n', ...
    sectionName, batch, run, nRun, algoTag, double(rec.feasible), double(rec.recovered), fmt_num_43_(rec.cost), fmt_num_43_(rec.time), ...
    fmt_num_43_(rec.initStrictFeasible), fmt_num_43_(rec.firstFeasibleGen), fmt_num_43_(rec.stopGen), fmt_num_43_(rec.penaltyCost));
end

function lv = normalize_parallel_log_level_43_(lvRaw)
lv = lower(strtrim(char(string(lvRaw))));
if ~any(strcmp(lv, {'none', 'summary', 'detailed'}))
    lv = 'detailed';
end
end

function src = normalize_result_source_43_(srcRaw)
src = lower(strtrim(stringify_safe_(srcRaw)));
if ~any(strcmp(src, {'raw', 'recovered'}))
    src = 'raw';
end
end

function pol = normalize_post_recovery_policy_43_(polRaw)
pol = lower(strtrim(stringify_safe_(polRaw)));
if ~any(strcmp(pol, {'off', 'diag_only', 'apply_to_all'}))
    pol = 'diag_only';
end
end

function mode = normalize_dominance_mode_43_(modeRaw)
mode = lower(strtrim(stringify_safe_(modeRaw)));
if ~any(strcmp(mode, {'off', 'diag', 'hard'}))
    mode = 'diag';
end
end

function policy = normalize_dominance_curve_policy_43_(policyRaw)
policy = lower(strtrim(stringify_safe_(policyRaw)));
if any(strcmp(policy, {'best', 'best_run'}))
    policy = 'best_run';
elseif ~any(strcmp(policy, {'paired_run', 'best_run'}))
    policy = 'paired_run';
end
end

function [gsaaCurve, gaCurve, saCurve, runIdx] = dominance_curves_paired_43_(results, cfg43, curveMeta)
runIdx = double(getfield_safe_(curveMeta, 'curveRunIdx', NaN));
NRun = max([size(results.gsaaCurves,2), size(results.gaCurves,2), size(results.saCurves,2), 1]);
if ~isfinite(runIdx) || runIdx < 1 || runIdx > NRun
    [runIdxPick, ~] = pick_paired_run_without_ref_(results, cfg43);
    if isfinite(runIdxPick) && runIdxPick >= 1
        runIdx = runIdxPick;
    else
        runIdx = 1;
    end
end
runIdx = min(max(round(runIdx), 1), NRun);
if size(results.gsaaCurves,2) >= 1
    gsaaCurve = normalize_curve_len_(results.gsaaCurves(:, min(runIdx, size(results.gsaaCurves,2))), cfg43.MaxGen);
else
    gsaaCurve = NaN(cfg43.MaxGen, 1);
end
if size(results.gaCurves,2) >= 1
    gaCurve = normalize_curve_len_(results.gaCurves(:, min(runIdx, size(results.gaCurves,2))), cfg43.MaxGen);
else
    gaCurve = NaN(cfg43.MaxGen, 1);
end
if size(results.saCurves,2) >= 1
    saCurve = normalize_curve_len_(results.saCurves(:, min(runIdx, size(results.saCurves,2))), cfg43.MaxGen);
else
    saCurve = NaN(cfg43.MaxGen, 1);
end
end

function s = fmt_num_43_(v)
if isnumeric(v) && isscalar(v)
    if ~isfinite(v)
        s = 'NA';
    elseif abs(v-round(v)) < 1e-9
        s = sprintf('%d', round(v));
    else
        s = sprintf('%.6f', v);
    end
elseif islogical(v) && isscalar(v)
    s = sprintf('%d', double(v));
else
    s = stringify_safe_(v);
end
end

function [outAlgo, elapsed] = solve_algo_with_seed_(algoName, seed, cfg43, G, suiteInfo)
rng(double(seed), 'twister');
t0 = tic;
switch upper(char(string(algoName)))
    case 'GSAA'
        if strcmpi(stringify_safe_(getfield_safe_(suiteInfo, 'tag', '')), 'paper_suite')
            outAlgo = gsaa_paper_43(cfg43.NP, cfg43.MaxGen, cfg43.Pc, cfg43.Pm, cfg43.Pe, ...
                cfg43.T0, cfg43.Tmin, cfg43.alpha, cfg43.STOP_BY_TMIN, G);
        else
            outAlgo = one_run_gsaa(cfg43.NP, cfg43.MaxGen, cfg43.Pc, cfg43.Pm, cfg43.Pe, ...
                cfg43.T0, cfg43.Tmin, cfg43.alpha, cfg43.STOP_BY_TMIN, G);
        end
    case 'GA'
        outAlgo = ga_solve_43(cfg43.NP, cfg43.MaxGen, cfg43.Pc, cfg43.Pm, G);
    case 'SA'
        if strcmpi(stringify_safe_(getfield_safe_(suiteInfo, 'tag', '')), 'paper_suite')
            outAlgo = sa_paper_43(cfg43.NP, cfg43.MaxGen, cfg43.T0, cfg43.Tmin, cfg43.alpha, G, cfg43.repro);
        else
            outAlgo = sa_solve_43(cfg43.NP, cfg43.MaxGen, cfg43.T0, cfg43.Tmin, cfg43.alpha, G);
        end
    otherwise
        error('run_section_43:unknownAlgo', 'unknown algo: %s', char(string(algoName)));
end
elapsed = toc(t0);
end

function suiteInfo = algo_suite_info_43_(cfg_usePaperTest, algoSuiteRaw)
if nargin < 2 || isempty(strtrim(stringify_safe_(algoSuiteRaw)))
    if cfg_usePaperTest
        algoSuite = 'paper_suite';
    else
        algoSuite = 'opensource_suite';
    end
else
    algoSuite = lower(strtrim(stringify_safe_(algoSuiteRaw)));
end

switch algoSuite
    case 'paper_suite'
        suiteInfo = struct('tag', 'paper_suite', 'gsaaImpl', 'gsaa_paper_43', 'gaImpl', 'ga_solve_43', 'saImpl', 'sa_paper_43', ...
            'usePaperTestChecks', true);
    case 'opensource_strict'
        suiteInfo = struct('tag', 'opensource_strict', 'gsaaImpl', 'one_run_gsaa', 'gaImpl', 'ga_solve_43', 'saImpl', 'sa_solve_43', ...
            'usePaperTestChecks', logical(cfg_usePaperTest));
    otherwise
        suiteInfo = struct('tag', 'opensource_suite', 'gsaaImpl', 'one_run_gsaa', 'gaImpl', 'ga_solve_43', 'saImpl', 'sa_solve_43', ...
            'usePaperTestChecks', logical(cfg_usePaperTest));
end
end

function algoCtx = build_algo_contexts_43_(G, cfg43, suiteInfo)
algoCtx = struct('gsaa', G, 'ga', G, 'sa', G, 'paperGsaaOpsApplied', false, 'note', '');

if ~strcmpi(stringify_safe_(getfield_safe_(suiteInfo, 'tag', '')), 'paper_suite')
    return;
end

ensureOps = logical(getfield_safe_(getfield_safe_(cfg43, 'repro', struct()), 'paperGsaaEnsureOps', false));
if ~ensureOps
    algoCtx.note = 'paper_suite_gsaa_ops_fix_disabled';
    return;
end

gFix = G;
if ~isfield(gFix, 'opt') || ~isstruct(gFix.opt)
    gFix.opt = struct();
end

gFix.opt.enableEliteLS = true;
gFix.opt.enableRelocate = true;
gFix.opt.enableSwap = true;
gFix.opt.enableImmigration = true;
gFix.opt.enableKick = true;

if ~isfield(gFix.opt, 'crossTrials') || ~isfinite(double(gFix.opt.crossTrials)) || double(gFix.opt.crossTrials) < 1
    gFix.opt.crossTrials = 1;
end
gFix.opt.allowWorseLS = true;

algoCtx.gsaa = gFix;
algoCtx.paperGsaaOpsApplied = true;
algoCtx.note = 'paper_suite_gsaa_core_ops_restored';
end

function Guse = get_algo_context_43_(algoCtx, algoName)
Guse = getfield_safe_(algoCtx, 'gsaa', struct());
switch upper(stringify_safe_(algoName))
    case 'GSAA'
        Guse = getfield_safe_(algoCtx, 'gsaa', Guse);
    case 'GA'
        Guse = getfield_safe_(algoCtx, 'ga', Guse);
    case 'SA'
        Guse = getfield_safe_(algoCtx, 'sa', Guse);
end
end

function algoCtxOut = set_console_verbose_43_(algoCtxIn, flag)
algoCtxOut = algoCtxIn;
if ~isstruct(algoCtxOut)
    return;
end
names = {'gsaa', 'ga', 'sa'};
for i = 1:numel(names)
    name = names{i};
    if isfield(algoCtxOut, name) && isstruct(algoCtxOut.(name))
        if ~isfield(algoCtxOut.(name), 'opt') || ~isstruct(algoCtxOut.(name).opt)
            algoCtxOut.(name).opt = struct();
        end
        algoCtxOut.(name).opt.consoleVerbose = logical(flag);
    end
end
end

function print_algo_context_diag_43_(sectionName, suiteInfo, algoCtx, cfg43)
if ~isstruct(algoCtx)
    return;
end
gsaaOpt = getfield_safe_(getfield_safe_(algoCtx, 'gsaa', struct()), 'opt', struct());
fprintf('[%s][ALGO_CTX] suite=%s | gsaaEnsureOps=%d | applied=%d | note=%s\n', ...
    sectionName, stringify_safe_(getfield_safe_(suiteInfo, 'tag', '')), ...
    logical(getfield_safe_(getfield_safe_(cfg43, 'repro', struct()), 'paperGsaaEnsureOps', false)), ...
    logical(getfield_safe_(algoCtx, 'paperGsaaOpsApplied', false)), ...
    stringify_safe_(getfield_safe_(algoCtx, 'note', '')));
fprintf('[%s][ALGO_CTX] GSAA关键算子: eliteLS=%d relocate=%d swap=%d immigration=%d kick=%d crossTrials=%s allowWorseLS=%d\n', ...
    sectionName, ...
    logical(getfield_safe_(gsaaOpt, 'enableEliteLS', false)), ...
    logical(getfield_safe_(gsaaOpt, 'enableRelocate', false)), ...
    logical(getfield_safe_(gsaaOpt, 'enableSwap', false)), ...
    logical(getfield_safe_(gsaaOpt, 'enableImmigration', false)), ...
    logical(getfield_safe_(gsaaOpt, 'enableKick', false)), ...
    stringify_safe_(getfield_safe_(gsaaOpt, 'crossTrials', NaN)), ...
    logical(getfield_safe_(gsaaOpt, 'allowWorseLS', false)));
end

function print_algo_start_43_(logCtx, runIdx, algoTag, seed)
fprintf('[%s][batch%02d][run%02d/%02d][%s][START] seed=%s | suite=%s\n', ...
    stringify_safe_(getfield_safe_(logCtx, 'sectionName', 'section_43')), ...
    round(double(getfield_safe_(logCtx, 'batch', NaN))), ...
    round(double(runIdx)), ...
    round(double(getfield_safe_(logCtx, 'nRun', NaN))), ...
    stringify_safe_(algoTag), stringify_safe_(seed), stringify_safe_(getfield_safe_(logCtx, 'suiteTag', '')));
end

function print_algo_done_43_(logCtx, runIdx, algoTag, outAlgo, elapsed)
bestCost = cost_from_out_(outAlgo);
fprintf('[%s][batch%02d][run%02d/%02d][%s][DONE ] best=%s | feasible=%d | time=%ss\n', ...
    stringify_safe_(getfield_safe_(logCtx, 'sectionName', 'section_43')), ...
    round(double(getfield_safe_(logCtx, 'batch', NaN))), ...
    round(double(runIdx)), ...
    round(double(getfield_safe_(logCtx, 'nRun', NaN))), ...
    stringify_safe_(algoTag), stringify_safe_(bestCost), double(isfinite(bestCost)), stringify_safe_(elapsed));
end

function [outAlgo, recovered] = recover_infeasible_result_(outAlgo, G, reproCfg)
recovered = false;
if result_is_feasible_(outAlgo)
    return;
end
if nargin < 3 || ~isstruct(reproCfg)
    reproCfg = struct();
end

[candCh, sourceTag] = get_recovery_candidate_ch_(outAlgo);
if isempty(candCh)
    if G.K > 1
        candCh = [randperm(G.n), sort(randperm(G.n-1, G.K-1))];
    else
        candCh = randperm(G.n);
    end
    sourceTag = 'random_init';
end
if ~isnumeric(candCh) || ~isvector(candCh)
    if G.K > 1
        candCh = [randperm(G.n), sort(randperm(G.n-1, G.K-1))];
    else
        candCh = randperm(G.n);
    end
    sourceTag = 'random_init';
end
candCh = double(candCh(:)');
if numel(candCh) ~= (G.n + G.K - 1)
    if G.K > 1
        candCh = [randperm(G.n), sort(randperm(G.n-1, G.K-1))];
    else
        candCh = randperm(G.n);
    end
    sourceTag = 'random_init';
end

try
    ch0 = repair_chromosome_deterministic(candCh, G);
    [ok, bestFx, bestCh, bestDetail] = try_recover_with_levels_(ch0, G, reproCfg);
    if ~ok
        return;
    end

    outAlgo.bestCost = bestFx;
    outAlgo.bestCh = bestCh;
    outAlgo.bestDetail = bestDetail;
    if isfield(outAlgo, 'feasible')
        outAlgo.feasible = true;
    end
    if isfield(outAlgo, 'bestFeasibleFound')
        outAlgo.bestFeasibleFound = true;
    end
    outAlgo.recoveredBySection43 = true;
    outAlgo.recoverySource = sourceTag;
    outAlgo = inject_recovered_cost_to_curve_(outAlgo, bestFx, reproCfg);
    recovered = true;
catch
    recovered = false;
end
end

function ok = result_is_feasible_(outAlgo)
ok = false;
try
    if isfield(outAlgo, 'feasible')
        ok = logical(outAlgo.feasible);
    elseif isfield(outAlgo, 'bestFeasibleFound')
        ok = logical(outAlgo.bestFeasibleFound);
    elseif isfield(outAlgo, 'bestCost')
        v = double(outAlgo.bestCost);
        ok = isfinite(v);
    end
catch
    ok = false;
end
end

function [ch, sourceTag] = get_recovery_candidate_ch_(outAlgo)
ch = [];
sourceTag = 'none';
if isfield(outAlgo, 'bestCh') && ~isempty(outAlgo.bestCh)
    ch = outAlgo.bestCh;
    sourceTag = 'bestCh';
    return;
end
if isfield(outAlgo, 'bestPenaltyCh') && ~isempty(outAlgo.bestPenaltyCh)
    ch = outAlgo.bestPenaltyCh;
    sourceTag = 'bestPenaltyCh';
end
end

function [ok, bestFx, bestCh, bestDetail] = try_recover_with_levels_(ch0, G, reproCfg)
ok = false;
bestFx = inf;
bestCh = [];
bestDetail = [];
if nargin < 3 || ~isstruct(reproCfg)
    reproCfg = struct();
end

maxTry = 1200;
restartPeriod = 10;
if isfield(reproCfg, 'recoverMaxTry')
    v = double(reproCfg.recoverMaxTry);
    if isfinite(v) && v > 0
        maxTry = round(v);
    end
end
if isfield(reproCfg, 'recoverRestartPeriod')
    v = double(reproCfg.recoverRestartPeriod);
    if isfinite(v) && v > 0
        restartPeriod = round(v);
    end
end

levels = [2, 1];
cand = ch0;
for t = 1:maxTry
    if t == 1
        cand = ch0;
    elseif mod(t-1, restartPeriod) == 0
        perm = randperm(G.n);
        cuts = sort(randperm(G.n-1, G.K-1));
        cand = [perm, cuts];
    else
        cand = perturb_chromosome_(cand, G.n, G.K);
    end

    try
        cand = repair_chromosome_deterministic(cand, G);
    catch
        continue;
    end

    for i = 1:numel(levels)
        lv = levels(i);
        try
            ch1 = repair_all_constraints(cand, G.n, G.K, lv, G);
            [fx, feasible, chFixed, detail] = fitness_strict_penalty(ch1, G);
            if feasible && isfinite(fx) && fx < bestFx
                ok = true;
                bestFx = fx;
                bestCh = chFixed;
                bestDetail = detail;
                if fx <= 1.05e4
                    return;
                end
            end
        catch
        end
    end
end

if ~isfinite(bestFx)
    bestFx = NaN;
end
end

function ch2 = perturb_chromosome_(ch, n, K)
ch2 = ch;
if numel(ch2) ~= (n + K - 1)
    perm = randperm(n);
    cuts = sort(randperm(n-1, K-1));
    ch2 = [perm, cuts];
    return;
end

perm = ch2(1:n);
cuts = ch2(n+1:end);
op = randi(3);
switch op
    case 1
        i = randi(n);
        j = randi(n);
        while j == i
            j = randi(n);
        end
        perm([i j]) = perm([j i]);
    case 2
        i = randi(n);
        j = randi(n);
        if i > j
            [i, j] = deal(j, i);
        end
        perm(i:j) = perm(j:-1:i);
    otherwise
        if K > 1
            cuts = sort(randperm(n-1, K-1));
        end
end
ch2 = [perm, cuts];
end

function outAlgo = inject_recovered_cost_to_curve_(outAlgo, recoveredCost, reproCfg)
if ~isfinite(recoveredCost)
    return;
end
if ~isfield(outAlgo, 'iterCurve')
    return;
end
if nargin < 3 || ~isstruct(reproCfg)
    reproCfg = struct();
end
try
    y = double(outAlgo.iterCurve(:));
    if isempty(y)
        outAlgo.iterCurve = recoveredCost;
        return;
    end

    injectMode = 'always';
    if isfield(reproCfg, 'recoveryCurveInjectMode') && ~isempty(reproCfg.recoveryCurveInjectMode)
        injectMode = lower(strtrim(char(string(reproCfg.recoveryCurveInjectMode))));
    end

    switch injectMode
        case {'never', 'off'}
            return;
        case {'all_nan_only', 'only_all_nan'}
            if any(isfinite(y))
                return;
            end
        otherwise
            % 默认行为：保持历史兼容
    end

    mask = isfinite(y);
    if any(mask)
        k = find(mask, 1, 'last');
        y(k) = min(y(k), recoveredCost);
    else
        y(:) = recoveredCost;
    end
    for i = 2:numel(y)
        if isfinite(y(i-1))
            if ~isfinite(y(i))
                y(i) = y(i-1);
            else
                y(i) = min(y(i), y(i-1));
            end
        end
    end
    outAlgo.iterCurve = y;
catch
end
end

function [gsaaCurvePlot, gaCurvePlot, saCurvePlot, meta] = build_curve_plots_(results, cfg43, figureRef)
if nargin < 3 || ~isstruct(figureRef)
    figureRef = struct('available', false, 'curves', struct(), 'sig', '', 'source', 'none');
end

policy = strtrim(char(string(cfg43.repro.curveSelectionPolicy)));
if strcmpi(policy, 'paired_run')
    [gsaaCurvePlot, gaCurvePlot, saCurvePlot, meta] = build_curve_plots_paired_run_(results, cfg43, figureRef);
    return;
end

aggMode = cfg43.curveAggregate;
if ~isempty(policy)
    aggMode = policy;
end
[gsaaCurvePlot, gsaaIdx] = aggregate_curve_matrix_(results.gsaaCurves, aggMode, results.gsaaCosts);
[gaCurvePlot, gaIdx] = aggregate_curve_matrix_(results.gaCurves, aggMode, results.gaCosts);
[saCurvePlot, saIdx] = aggregate_curve_matrix_(results.saCurves, aggMode, results.saCosts);
figEval = evaluate_figure_shape_43_(gsaaCurvePlot, gaCurvePlot, saCurvePlot, figureRef, cfg43);
meta = struct('gsaaCurveRunIdx', gsaaIdx, 'gaCurveRunIdx', gaIdx, 'saCurveRunIdx', saIdx, ...
    'curvePolicy', char(string(aggMode)), 'curveRunIdx', NaN, ...
    'figureRefSource', getfield_safe_(figureRef, 'source', ''), 'figureRefSig', getfield_safe_(figureRef, 'sig', ''), ...
    'figureEval', figEval);
end

function [gsaaCurvePlot, gaCurvePlot, saCurvePlot, meta] = build_curve_plots_paired_run_(results, cfg43, figureRef)
NRun = max([size(results.gsaaCurves,2), size(results.gaCurves,2), size(results.saCurves,2), 1]);
cands = repmat(struct('idx', NaN, 'gsaa', [], 'ga', [], 'sa', [], 'score', inf, 'pass', false, ...
    'eval', struct(), 'activity', struct('GSAA', 0, 'GA', 0, 'SA', 0), 'nonflat', false), NRun, 1);
minChanges = struct('GSAA', 1, 'GA', 1, 'SA', 1);
for runIdx = 1:NRun
    gsaa = normalize_curve_len_(results.gsaaCurves(:, min(runIdx, size(results.gsaaCurves,2))), cfg43.MaxGen);
    ga = normalize_curve_len_(results.gaCurves(:, min(runIdx, size(results.gaCurves,2))), cfg43.MaxGen);
    sa = normalize_curve_len_(results.saCurves(:, min(runIdx, size(results.saCurves,2))), cfg43.MaxGen);

    gsaa = normalize_for_curve_eval_(gsaa, cfg43);
    ga = normalize_for_curve_eval_(ga, cfg43);
    sa = normalize_for_curve_eval_(sa, cfg43);

    figEval = evaluate_figure_shape_43_(gsaa, ga, sa, figureRef, cfg43);
    cands(runIdx).idx = runIdx;
    cands(runIdx).gsaa = gsaa;
    cands(runIdx).ga = ga;
    cands(runIdx).sa = sa;
    cands(runIdx).score = figEval.shapeScore;
    cands(runIdx).pass = figEval.pass;
    cands(runIdx).eval = figEval;
    act = struct( ...
        'GSAA', curve_change_count_43_(gsaa), ...
        'GA', curve_change_count_43_(ga), ...
        'SA', curve_change_count_43_(sa));
    cands(runIdx).activity = act;
    cands(runIdx).nonflat = (act.GSAA >= minChanges.GSAA) && (act.GA >= minChanges.GA) && (act.SA >= minChanges.SA);
end

passIdx = find([cands.pass]);
pickMode = lower(strtrim(char(string(cfg43.repro.curvePairedRunPick))));
if isempty(pickMode)
    pickMode = 'min_shape_score_nonflat';
end

if ~logical(getfield_safe_(figureRef, 'available', false))
    [pick, fallbackScores] = pick_paired_run_without_ref_(results, cfg43);
    for i = 1:numel(cands)
        cands(i).score = fallbackScores(i);
        cands(i).eval.shapeScore = fallbackScores(i);
        cands(i).eval.failReason = 'figure_reference_unavailable_fallback_by_cost';
    end
    if strcmp(pickMode, 'min_shape_score_nonflat')
        nonflatIdx = find([cands.nonflat]);
        if ~isempty(nonflatIdx)
            [~, kk] = min([cands(nonflatIdx).score]);
            pick = nonflatIdx(kk);
            pickMode = [pickMode '_fallback_cost_nonflat'];
        else
            pickMode = [pickMode '_fallback_cost_all_flat'];
        end
    else
        pickMode = [pickMode '_fallback_cost'];
    end
else
    if strcmp(pickMode, 'min_shape_score_nonflat')
        passNonflatIdx = find([cands.pass] & [cands.nonflat]);
        nonflatIdx = find([cands.nonflat]);
        if ~isempty(passNonflatIdx)
            [~, k] = min([cands(passNonflatIdx).score]);
            pick = passNonflatIdx(k);
            pickMode = [pickMode '_pass_nonflat'];
        elseif ~isempty(nonflatIdx)
            [~, k] = min([cands(nonflatIdx).score]);
            pick = nonflatIdx(k);
            pickMode = [pickMode '_nonflat_only'];
        elseif ~isempty(passIdx)
            [~, k] = min([cands(passIdx).score]);
            pick = passIdx(k);
            pickMode = [pickMode '_fallback_pass_all_flat'];
        else
            [~, pick] = min([cands.score]);
            pickMode = [pickMode '_fallback_all'];
        end
    elseif strcmp(pickMode, 'min_shape_score')
        if ~isempty(passIdx)
            [~, k] = min([cands(passIdx).score]);
            pick = passIdx(k);
        else
            [~, pick] = min([cands.score]);
        end
    else
        if ~isempty(passIdx)
            pick = passIdx(1);
        else
            [~, pick] = min([cands.score]);
        end
    end
end

sel = cands(pick);
gsaaCurvePlot = sel.gsaa;
gaCurvePlot = sel.ga;
saCurvePlot = sel.sa;
passNonflatCount = sum([cands.pass] & [cands.nonflat]);
meta = struct('gsaaCurveRunIdx', sel.idx, 'gaCurveRunIdx', sel.idx, 'saCurveRunIdx', sel.idx, ...
    'curvePolicy', 'paired_run', 'curveRunIdx', sel.idx, ...
    'figureRefSource', getfield_safe_(figureRef, 'source', ''), 'figureRefSig', getfield_safe_(figureRef, 'sig', ''), ...
    'figureEval', sel.eval, ...
    'candidateCount', NRun, 'passedCandidateCount', numel(passIdx), 'curvePairedRunPick', pickMode, ...
    'selectedNonflat', logical(getfield_safe_(sel, 'nonflat', false)), ...
    'selectedActivity', getfield_safe_(sel, 'activity', struct('GSAA', NaN, 'GA', NaN, 'SA', NaN)), ...
    'nonflatCandidateCount', sum([cands.nonflat]), 'passedNonflatCandidateCount', passNonflatCount, ...
    'curvePairedRunMinChanges', minChanges);
end

function y = normalize_for_curve_eval_(x, cfg43)
y = double(x(:));
if isfield(cfg43, 'curveMode') && strcmpi(cfg43.curveMode, 'cummin')
    y = cummin_finite_(y);
end
end

function n = curve_change_count_43_(curve)
x = double(curve(:));
if numel(x) <= 1
    n = 0;
    return;
end
mask = isfinite(x(1:end-1)) & isfinite(x(2:end));
if ~any(mask)
    n = 0;
    return;
end
d = abs(diff(x));
n = sum(mask & (d > 1e-9));
end

function y = cummin_finite_(x)
y = double(x(:));
best = NaN;
for i = 1:numel(y)
    if ~isfinite(y(i))
        if isfinite(best)
            y(i) = best;
        end
        continue;
    end
    if ~isfinite(best)
        best = y(i);
    else
        best = min(best, y(i));
        y(i) = best;
    end
end
end

function figEval = evaluate_figure_shape_43_(gsaaCurve, gaCurve, saCurve, figureRef, cfg43)
figEval = struct();
figEval.refAvailable = false;
figEval.refSource = getfield_safe_(figureRef, 'source', 'none');
figEval.refSig = getfield_safe_(figureRef, 'sig', '');
figEval.anchorGens = sanitize_anchor_gens_(cfg43.repro.figureAnchorGens, cfg43.MaxGen);
figEval.anchorRelErr = NaN(3, numel(figEval.anchorGens));
figEval.endpointRelErr = NaN(3, 1);
figEval.anchorPassMatrix = false(3, numel(figEval.anchorGens));
figEval.endpointPass = false(3, 1);
figEval.monotonicPass = [false; false; false];
figEval.orderPass = false;
figEval.shapeScore = inf;
figEval.pass = false;
figEval.failReason = '';

figEval.monotonicPass(1) = is_nonincreasing_curve_(gsaaCurve, 1e-8);
figEval.monotonicPass(2) = is_nonincreasing_curve_(gaCurve, 1e-8);
figEval.monotonicPass(3) = is_nonincreasing_curve_(saCurve, 1e-8);

lastGSAA = last_finite_(gsaaCurve);
lastGA = last_finite_(gaCurve);
lastSA = last_finite_(saCurve);
figEval.orderPass = isfinite(lastGSAA) && isfinite(lastGA) && isfinite(lastSA) && ...
    (lastGSAA <= lastGA) && (lastGSAA <= lastSA);

if ~isfield(cfg43.repro, 'figureHardGateEnable') || ~cfg43.repro.figureHardGateEnable
    figEval.pass = all(figEval.monotonicPass) && figEval.orderPass;
    figEval.shapeScore = double(~figEval.pass);
    figEval.failReason = ternary_str_(figEval.pass, '', 'figure_hard_gate_disabled_but_curve_basic_check_failed');
    return;
end

if ~isstruct(figureRef) || ~isfield(figureRef, 'available') || ~logical(figureRef.available)
    figEval.failReason = 'figure_reference_unavailable';
    return;
end
if ~isfield(figureRef, 'curves') || ~all(isfield(figureRef.curves, {'GSAA','GA','SA'}))
    figEval.failReason = 'figure_reference_curve_missing';
    return;
end

figEval.refAvailable = true;
refGSAA = normalize_curve_len_(figureRef.curves.GSAA, cfg43.MaxGen);
refGA = normalize_curve_len_(figureRef.curves.GA, cfg43.MaxGen);
refSA = normalize_curve_len_(figureRef.curves.SA, cfg43.MaxGen);
refGSAA = cummin_finite_(refGSAA);
refGA = cummin_finite_(refGA);
refSA = cummin_finite_(refSA);

curves = [gsaaCurve(:), gaCurve(:), saCurve(:)];
refs = [refGSAA(:), refGA(:), refSA(:)];
anchorTol = max(0, double(cfg43.repro.figureAnchorRelTol));
endTol = max(0, double(cfg43.repro.figureEndpointRelTol));

for a = 1:3
    for gk = 1:numel(figEval.anchorGens)
        g = figEval.anchorGens(gk);
        figEval.anchorRelErr(a, gk) = rel_err_finite_(curves(g, a), refs(g, a));
        figEval.anchorPassMatrix(a, gk) = isfinite(figEval.anchorRelErr(a, gk)) && (figEval.anchorRelErr(a, gk) <= anchorTol);
    end
    figEval.endpointRelErr(a) = rel_err_finite_(curves(end, a), refs(end, a));
    figEval.endpointPass(a) = isfinite(figEval.endpointRelErr(a)) && (figEval.endpointRelErr(a) <= endTol);
end

anchorErrMean = nanmean_safe_(figEval.anchorRelErr(:), 10);
endErrMean = nanmean_safe_(figEval.endpointRelErr(:), 10);
failCount = sum(~figEval.anchorPassMatrix(:)) + sum(~figEval.endpointPass(:)) + ...
    sum(~figEval.monotonicPass(:)) + double(~figEval.orderPass);
figEval.shapeScore = anchorErrMean + endErrMean + 0.01 * failCount;

figEval.pass = all(figEval.anchorPassMatrix(:)) && all(figEval.endpointPass(:)) && ...
    all(figEval.monotonicPass(:)) && figEval.orderPass;
if ~figEval.pass
    figEval.failReason = sprintf('anchorOrEndpointOrOrderFailed(failCount=%d)', failCount);
end
end

function g = sanitize_anchor_gens_(genList, maxGen)
g = unique(round(double(genList(:)')));
g = g(isfinite(g) & g >= 1 & g <= maxGen);
if isempty(g)
    g = [1, maxGen];
end
end

function [pickIdx, scoreVec] = pick_paired_run_without_ref_(results, cfg43)
NRun = max([numel(results.gsaaCosts), numel(results.gaCosts), numel(results.saCosts), 1]);
scoreVec = inf(NRun, 1);
paper = cfg43.paperBaseline;
for i = 1:NRun
    gsaa = value_at_or_nan_(results.gsaaCosts, i);
    ga = value_at_or_nan_(results.gaCosts, i);
    sa = value_at_or_nan_(results.saCosts, i);

    s = rel_err_or_fallback_(gsaa, paper.GSAA_Cost, 5) + ...
        rel_err_or_fallback_(ga, paper.GA_Cost, 5) + ...
        rel_err_or_fallback_(sa, paper.SA_Cost, 5);

    missCount = double(~isfinite(gsaa)) + double(~isfinite(ga)) + double(~isfinite(sa));
    s = s + 2.0 * missCount;
    if isfinite(gsaa) && isfinite(ga) && isfinite(sa) && ~((gsaa <= ga) && (gsaa <= sa))
        s = s + 0.5;
    end
    scoreVec(i) = s;
end
[~, pickIdx] = min(scoreVec);
if ~isfinite(pickIdx) || pickIdx < 1 || pickIdx > NRun
    pickIdx = 1;
end
end

function v = value_at_or_nan_(x, idx)
v = NaN;
try
    if idx >= 1 && idx <= numel(x)
        v = double(x(idx));
    end
catch
    v = NaN;
end
end

function e = rel_err_or_fallback_(actual, ref, fallback)
e = rel_err_finite_(actual, ref);
if ~isfinite(e)
    e = fallback;
end
end

function r = rel_err_finite_(actual, ref)
r = NaN;
if isfinite(actual) && isfinite(ref)
    r = abs(actual - ref) / max(abs(ref), 1e-6);
end
end

function bench = benchmark_time_order_(results, batch, cfg43, algoCtx, suiteInfo, cfg_usePaperTest)
bench = struct();
bench.metric = char(string(cfg43.repro.timeMetric));
bench.repeatCount = max(1, round(double(cfg43.repro.timeBenchmarkRepeats)));
bench.samples = struct('GSAA', NaN(bench.repeatCount,1), 'GA', NaN(bench.repeatCount,1), 'SA', NaN(bench.repeatCount,1));
bench.GSAA = NaN;
bench.GA = NaN;
bench.SA = NaN;
bench.orderExpected = 'GA(sum NRun) < GSAA(sum NRun) < SA(sum NRun)';
bench.orderPass = false;

if isfield(cfg43.repro, 'timeMetric') && strcmpi(cfg43.repro.timeMetric, 'nrun_cumulative')
    bench.GSAA = finite_sum_(results.gsaaTimes);
    bench.GA = finite_sum_(results.gaTimes);
    bench.SA = finite_sum_(results.saTimes);
    bench.orderPass = isfinite(bench.GA) && isfinite(bench.GSAA) && isfinite(bench.SA) && ...
        (bench.GA < bench.GSAA) && (bench.GSAA < bench.SA);
    return;
end

bench.orderExpected = 'GA(median) < GSAA(median) < SA(median)';
if ~isfield(cfg43.repro, 'timeMetric') || ~strcmpi(cfg43.repro.timeMetric, 'benchmark_median')
    return;
end

algoList = {'GSAA', 'GA', 'SA'};
for i = 1:numel(algoList)
    algo = algoList{i};
    warmSeed = 600000 + batch*100 + i*10;
    Gbench = get_algo_context_43_(algoCtx, algo);
    try
        solve_algo_with_seed_(algo, warmSeed, cfg43, Gbench, suiteInfo); % 预热
    catch
    end

    for r = 1:bench.repeatCount
        seed = warmSeed + r;
        try
            [~, elapsed] = solve_algo_with_seed_(algo, seed, cfg43, Gbench, suiteInfo);
            bench.samples.(algo)(r) = elapsed;
        catch
            bench.samples.(algo)(r) = NaN;
        end
    end

    vv = bench.samples.(algo);
    mask = isfinite(vv);
    if any(mask)
        bench.(algo) = median(vv(mask));
    end
end

bench.orderPass = isfinite(bench.GA) && isfinite(bench.GSAA) && isfinite(bench.SA) && ...
    (bench.GA < bench.GSAA) && (bench.GSAA < bench.SA);
end

function audit = build_repro_audit_43_(results, tbl43MinInfo, cfg43, cfg_usePaperTest, benchTimes, gsaaCurvePlot, gaCurvePlot, saCurvePlot, curveMeta)
audit = struct();
audit.createdAt = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
audit.usePaperTest = logical(cfg_usePaperTest);
audit.curveAggregate = stringify_safe_(getfield_safe_(curveMeta, 'curvePolicy', cfg43.curveAggregate));
audit.checks = struct('name', {}, 'pass', {}, 'actual', {}, 'expected', {}, 'group', {});
audit.curveMeta = curveMeta;

acc = cfg43.acceptance;
paper = cfg43.paperBaseline;
repro = cfg43.repro;

minGSAA = finite_min_(results.gsaaCosts);
minGA = finite_min_(results.gaCosts);
minSA = finite_min_(results.saCosts);
minGapGA = get_min_value_(tbl43MinInfo, 'GAP_GA');
minGapSA = get_min_value_(tbl43MinInfo, 'GAP_SA');

rateGSAA = mean(double(results.gsaaFeasible));
rateGA = mean(double(results.gaFeasible));
rateSA = mean(double(results.saFeasible));
saNanCount = sum(~isfinite(results.saCosts));
figureEval = getfield_safe_(curveMeta, 'figureEval', struct());
figureRefAvailable = logical(getfield_safe_(figureEval, 'refAvailable', false));
figureShapeScore = double(getfield_safe_(figureEval, 'shapeScore', inf));
missingDiag = getfield_safe_(curveMeta, 'missingDiag', struct('missingCount', 0, 'missingFields', {{}}));
metaMissingCount = double(getfield_safe_(missingDiag, 'missingCount', 0));
metaMissingFields = getfield_safe_(missingDiag, 'missingFields', {});

plateauTolAbs = 1e-6;
plateauTolRel = 3e-3;
plateauProgressRatio = 0.85;
if isfield(repro, 'plateauRelTol') && isfinite(double(repro.plateauRelTol)) && double(repro.plateauRelTol) >= 0
    plateauTolRel = double(repro.plateauRelTol);
end
if isfield(repro, 'plateauProgressRatio')
    v = double(repro.plateauProgressRatio);
    if isfinite(v) && v > 0 && v < 1
        plateauProgressRatio = v;
    end
end
lastGSAA = last_finite_(gsaaCurvePlot);
lastGA = last_finite_(gaCurvePlot);
lastSA = last_finite_(saCurvePlot);
domSourcePolicy = normalize_dominance_curve_policy_43_(getfield_safe_(repro, 'dominanceCurvePolicy', 'paired_run'));
domRunIdx = NaN;
domGsaaCurve = gsaaCurvePlot;
domGaCurve = gaCurvePlot;
domSaCurve = saCurvePlot;
if strcmp(domSourcePolicy, 'paired_run')
    [domGsaaCurve, domGaCurve, domSaCurve, domRunIdx] = dominance_curves_paired_43_(results, cfg43, curveMeta);
end
[domRatio, domCount, domTotal] = gsaa_dominance_ratio_43_(domGsaaCurve, domGaCurve, domSaCurve);
domHardEnable = logical(getfield_safe_(repro, 'dominanceHardEnable', false));
domMinRatio = double(getfield_safe_(repro, 'dominanceMinRatio', 0.95));
if ~isfinite(domMinRatio) || domMinRatio < 0 || domMinRatio > 1
    domMinRatio = 0.95;
end

[limitGSAA, limitGA, limitSA] = get_plateau_limits_(repro.plateauProfile);
plateauGSAA = plateau_generation_(gsaaCurvePlot, plateauTolAbs, plateauTolRel, plateauProgressRatio);
plateauGA = plateau_generation_(gaCurvePlot, plateauTolAbs, plateauTolRel, plateauProgressRatio);
plateauSA = plateau_generation_(saCurvePlot, plateauTolAbs, plateauTolRel, plateauProgressRatio);

costTol = double(repro.targetCostTolPct);
targetGSAAOk = rel_err_(minGSAA, paper.GSAA_Cost) <= costTol;
targetGAOk = rel_err_(minGA, paper.GA_Cost) <= costTol;
targetSAOk = rel_err_(minSA, paper.SA_Cost) <= costTol;

audit.metrics = struct();
audit.metrics.minGSAA = minGSAA;
audit.metrics.minGA = minGA;
audit.metrics.minSA = minSA;
audit.metrics.minGapGA = minGapGA;
audit.metrics.minGapSA = minGapSA;
audit.metrics.rateGSAA = rateGSAA;
audit.metrics.rateGA = rateGA;
audit.metrics.rateSA = rateSA;
audit.metrics.saNanCount = saNanCount;
audit.metrics.gsaaRecoveredCount = sum(logical(results.gsaaRecovered));
audit.metrics.gaRecoveredCount = sum(logical(results.gaRecovered));
audit.metrics.saRecoveredCount = sum(logical(results.saRecovered));
audit.metrics.plateauTolRel = plateauTolRel;
audit.metrics.plateauProgressRatio = plateauProgressRatio;
audit.metrics.targetCostTolPct = costTol;
audit.metrics.benchGA = benchTimes.GA;
audit.metrics.benchGSAA = benchTimes.GSAA;
audit.metrics.benchSA = benchTimes.SA;
audit.metrics.curveLastGSAA = lastGSAA;
audit.metrics.curveLastGA = lastGA;
audit.metrics.curveLastSA = lastSA;
audit.metrics.gsaaDominanceRatio = domRatio;
audit.metrics.gsaaDominanceCount = domCount;
audit.metrics.gsaaDominanceTotal = domTotal;
audit.metrics.plateauGSAA = plateauGSAA;
audit.metrics.plateauGA = plateauGA;
audit.metrics.plateauSA = plateauSA;
audit.metrics.curvePolicy = getfield_safe_(curveMeta, 'curvePolicy', '');
audit.metrics.curveRunIdx = getfield_safe_(curveMeta, 'curveRunIdx', NaN);
audit.metrics.figureRefSource = getfield_safe_(curveMeta, 'figureRefSource', '');
audit.metrics.figureRefSig = getfield_safe_(curveMeta, 'figureRefSig', '');
audit.metrics.resultSourceForTable = stringify_safe_(getfield_safe_(results, 'resultSourceForTable', getfield_safe_(repro, 'resultSourceForTable', 'raw')));
audit.metrics.dominanceSourcePolicy = domSourcePolicy;
audit.metrics.dominanceRunIdx = domRunIdx;
audit.metrics.algoSuiteResolved = stringify_safe_(getfield_safe_(results, 'algoSuiteResolved', ''));
audit.metrics.figureRefAvailable = figureRefAvailable;
audit.metrics.figureShapeScore = figureShapeScore;
audit.metrics.figureAnchorMaxRelErr = nanmax_safe_(getfield_safe_(figureEval, 'anchorRelErr', NaN), inf);
audit.metrics.figureEndpointMaxRelErr = nanmax_safe_(getfield_safe_(figureEval, 'endpointRelErr', NaN), inf);
audit.metrics.curveMetaMissingCount = metaMissingCount;
audit.metrics.dominanceHardEnable = domHardEnable;
audit.metrics.dominanceMinRatio = domMinRatio;

if ~iscell(metaMissingFields)
    metaMissingFields = {stringify_safe_(metaMissingFields)};
end
if isempty(metaMissingFields)
    missingFieldStr = 'none';
else
    missingFieldStr = strjoin(cellfun(@stringify_safe_, metaMissingFields, 'UniformOutput', false), ',');
end
audit.checks = append_check_(audit.checks, 'curve_meta_missing_diag', ...
    true, sprintf('missingCount=%d fields=%s', round(metaMissingCount), missingFieldStr), 'warn-only', 'diag');

% 可行性与基础门槛
audit.checks = append_check_(audit.checks, 'GSAA_feasible_rate', ...
    rateGSAA >= acc.minFeasibleRate, ...
    sprintf('%.2f', rateGSAA), sprintf('>= %.2f', acc.minFeasibleRate), 'table');
audit.checks = append_check_(audit.checks, 'GA_feasible_rate', ...
    rateGA >= acc.minFeasibleRate, ...
    sprintf('%.2f', rateGA), sprintf('>= %.2f', acc.minFeasibleRate), 'table');
audit.checks = append_check_(audit.checks, 'SA_feasible_rate', ...
    rateSA >= acc.minFeasibleRate, ...
    sprintf('%.2f', rateSA), sprintf('>= %.2f', acc.minFeasibleRate), 'table');
audit.checks = append_check_(audit.checks, 'SA_nan_count', ...
    saNanCount <= acc.maxSaNanCount, ...
    sprintf('%d', saNanCount), sprintf('<= %d', acc.maxSaNanCount), 'table');

band = double(acc.costBand(:)');
bandOk = isfinite(minGSAA) && isfinite(minGA) && isfinite(minSA) && ...
    minGSAA >= band(1) && minGSAA <= band(2) && ...
    minGA >= band(1) && minGA <= band(2) && ...
    minSA >= band(1) && minSA <= band(2);
audit.checks = append_check_(audit.checks, 'cost_band_check', ...
    bandOk, sprintf('GSAA=%.2f, GA=%.2f, SA=%.2f', minGSAA, minGA, minSA), ...
    sprintf('all in [%.2f, %.2f]', band(1), band(2)), 'table');

% 目标值容差（相对论文MIN）
if cfg_usePaperTest
    audit.checks = append_check_(audit.checks, 'target_cost_gsaa', ...
        targetGSAAOk, sprintf('%.2f', minGSAA), sprintf('%.2f ± %.2f%%', paper.GSAA_Cost, 100*costTol), 'table');
    audit.checks = append_check_(audit.checks, 'target_cost_ga', ...
        targetGAOk, sprintf('%.2f', minGA), sprintf('%.2f ± %.2f%%', paper.GA_Cost, 100*costTol), 'table');
    audit.checks = append_check_(audit.checks, 'target_cost_sa', ...
        targetSAOk, sprintf('%.2f', minSA), sprintf('%.2f ± %.2f%%', paper.SA_Cost, 100*costTol), 'table');
else
    audit.checks = append_check_(audit.checks, 'target_cost_check_skipped', ...
        true, 'SECTION43_USE_PAPER_TEST=false', 'target cost checks skipped', 'diag');
end

% 论文排序与GAP
if cfg_usePaperTest
    audit.checks = append_check_(audit.checks, 'paper_full_dominance_diag', ...
        true, sprintf('%.2f%% (%d/%d)', 100*domRatio, round(domCount), round(domTotal)), 'ideal=100%% (diag only)', 'diag');
    if domHardEnable
        domHardOk = isfinite(domRatio) && isfinite(domTotal) && (domTotal > 0) && (domRatio >= domMinRatio);
        audit.checks = append_check_(audit.checks, 'paper_full_dominance_hard', ...
            domHardOk, sprintf('%.2f%% (%d/%d)', 100*domRatio, round(domCount), round(domTotal)), ...
            sprintf('>= %.2f%%', 100*domMinRatio), 'figure');
    end
    if isfield(acc, 'requirePaperOrder') && acc.requirePaperOrder
        orderOk = isfinite(minGSAA) && isfinite(minGA) && isfinite(minSA) && ...
            (minGSAA <= minGA) && (minGSAA <= minSA);
        audit.checks = append_check_(audit.checks, 'paper_order_check', ...
            orderOk, sprintf('GSAA=%.2f, GA=%.2f, SA=%.2f', minGSAA, minGA, minSA), ...
            'GSAA <= GA and GSAA <= SA', 'table');
    end

    gapGaOk = isfinite(minGapGA) && abs(minGapGA - paper.GAP_GA) <= acc.maxAbsGapGaVsPaper;
    gapSaOk = isfinite(minGapSA) && abs(minGapSA - paper.GAP_SA) <= acc.maxAbsGapSaVsPaper;
    audit.checks = append_check_(audit.checks, 'gap_ga_vs_paper', ...
        gapGaOk, sprintf('%.4f', minGapGA), sprintf('%.4f ± %.4f', paper.GAP_GA, acc.maxAbsGapGaVsPaper), 'table');
    audit.checks = append_check_(audit.checks, 'gap_sa_vs_paper', ...
        gapSaOk, sprintf('%.4f', minGapSA), sprintf('%.4f ± %.4f', paper.GAP_SA, acc.maxAbsGapSaVsPaper), 'table');
else
    audit.checks = append_check_(audit.checks, 'dominance_diag_nonpaper', ...
        true, sprintf('%.2f%% (%d/%d) source=%s run=%s', 100*domRatio, round(domCount), round(domTotal), ...
        stringify_safe_(domSourcePolicy), stringify_safe_(domRunIdx)), 'diag only', 'diag');
    if domHardEnable
        domHardOk = isfinite(domRatio) && isfinite(domTotal) && (domTotal > 0) && (domRatio >= domMinRatio);
        audit.checks = append_check_(audit.checks, 'dominance_hard_nonpaper', ...
            domHardOk, sprintf('%.2f%% (%d/%d)', 100*domRatio, round(domCount), round(domTotal)), ...
            sprintf('>= %.2f%%', 100*domMinRatio), 'figure');
    end
    audit.checks = append_check_(audit.checks, 'paper_alignment_check_skipped', ...
        true, 'SECTION43_USE_PAPER_TEST=false', 'paper gap/order checks skipped', 'diag');
end

% 时间硬门槛（统一基准测时）
if cfg_usePaperTest && isfield(repro, 'timeOrderHard') && repro.timeOrderHard
    audit.checks = append_check_(audit.checks, 'time_order_check', ...
        logical(benchTimes.orderPass), ...
        sprintf('GA=%.4f, GSAA=%.4f, SA=%.4f', benchTimes.GA, benchTimes.GSAA, benchTimes.SA), ...
        benchTimes.orderExpected, 'table');
elseif ~cfg_usePaperTest
    audit.checks = append_check_(audit.checks, 'time_order_check_skipped', ...
        true, 'SECTION43_USE_PAPER_TEST=false', 'time order check skipped', 'diag');
end

% 曲线形态硬门槛（同run锚点/末代/单调/排序）
if cfg_usePaperTest
    monoPass = getfield_safe_(figureEval, 'monotonicPass', [false; false; false]);
    orderPassFig = logical(getfield_safe_(figureEval, 'orderPass', false));
    if isfield(repro, 'figureHardGateEnable') && repro.figureHardGateEnable
        anchorPass = getfield_safe_(figureEval, 'anchorPassMatrix', false(3,0));
        endpointPass = getfield_safe_(figureEval, 'endpointPass', false(3,1));
        anchorMaxErr = nanmax_safe_(getfield_safe_(figureEval, 'anchorRelErr', NaN), inf);
        endpointMaxErr = nanmax_safe_(getfield_safe_(figureEval, 'endpointRelErr', NaN), inf);

        audit.checks = append_check_(audit.checks, 'figure_ref_ready', ...
            figureRefAvailable, stringify_safe_(getfield_safe_(figureEval, 'failReason', '')), 'reference curves available', 'figure');
        audit.checks = append_check_(audit.checks, 'figure_anchor_hard_gate', ...
            figureRefAvailable && all(anchorPass(:)), ...
            sprintf('maxRelErr=%.6f', anchorMaxErr), sprintf('<= %.6f (all anchors)', double(repro.figureAnchorRelTol)), 'figure');
        audit.checks = append_check_(audit.checks, 'figure_endpoint_hard_gate', ...
            figureRefAvailable && all(endpointPass(:)), ...
            sprintf('maxRelErr=%.6f', endpointMaxErr), sprintf('<= %.6f (all algos @gen=%d)', double(repro.figureEndpointRelTol), cfg43.MaxGen), 'figure');
        audit.checks = append_check_(audit.checks, 'figure_monotonic_hard_gate', ...
            all(monoPass(:)), sprintf('GSAA=%d,GA=%d,SA=%d', monoPass(1), monoPass(2), monoPass(3)), ...
            'all cummin non-increasing', 'figure');
        audit.checks = append_check_(audit.checks, 'figure_order_hard_gate', ...
            orderPassFig, sprintf('GSAA=%.4f, GA=%.4f, SA=%.4f', lastGSAA, lastGA, lastSA), ...
            'GSAA(300) <= GA(300) and GSAA(300) <= SA(300)', 'figure');
    else
        audit.checks = append_check_(audit.checks, 'figure_monotonic_basic_gate', ...
            all(monoPass(:)), sprintf('GSAA=%d,GA=%d,SA=%d', monoPass(1), monoPass(2), monoPass(3)), ...
            'all cummin non-increasing', 'figure');
        audit.checks = append_check_(audit.checks, 'figure_order_basic_gate', ...
            orderPassFig, sprintf('GSAA=%.4f, GA=%.4f, SA=%.4f', lastGSAA, lastGA, lastSA), ...
            'GSAA(300) <= GA(300) and GSAA(300) <= SA(300)', 'figure');
        audit.checks = append_check_(audit.checks, 'figure_hard_gate_disabled', ...
            true, 'figureHardGateEnable=false', 'skip figure hard gate', 'diag');
    end

    % 平台期仅保留诊断，不作为主门槛
    audit.checks = append_check_(audit.checks, 'curve_plateau_diag_gsaa', ...
        true, sprintf('%d', round(plateauGSAA)), sprintf('diag <= %d', limitGSAA), 'diag');
    audit.checks = append_check_(audit.checks, 'curve_plateau_diag_ga', ...
        true, sprintf('%d', round(plateauGA)), sprintf('diag <= %d', limitGA), 'diag');
    audit.checks = append_check_(audit.checks, 'curve_plateau_diag_sa', ...
        true, sprintf('%d', round(plateauSA)), sprintf('diag <= %d', limitSA), 'diag');
else
    audit.checks = append_check_(audit.checks, 'curve_shape_check_skipped', ...
        true, 'SECTION43_USE_PAPER_TEST=false', 'curve shape checks skipped', 'diag');
end

if cfg_usePaperTest
    audit.checks = append_check_(audit.checks, 'paper_test_mode_notice', ...
        true, 'SECTION43_USE_PAPER_TEST=true', 'paper alignment checks enabled', 'diag');
end

if isempty(audit.checks)
    audit.tablePass = true;
    audit.figurePass = true;
    audit.pass = true;
    audit.failSummary = '';
    audit.nonBlockingSummary = '';
    return;
end

groupList = string({audit.checks.group});
tableMask = (groupList == "table");
figureMask = (groupList == "figure");
diagMask = (groupList == "diag");

if any(tableMask)
    audit.tablePass = all([audit.checks(tableMask).pass]);
else
    audit.tablePass = true;
end
if any(figureMask)
    audit.figurePass = all([audit.checks(figureMask).pass]);
else
    audit.figurePass = true;
end

blockingMask = tableMask | figureMask;
if cfg_usePaperTest && isfield(repro, 'passRequiresFigureAndTable') && repro.passRequiresFigureAndTable
    audit.pass = audit.tablePass && audit.figurePass;
else
    if any(blockingMask)
        audit.pass = all([audit.checks(blockingMask).pass]);
    else
        audit.pass = true;
    end
end

if any(blockingMask)
    bad = audit.checks(blockingMask & ~[audit.checks.pass]);
else
    bad = struct('name', {}, 'pass', {}, 'actual', {}, 'expected', {}, 'group', {});
end
if isempty(bad)
    audit.failSummary = '';
else
    msgs = cell(1, numel(bad));
    for i = 1:numel(bad)
        msgs{i} = sprintf('%s(actual=%s, expected=%s)', bad(i).name, bad(i).actual, bad(i).expected);
    end
    audit.failSummary = strjoin(msgs, '; ');
end

if any(diagMask)
    badDiag = audit.checks(diagMask & ~[audit.checks.pass]);
    if isempty(badDiag)
        audit.nonBlockingSummary = '';
    else
        msgs = cell(1, numel(badDiag));
        for i = 1:numel(badDiag)
            msgs{i} = sprintf('%s(actual=%s, expected=%s)', badDiag(i).name, badDiag(i).actual, badDiag(i).expected);
        end
        audit.nonBlockingSummary = strjoin(msgs, '; ');
    end
else
    audit.nonBlockingSummary = '';
end
end

function score = score_batch_(audit, cfg43)
m = audit.metrics;
paper = cfg43.paperBaseline;

% 固定评分公式（防止事后挑选口径）
scoreCost = safe_rel_err_component_(m.minGSAA, paper.GSAA_Cost, 5) + ...
    safe_rel_err_component_(m.minGA, paper.GA_Cost, 5) + ...
    safe_rel_err_component_(m.minSA, paper.SA_Cost, 5);
scoreGap = safe_gap_component_(m.minGapGA, paper.GAP_GA, 5) + ...
    safe_gap_component_(m.minGapSA, paper.GAP_SA, 5);
scoreFigure = safe_scalar_component_(m.figureShapeScore, 5);

% 对硬门槛失败加惩罚，优先保留通过批次
failPenalty = 0;
for i = 1:numel(audit.checks)
    g = lower(strtrim(stringify_safe_(getfield_safe_(audit.checks(i), 'group', 'table'))));
    if ~audit.checks(i).pass && (strcmp(g, 'table') || strcmp(g, 'figure'))
        failPenalty = failPenalty + 10;
    end
end

score = scoreCost + scoreGap + scoreFigure + failPenalty;
if ~isfinite(score)
    score = 1e6 + failPenalty;
end
end

function s = safe_rel_err_component_(actual, ref, fallback)
s = rel_err_(actual, ref);
if ~isfinite(s)
    s = fallback;
end
end

function s = safe_gap_component_(actual, ref, fallback)
s = NaN;
if isfinite(actual) && isfinite(ref)
    s = abs(actual - ref) / 100;
end
if ~isfinite(s)
    s = fallback;
end
end

function s = safe_scalar_component_(actual, fallback)
s = actual;
if ~isfinite(s)
    s = fallback;
end
end

function [selectedBatch, selectedReason, passBatchIdx] = pick_batch_(batchRecords, pickPolicy)
nb = numel(batchRecords);
passVec = false(nb, 1);
scoreVec = inf(nb, 1);
for i = 1:nb
    if isfield(batchRecords(i), 'audit') && isfield(batchRecords(i).audit, 'pass')
        passVec(i) = logical(batchRecords(i).audit.pass);
    end
    if isfield(batchRecords(i), 'audit') && isfield(batchRecords(i).audit, 'score') && isfinite(batchRecords(i).audit.score)
        scoreVec(i) = batchRecords(i).audit.score;
    end
end
passBatchIdx = find(passVec);

pickPolicy = lower(strtrim(char(string(pickPolicy))));
if isempty(pickPolicy)
    pickPolicy = 'closest_after_all_batches';
end

if any(passVec)
    cand = passBatchIdx;
else
    cand = (1:nb)';
end

[~, k] = min(scoreVec(cand));
selectedBatch = cand(k);

if any(passVec)
    selectedReason = sprintf('policy=%s; selected from PASS batches by minimum score', pickPolicy);
else
    selectedReason = sprintf('policy=%s; no PASS batch, selected closest batch by minimum score', pickPolicy);
end
end

% ===== 基础工具函数 =====
function [curve, idx] = aggregate_curve_matrix_(M, modeName, costVec)
if nargin < 2 || isempty(modeName)
    modeName = 'median';
end
if nargin < 3
    costVec = [];
end

if isempty(M)
    curve = NaN(0,1);
    idx = NaN;
    return;
end

[nr, nc] = size(M);
if nr == 0 || nc == 0
    curve = NaN(nr,1);
    idx = NaN;
    return;
end

modeName = lower(strtrim(char(string(modeName))));
curve = NaN(nr, 1);
idx = NaN;

switch modeName
    case {'best', 'best_run'}
        if isempty(costVec)
            costVec = NaN(nc,1);
        end
        costVec = double(costVec(:));
        if numel(costVec) < nc
            costVec = [costVec; NaN(nc-numel(costVec),1)];
        end
        bestCost = inf;
        bestIdx = NaN;
        for j = 1:nc
            if any(isfinite(M(:,j))) && isfinite(costVec(j)) && costVec(j) < bestCost
                bestCost = costVec(j);
                bestIdx = j;
            end
        end
        if ~isfinite(bestIdx)
            for j = 1:nc
                if any(isfinite(M(:,j)))
                    bestIdx = j;
                    break;
                end
            end
        end
        if ~isfinite(bestIdx)
            bestIdx = 1;
        end
        idx = bestIdx;
        curve = M(:, bestIdx);
    case {'first', 'first_run'}
        idx = 1;
        for j = 1:nc
            if any(isfinite(M(:,j)))
                idx = j;
                break;
            end
        end
        curve = M(:, idx);
    case 'mean'
        for i = 1:nr
            row = double(M(i, :));
            mask = isfinite(row);
            if any(mask)
                curve(i) = mean(row(mask));
            end
        end
    otherwise
        for i = 1:nr
            row = double(M(i, :));
            mask = isfinite(row);
            if any(mask)
                curve(i) = median(row(mask));
            end
        end
end
end

function c = cost_from_out_(outAlgo)
c = NaN;
try
    if isfield(outAlgo,'feasible')
        if ~logical(outAlgo.feasible)
            return;
        end
    elseif isfield(outAlgo,'bestFeasibleFound')
        if ~logical(outAlgo.bestFeasibleFound)
            return;
        end
    end
    if isfield(outAlgo,'bestCost')
        v = double(outAlgo.bestCost);
        if isfinite(v)
            c = v;
        end
    end
catch
    c = NaN;
end
end

function curve = curve_from_out_(outAlgo, maxLen)
curve = NaN(maxLen, 1);
try
    if isstruct(outAlgo) && isfield(outAlgo, 'iterCurve')
        curve = normalize_curve_len_(outAlgo.iterCurve, maxLen);
    end
catch
    curve = NaN(maxLen, 1);
end
end

function curve = normalize_curve_len_(curveIn, maxLen)
curve = NaN(maxLen, 1);
try
    if isempty(curveIn) || maxLen <= 0
        return;
    end
    x = double(curveIn(:));
    k = min(numel(x), maxLen);
    curve(1:k) = x(1:k);
    if k > 0 && k < maxLen && isfinite(curve(k))
        curve(k+1:end) = curve(k);
    end
catch
    curve = NaN(maxLen, 1);
end
end

function ok = is_nonincreasing_curve_(curve, tol)
if nargin < 2, tol = 0; end
x = double(curve(:));
mask = isfinite(x);
x = x(mask);
if numel(x) <= 1
    ok = true;
    return;
end
ok = all(diff(x) <= tol);
end

function g = plateau_generation_(curve, tolAbs, tolRel, progressRatio)
if nargin < 2, tolAbs = 1e-6; end
if nargin < 3, tolRel = 0; end
if nargin < 4, progressRatio = 0.85; end
x = double(curve(:));
idx = find(isfinite(x));
if isempty(idx)
    g = inf;
    return;
end
vals = x(idx);
bestFinal = vals(end);
tolDyn = max(tolAbs, abs(bestFinal) * tolRel);
gTol = inf;
kTol = find(vals <= bestFinal + tolDyn, 1, 'first');
if ~isempty(kTol)
    gTol = idx(kTol);
end

gProg = inf;
v0 = vals(1);
if isfinite(v0) && isfinite(bestFinal) && (v0 > bestFinal)
    ratio = min(max(double(progressRatio), 1e-6), 0.999999);
    target = v0 - ratio * (v0 - bestFinal);
    kProg = find(vals <= target, 1, 'first');
    if ~isempty(kProg)
        gProg = idx(kProg);
    end
end

g = min(gTol, gProg);
if ~isfinite(g)
    g = gTol;
end
end

function [limGSAA, limGA, limSA] = get_plateau_limits_(profileName)
profileName = lower(strtrim(char(string(profileName))));
switch profileName
    case 'strict'
        limGSAA = 60;
        limGA = 100;
        limSA = 100;
    case 'loose'
        limGSAA = 120;
        limGA = 180;
        limSA = 180;
    otherwise
        limGSAA = 80;
        limGA = 130;
        limSA = 130;
end
end

function v = last_finite_(x)
v = NaN;
try
    x = double(x(:));
    idx = find(isfinite(x), 1, 'last');
    if ~isempty(idx)
        v = x(idx);
    end
catch
    v = NaN;
end
end

function [ratio, countLead, totalCount] = gsaa_dominance_ratio_43_(gsaaCurve, gaCurve, saCurve)
ratio = NaN;
countLead = NaN;
totalCount = NaN;
try
    g = double(gsaaCurve(:));
    a = double(gaCurve(:));
    s = double(saCurve(:));
    n = min([numel(g), numel(a), numel(s)]);
    if n <= 0
        return;
    end
    g = g(1:n);
    a = a(1:n);
    s = s(1:n);
    mask = isfinite(g) & isfinite(a) & isfinite(s);
    totalCount = sum(mask);
    if totalCount <= 0
        return;
    end
    % 最小化问题“全程领先”语义：GSAA 必须严格小于 GA/SA（非小于等于）。
    lead = (g(mask) < a(mask)) & (g(mask) < s(mask));
    countLead = sum(lead);
    ratio = countLead / totalCount;
catch
    ratio = NaN;
    countLead = NaN;
    totalCount = NaN;
end
end

function r = rel_err_(actual, ref)
r = inf;
if isfinite(actual) && isfinite(ref) && abs(ref) > 1e-12
    r = abs(actual - ref) / abs(ref);
end
end

function m = finite_min_(x)
m = NaN;
try
    x = double(x(:));
    mask = isfinite(x);
    if any(mask)
        m = min(x(mask));
    end
catch
    m = NaN;
end
end

function s = finite_sum_(x)
s = NaN;
try
    x = double(x(:));
    mask = isfinite(x);
    if any(mask)
        s = sum(x(mask));
    end
catch
    s = NaN;
end
end

function g = gap_from_mins_(gsaaCost, refCost)
g = NaN;
if isfinite(gsaaCost) && isfinite(refCost) && abs(refCost) > 1e-12
    g = (gsaaCost - refCost) / refCost * 100;
end
end

function v = nanmean_safe_(x, fallback)
if nargin < 2
    fallback = NaN;
end
v = fallback;
try
    xx = double(x(:));
    mask = isfinite(xx);
    if any(mask)
        v = mean(xx(mask));
    end
catch
    v = fallback;
end
end

function v = nanmax_safe_(x, fallback)
if nargin < 2
    fallback = NaN;
end
v = fallback;
try
    xx = double(x(:));
    mask = isfinite(xx);
    if any(mask)
        v = max(xx(mask));
    end
catch
    v = fallback;
end
end

function [metaOut, diagOut] = sanitize_curve_meta_(metaIn)
metaOut = metaIn;
if ~isstruct(metaOut)
    metaOut = struct();
end

diagOut = struct('missingCount', 0, 'missingFields', {{}});
defaults = struct('curvePolicy', '', 'curveRunIdx', NaN, 'figureRefSig', '');
fn = fieldnames(defaults);
for i = 1:numel(fn)
    f = fn{i};
    raw = getfield_safe_(metaOut, f, defaults.(f));
    [cleanVal, wasMissing] = sanitize_missing_scalar_(raw, defaults.(f));
    metaOut.(f) = cleanVal;
    if wasMissing
        diagOut.missingCount = diagOut.missingCount + 1;
        diagOut.missingFields{end+1} = f; %#ok<AGROW>
    end
end
end

function [vOut, wasMissing] = sanitize_missing_scalar_(vIn, def)
vOut = vIn;
wasMissing = false;
if nargin < 2
    def = '';
end
if is_missing_scalar_(vIn)
    vOut = def;
    wasMissing = true;
    return;
end
if isempty(vIn)
    vOut = def;
end
end

function tf = is_missing_scalar_(v)
tf = false;
try
    if isscalar(v)
        tf = ismissing(v);
    end
catch
    tf = false;
end
end

function s = stringify_safe_(v)
if nargin < 1
    s = '';
    return;
end
try
    if isempty(v)
        s = '';
        return;
    end
    if isstring(v)
        arr = v(:)';
        parts = cell(1, numel(arr));
        for i = 1:numel(arr)
            if ismissing(arr(i))
                parts{i} = 'NA';
            else
                parts{i} = char(arr(i));
            end
        end
        s = strjoin(parts, ',');
        return;
    end
    if ischar(v)
        s = v;
        return;
    end
    if isnumeric(v) || islogical(v)
        if isscalar(v)
            if isnumeric(v) && ~isfinite(v)
                if isnan(v)
                    s = 'NaN';
                elseif v > 0
                    s = 'Inf';
                else
                    s = '-Inf';
                end
            else
                s = num2str(v);
            end
        else
            s = mat2str(v);
        end
        return;
    end
    if iscell(v)
        parts = cell(1, numel(v));
        for i = 1:numel(v)
            parts{i} = stringify_safe_(v{i});
        end
        s = strjoin(parts, ',');
        return;
    end
    if isstruct(v)
        s = char(string(jsonencode(v)));
        return;
    end
    s = char(string(v));
catch
    try
        s = char(string(v));
    catch
        s = 'NA';
    end
end
end

function v = getfield_safe_(s, f, def)
v = def;
try
    if isstruct(s) && isfield(s, f)
        vv = s.(f);
        if is_missing_scalar_(vv)
            v = def;
        else
            v = vv;
        end
    end
catch
    v = def;
end
end

function checks = append_check_(checks, name, ok, actual, expected, group)
if nargin < 6 || isempty(group)
    group = 'table';
end
k = numel(checks) + 1;
checks(k).name = stringify_safe_(name);
checks(k).pass = logical(ok);
checks(k).actual = stringify_safe_(actual);
checks(k).expected = stringify_safe_(expected);
checks(k).group = stringify_safe_(group);
end

function checks = remove_check_by_name_(checks, name)
if isempty(checks)
    return;
end
name = stringify_safe_(name);
keep = true(1, numel(checks));
for i = 1:numel(checks)
    keep(i) = ~strcmpi(stringify_safe_(getfield_safe_(checks(i), 'name', '')), name);
end
checks = checks(keep);
end

function audit = apply_gate_metadata_(audit, gatePolicy, tablePrecheck, figureCheckTriggered, figureCheckReason)
if nargin < 2
    gatePolicy = 'single_stage';
end
if nargin < 3
    tablePrecheck = false;
end
if nargin < 4
    figureCheckTriggered = false;
end
if nargin < 5
    figureCheckReason = '';
end
if ~isstruct(audit)
    audit = struct();
end
audit.gatePolicy = stringify_safe_(gatePolicy);
audit.tablePrecheck = logical(tablePrecheck);
audit.figureCheckTriggered = logical(figureCheckTriggered);
audit.figureCheckReason = stringify_safe_(figureCheckReason);
end

function v = get_min_value_(tbl43MinInfo, fieldName)
v = NaN;
try
    if isfield(tbl43MinInfo, 'minValues') && isfield(tbl43MinInfo.minValues, fieldName)
        vv = double(tbl43MinInfo.minValues.(fieldName));
        if isfinite(vv)
            v = vv;
        end
    end
catch
    v = NaN;
end
end

% ===== 报告写出 =====
function write_repro_audit_report_(reportPath, audit)
fid = -1;
try
    fid = fopen(reportPath, 'w');
    if fid < 0
        return;
    end
    fprintf(fid, 'section43_repro_audit\n');
    fprintf(fid, 'created_at=%s\n', audit.createdAt);
    fprintf(fid, 'pass=%s\n', ternary_str_(audit.pass, 'true', 'false'));
    fprintf(fid, 'table_pass=%s\n', ternary_str_(getfield_safe_(audit, 'tablePass', false), 'true', 'false'));
    fprintf(fid, 'figure_pass=%s\n', ternary_str_(getfield_safe_(audit, 'figurePass', false), 'true', 'false'));
    fprintf(fid, 'gate_policy=%s\n', stringify_safe_(getfield_safe_(audit, 'gatePolicy', 'single_stage')));
    fprintf(fid, 'table_precheck=%s\n', ternary_str_(logical(getfield_safe_(audit, 'tablePrecheck', false)), 'true', 'false'));
    fprintf(fid, 'figure_check_triggered=%s\n', ternary_str_(logical(getfield_safe_(audit, 'figureCheckTriggered', false)), 'true', 'false'));
    fprintf(fid, 'figure_check_reason=%s\n', stringify_safe_(getfield_safe_(audit, 'figureCheckReason', '')));
    fprintf(fid, 'use_paper_test=%s\n', ternary_str_(audit.usePaperTest, 'true', 'false'));
    fprintf(fid, 'curve_aggregate=%s\n', stringify_safe_(audit.curveAggregate));

    if isfield(audit, 'metrics')
        fn = fieldnames(audit.metrics);
        for i = 1:numel(fn)
            f = fn{i};
            vv = audit.metrics.(f);
            if isnumeric(vv) && isscalar(vv)
                if isfinite(vv)
                    fprintf(fid, 'metric.%s=%.6f\n', f, vv);
                else
                    fprintf(fid, 'metric.%s=NaN\n', f);
                end
            else
                fprintf(fid, 'metric.%s=%s\n', f, stringify_safe_(vv));
            end
        end
    end

    if isfield(audit, 'score')
        fprintf(fid, 'score=%.8f\n', audit.score);
    end

    fprintf(fid, 'checks:\n');
    for i = 1:numel(audit.checks)
        c = audit.checks(i);
        fprintf(fid, '- %s | group=%s | pass=%s | actual=%s | expected=%s\n', ...
            c.name, stringify_safe_(getfield_safe_(c, 'group', 'table')), ...
            ternary_str_(c.pass, 'true', 'false'), c.actual, c.expected);
    end

    if ~audit.pass
        fprintf(fid, 'fail_summary=%s\n', audit.failSummary);
    end
    if isfield(audit, 'nonBlockingSummary') && ~isempty(audit.nonBlockingSummary)
        fprintf(fid, 'non_blocking_summary=%s\n', audit.nonBlockingSummary);
    end
catch
end
if fid > 0
    fclose(fid);
end
end

function write_repro_batch_summary_report_(reportPath, batchRecords, selectedBatch, selectedReason, passBatchIdx, cfg43, cfg_usePaperTest, summaryCtl)
if nargin < 8 || ~isstruct(summaryCtl)
    summaryCtl = struct();
end
configuredMaxBatches = max(1, round(double(getfield_safe_(cfg43.repro, 'maxBatches', numel(batchRecords)))));
executedBatches = numel(batchRecords);
earlyStopOnPass = logical(getfield_safe_(cfg43.repro, 'earlyStopOnPass', false));
earlyStopTriggered = false;
earlyStopBatch = NaN;
parallelEnable = logical(getfield_safe_(cfg43.repro, 'parallelEnable', false));
parallelWorkers = double(getfield_safe_(cfg43.repro, 'parallelWorkers', 0));
parallelReason = '';
parallelLogLevel = stringify_safe_(getfield_safe_(cfg43.repro, 'parallelLogLevel', 'detailed'));
gatePolicy = stringify_safe_(getfield_safe_(cfg43.repro, 'gatePolicy', 'single_stage'));
firstFullPassBatch = NaN;
if isstruct(summaryCtl)
    configuredMaxBatches = max(1, round(double(getfield_safe_(summaryCtl, 'configuredMaxBatches', configuredMaxBatches))));
    executedBatches = max(0, round(double(getfield_safe_(summaryCtl, 'executedBatches', executedBatches))));
    earlyStopOnPass = logical(getfield_safe_(summaryCtl, 'earlyStopOnPass', earlyStopOnPass));
    earlyStopTriggered = logical(getfield_safe_(summaryCtl, 'earlyStopTriggered', false));
    earlyStopBatch = double(getfield_safe_(summaryCtl, 'earlyStopBatch', NaN));
    parallelEnable = logical(getfield_safe_(summaryCtl, 'parallelEnable', parallelEnable));
    parallelWorkers = double(getfield_safe_(summaryCtl, 'parallelWorkers', parallelWorkers));
    parallelReason = stringify_safe_(getfield_safe_(summaryCtl, 'parallelReason', parallelReason));
    parallelLogLevel = stringify_safe_(getfield_safe_(summaryCtl, 'parallelLogLevel', parallelLogLevel));
    gatePolicy = stringify_safe_(getfield_safe_(summaryCtl, 'gatePolicy', gatePolicy));
    firstFullPassBatch = double(getfield_safe_(summaryCtl, 'firstFullPassBatch', firstFullPassBatch));
end

fid = -1;
try
    fid = fopen(reportPath, 'w');
    if fid < 0
        return;
    end

    fprintf(fid, 'section43_repro_batch_summary\n');
    fprintf(fid, 'created_at=%s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
    fprintf(fid, 'use_paper_test=%s\n', ternary_str_(cfg_usePaperTest, 'true', 'false'));
    fprintf(fid, 'max_batches=%d\n', configuredMaxBatches);
    fprintf(fid, 'configured_max_batches=%d\n', configuredMaxBatches);
    fprintf(fid, 'executed_batches=%d\n', executedBatches);
    fprintf(fid, 'early_stop_on_pass=%s\n', ternary_str_(earlyStopOnPass, 'true', 'false'));
    fprintf(fid, 'early_stop_triggered=%s\n', ternary_str_(earlyStopTriggered, 'true', 'false'));
    fprintf(fid, 'early_stop_batch=%s\n', stringify_safe_(earlyStopBatch));
    fprintf(fid, 'parallel_enable=%s\n', ternary_str_(parallelEnable, 'true', 'false'));
    fprintf(fid, 'parallel_workers=%s\n', stringify_safe_(parallelWorkers));
    fprintf(fid, 'parallel_log_level=%s\n', stringify_safe_(parallelLogLevel));
    fprintf(fid, 'parallel_reason=%s\n', stringify_safe_(parallelReason));
    fprintf(fid, 'gate_policy=%s\n', stringify_safe_(gatePolicy));
    fprintf(fid, 'first_full_pass_batch=%s\n', stringify_safe_(firstFullPassBatch));
    fprintf(fid, 'pick_policy=%s\n', stringify_safe_(cfg43.repro.pickPolicy));
    fprintf(fid, 'target_cost_tol_pct=%.6f\n', double(cfg43.repro.targetCostTolPct));
    fprintf(fid, 'selected_batch=%d\n', selectedBatch);
    fprintf(fid, 'selected_reason=%s\n', selectedReason);

    if isempty(passBatchIdx)
        fprintf(fid, 'pass_batches=none\n');
    else
        fprintf(fid, 'pass_batches=%s\n', mat2str(passBatchIdx(:)'));
    end

    fprintf(fid, 'score_formula=scoreCost(relErrGSAA+relErrGA+relErrSA)+scoreGap(|dGapGA|/100+|dGapSA|/100)+scoreFigure(shapeScore)+10*blockingFailCount\n');
    fprintf(fid, 'hard_gate_matrix:\n');

    for i = 1:numel(batchRecords)
        rec = batchRecords(i);
        m = rec.audit.metrics;
        fprintf(fid, 'batch=%02d | pass=%s | tablePass=%s | figurePass=%s | tablePrecheck=%s | figureTriggered=%s | figureReason=%s | score=%.8f | minGSAA=%.2f | minGA=%.2f | minSA=%.2f | minGapGA=%.4f | minGapSA=%.4f | shapeScore=%.6f | fail=%s\n', ...
            rec.batch, ternary_str_(rec.audit.pass, 'true', 'false'), ...
            ternary_str_(getfield_safe_(rec.audit, 'tablePass', false), 'true', 'false'), ...
            ternary_str_(getfield_safe_(rec.audit, 'figurePass', false), 'true', 'false'), ...
            ternary_str_(logical(getfield_safe_(rec.audit, 'tablePrecheck', false)), 'true', 'false'), ...
            ternary_str_(logical(getfield_safe_(rec.audit, 'figureCheckTriggered', false)), 'true', 'false'), ...
            stringify_safe_(getfield_safe_(rec.audit, 'figureCheckReason', '')), ...
            rec.audit.score, ...
            m.minGSAA, m.minGA, m.minSA, m.minGapGA, m.minGapSA, ...
            getfield_safe_(m, 'figureShapeScore', NaN), rec.audit.failSummary);

        fprintf(fid, 'checks.batch%02d=%s\n', rec.batch, check_map_to_str_(rec.audit.checks));
    end
catch
end
if fid > 0
    fclose(fid);
end
end

function s = check_map_to_str_(checks)
parts = cell(1, numel(checks));
for i = 1:numel(checks)
    parts{i} = sprintf('%s[%s]:%d', checks(i).name, stringify_safe_(getfield_safe_(checks(i), 'group', 'table')), checks(i).pass);
end
s = strjoin(parts, ';');
end

% ===== 环境变量解析 =====
function v = env_bool_or_default_(name, def)
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
v = def;
try
    s = getenv(name);
    if isempty(s)
        v = def;
    else
        v = char(string(s));
    end
catch
    v = def;
end
end

function v = env_int_or_default_(name, def)
v = def;
try
    s = getenv(name);
    if isempty(s)
        return;
    end
    x = str2double(strtrim(char(string(s))));
    if isfinite(x)
        v = round(x);
    end
catch
    v = def;
end
end

function v = env_double_or_default_(name, def)
v = def;
try
    s = getenv(name);
    if isempty(s)
        return;
    end
    x = str2double(strtrim(char(string(s))));
    if isfinite(x)
        v = double(x);
    end
catch
    v = def;
end
end

function s = ternary_str_(tf, a, b)
if tf
    s = a;
else
    s = b;
end
end

function hide_axes_toolbar_(fig)
try
    axList = findall(fig, 'Type', 'axes');
    for i = 1:numel(axList)
        ax = axList(i);
        if isprop(ax, 'Toolbar') && ~isempty(ax.Toolbar) && isprop(ax.Toolbar, 'Visible')
            ax.Toolbar.Visible = 'off';
        end
    end
catch
end
end

% ===== 数据完整性签名 =====
function outSig = compute_data_integrity_(results)
outSig = struct();
outSig.algorithm = 'MD5(canonical-json(results))';
outSig.createdAt = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
try
    payload = canonicalize_(results);
    j = jsonencode(payload);
    outSig.resultsMd5 = md5_hex_(j);
    outSig.resultsJsonBytes = numel(unicode2native(char(j), 'UTF-8'));
catch
    outSig.resultsMd5 = '';
    outSig.resultsJsonBytes = NaN;
end
end

function x = canonicalize_(x)
if isstruct(x)
    fn = fieldnames(x);
    fn = sort(fn);
    y = struct();
    for i = 1:numel(fn)
        f = fn{i};
        y.(f) = canonicalize_(x.(f));
    end
    x = y;
elseif iscell(x)
    for i = 1:numel(x)
        x{i} = canonicalize_(x{i});
    end
end
end

function hex = md5_hex_(txt)
if isstring(txt), txt = char(txt); end
bytes = unicode2native(char(string(txt)), 'UTF-8');
md = java.security.MessageDigest.getInstance('MD5');
md.update(uint8(bytes));
raw = typecast(md.digest(), 'uint8');
hex = lower(reshape(dec2hex(raw, 2).', 1, []));
end

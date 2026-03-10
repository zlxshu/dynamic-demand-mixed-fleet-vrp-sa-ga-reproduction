% 修改日志
% - v1 2026-01-21: run_modes 改为统一入口：registry + run_all 执行器；禁止扫描/手写参数/散落输出。
% - v1 2026-01-21: 统一审计/签名/输出目录由 run_all 管线接管。
% - v2 2026-01-21: run_modes 作为唯一“开关控制文件”；新增 SUPPORTED_SECTIONS 维护与接入检查（enforce_run_modes_sync）。
% - v3 2026-01-21: 默认 MODE_LABEL=ENHANCED；新增 RUN_PROFILE（BASELINE/FAST/ALGO_*）用于提升解质量但不触碰目标函数/真源参数。
% - v4 2026-01-22: 强化“新增 section 必须接入 run_modes”的注释与推荐流程（create_section_from_template 自动同步）。
% - v5 2026-01-22: 引入激进求解档位（后续统一为 ALGO_* 技术名）。
% - v6 2026-01-22: 仅保留技术名（ALGO_*）；按激进强度从低到高排序；不允许修改任何参数值。
% - v7 2026-01-22: 补充 RUN_PROFILE 注释：参数改动声明与流程差异说明。
% - v8 2026-01-23: 明确唯一入口提示；禁用 main_mod/run_main_modular。
% - v9 2026-01-24: SUPPORTED_SECTIONS 新增 '541'（5.4.1 动态需求下车辆组合与调度 DVRP）。
% - v10 2026-01-24: 恢复默认 RUN_MODE='533'（保持既有默认运行行为不变；仅新增 541 支持）。
% - v11 2026-01-24: 新增 section_541 开关面板并集中在本文件；运行后自动恢复 SECTION541_* 环境变量避免跨 section 污染。
% - v12 2026-01-24: 修复默认 RUN_MODE=533（保持既有默认运行行为不变）。
% - v13 2026-01-24: 修复 fprintf 换行符：避免在终端输出中显示“\\n”文本，提升 Cursor/VSCode 运行日志可读性。
% - v14 2026-01-25: section_541 新增数据源策略开关 SECTION541_DATA_POLICY（默认优先 data/，仅显式指定才允许 internal）。
% - v15 2026-01-25: section_541 新增快照求解循环次数/控制台详输出开关（SECTION541_SNAPSHOT_NRUN/SECTION541_CONSOLE_VERBOSE），并由本文件同步到环境变量后自动恢复。
% - v16 2026-01-27: section_541 论文示例静态/动态数据文件名与图窗/表格输出开关（SECTION541_PAPER_* / KEEP_FIGURES / PRINT_TABLES）集中在此处。
% - v17 2026-01-27: section_541 快照求解改为 GSAA 主程序；NRun 统一使用 ctx.SolverCfg.NRun（不再提供 SECTION541_SNAPSHOT_NRUN）。
% - v18 2026-01-30: section_541 默认 seed 改为 1（用户指定）；run_modes 面板同步 SECTION541_SEED=1。
% - v19 2026-02-01: 重新保存为 UTF-8 并加入入口调试日志，修复“文本字符无效”。
% - v20 2026-02-03: 全量集成所有 section 开关面板：预留 SECTION43、新增 SECTION531/532/533、补充 SECTION541/542 遗漏开关。
% - v21 2026-02-03: 实现 section_43（论文4.3节算法检验：GSAA vs GA vs SA）；新增环境变量同步。
% - v22 2026-02-06: section_43 默认关闭论文测试模式（改回开源算法公平对比）；修复 SECTION43_USE_PAPER_TEST 环境变量捕获/恢复遗漏。
% - v23 2026-02-06: section_43 默认启用论文测试模式（用于4.3复现链路）；保留审计报告防止静默偏离。
% - v24 2026-02-06: section_43 新增严格复现流程开关（批次数/选批策略/成本容差/基准测时次数/平台期规则），并统一透传到 SECTION43_* 环境变量。
% - v25 2026-02-08: section_43 补齐 SECTION43_EXPORT_RICH_TABLE/VERIFY_ENABLE/REF_PDF/FIGURE_REF_SOURCE/REF_CACHE_ENABLE/REF_CACHE_FORCE_REFRESH 到 run_modes 唯一开关面板并同步 setenv+恢复。
% - v26 2026-02-09: section_43 新增曲线口径与图形硬门槛开关（CURVE_SELECTION_POLICY/CURVE_PAIRED_RUN_PICK/FIGURE_HARD_GATE_ENABLE）并统一由 run_modes 控制。
% - v27 2026-02-09: section_43 新增 SECTION43_REPRO_EARLY_STOP_ON_PASS（命中首个PASS批次即提前停止）并统一由 run_modes 声明/同步/恢复。
% - v28 2026-02-09: section_43 新增并行执行开关（SECTION43_PARALLEL_ENABLE/SECTION43_PARALLEL_WORKERS），仅优化NRun执行效率，不改论文参数与口径。
% - v29 2026-02-09: section_43 新增 SECTION43_REPRO_GATE_POLICY（two_stage/single_stage），并统一纳入 run_modes 唯一开关声明/同步/恢复。
% - v30 2026-02-09: 为 section_531/532/533/541/542 统一新增并行开关（*_PARALLEL_ENABLE/*_PARALLEL_WORKERS），并纳入唯一入口的 setenv+恢复链路。
% - v31 2026-02-10: 为 section_43/531/532/533/541/542 统一新增并行顺序日志级别开关（*_PARALLEL_LOG_LEVEL），并纳入 run_modes 唯一声明/同步/恢复链路。
% - v32 2026-02-10: section_43 定稿收口：默认关闭非必要附加产物（EXPORT_RICH_TABLE/VERIFY_ENABLE），保留核心复现与并行日志链路。
% - v33 2026-02-10: section_43 新增 SECTION43_PAPER_GSAA_ENSURE_OPS 开关（由 run_modes 唯一托管），用于修复论文模式下 GSAA 关键算子被全局 PAPER 档误关导致的复现偏弱。
% - v34 2026-02-10: section_43 将 SECTION43_PAPER_GSAA_ENSURE_OPS 默认改回 false（保留手动开关），避免 GSAA 过强化导致偏离论文目标容差与时间顺序硬门槛。
% - v35 2026-02-10: section_43 新增 GSAA 全程领先硬门槛开关（SECTION43_DOMINANCE_HARD_ENABLE/SECTION43_DOMINANCE_MIN_RATIO），并纳入 run_modes 唯一声明/同步/恢复链路。
% - v36 2026-02-10: 按“可回退的一次尝试”启用 section_43 全程领先硬门槛（dominance=1.00），并全面补充 43/531/532/533/541/542 开关注释（含取值与是否影响论文参数）。
% - v37 2026-02-10: section_43 默认切换为纯开源算法对比（SECTION43_USE_PAPER_TEST=false，GSAA=one_run_gsaa），用于公平比较 GSAA/GA/SA（GSAA 在部分文献中也写作 GASA）。
% - v38 2026-02-10: section_43 新增分轨与口径开关（TRACK_MODE/ALGO_SUITE/POST_RECOVERY_POLICY/RESULT_SOURCE_FOR_TABLE/DOMINANCE_MODE/DOMINANCE_CURVE_POLICY）。
% - v39 2026-02-11: 修复 v38 六个开关未进入 apply/capture/restore 链路导致 enforce_run_modes_env “未声明读取”；补齐 SECTION43_* 全链路同步。
% - v40 2026-02-11: 修复 section_43 开关面板漏定义分轨口径变量（TRACK_MODE/ALGO_SUITE/POST_RECOVERY_POLICY/RESULT_SOURCE_FOR_TABLE/DOMINANCE_MODE/DOMINANCE_CURVE_POLICY）导致 run_modes 启动告警。
% - v41 2026-02-11: section_43 默认值切回论文复现基线（USE_PAPER_TEST=true、ALGO_SUITE=paper_suite、FIGURE_REF_SOURCE=pdf_extract、FIGURE_HARD_GATE_ENABLE=true、DOMINANCE_HARD_ENABLE=false、DOMINANCE_MIN_RATIO=0.95）。
% - v42 2026-02-11: run_modes 入口新增自动 clear all + clc，降低调试残留变量/终端噪声对复现实验的干扰。
% - v43 2026-02-11: section_43 默认开启 SECTION43_PAPER_GSAA_ENSURE_OPS（仅修复 GSAA 关键算子被误关，不改论文参数）。
% - v48 2026-02-11: section_43 paired_run 选run默认策略升级为 min_shape_score_nonflat，优先规避“整段平线”候选（仅展示口径选择，不改求解参数）。
% - v44 2026-02-11: section_43 默认关闭 SECTION43_PAPER_GSAA_ENSURE_OPS（回归论文复现基线，避免 GSAA 过强化导致目标容差/时间顺序失败）。
% - v45 2026-02-11: section_43 在 repro_baseline 默认关闭 FIGURE_HARD_GATE（PDF锚点误差改诊断），避免图锚点3%门槛阻断真实求解基线。
% - v46 2026-02-11: section_43 新增 BASELINE 预设锁（SECTION43_BASELINE_PRESET）；启用后强制回写已验证可用基线开关组合，防止手工改动导致复现漂移。
% - v47 2026-02-11: section_43 新增曲线口径统一开关 SECTION43_CURVE_POLICY_UNIFIED（默认统一，可切换为不统一）。

% run_modes - 本工程唯一运行入口（开关控制文件）
% 说明：
% - 新增 section 必须“接入 run_modes”：模板生成 -> registry 注册 -> 同步更新本文件 SUPPORTED_SECTIONS（否则将报错）。
% - 强烈建议通过 modules/experiments/create_section_from_template.m 创建新 section：
%   它会自动：生成文件 -> 注册 registry -> 更新本文件 SUPPORTED_SECTIONS，避免遗漏。
% - 禁止新建“独立脚本”绕过本文件直接跑（会导致参数/输出/审计/缓存口径漂移，也会绕过规范检查器）。
%   所有运行都应从 run_modes 进入；run_modes 内部会调用统一执行器 run_all，并强制 section 规范校验。

% 每次入口先清理工作区与命令窗，避免上次调试残留污染本次 mode/section 运行。
clear all;
clc;

% ===================== RUN MODE 开关面板 =====================
% 新增 section 时必须同步维护此列表（否则 enforce_run_modes_sync 会报错）
SUPPORTED_SECTIONS = {'43','531','532','533','541','542'};  % 43: 论文4.3节算法检验

RUN_MODE = '542';          % 单个运行：'531'/'532'/'533'/...
RUN_MODE_MULTI = {'43','531','532','533','541','542'};      % 批量运行：例如 {'531','532','533'}；非空则忽略 RUN_MODE
RUN_TAG = 'default';       % 输出/审计模式标签（写入文件名与 audit.txt）
MODE_LABEL = 'PAPER';   % 默认 ENHANCED（允许 PAPER 但不推荐用于提升解质量）
% RUN_PROFILE 说明（不改任何参数，仅算法流程增强；按激进强度从低到高排序）：
% - 下列所有模式 **均不修改任何参数值**（包括 NP/MaxGen/NRun/Pe/alpha 及其他所有硬参数）
% - 若未来新增允许改参数，必须在此处逐条标注“改动项”，否则不允许合入
% - BASELINE        : 参数改动=无；不做额外流程增强，严格使用默认实现（论文严格复现）。
% - FAST            : 参数改动=无；仅用于流程自检，算法流程与 BASELINE 相同。
% - ALGO_INTENSIFY  : 参数改动=无；每代额外执行一次精英局部搜索（强强化）。
% - ALGO_DIVERSIFY  : 参数改动=无；停滞时追加扰动变异 + 移民（强探索）。
% - ALGO_HYBRID     : 参数改动=无；同时启用强化 + 多样化（最激进）。
RUN_PROFILE = 'BASELINE'; %BASELINE | FAST | ALGO_INTENSIFY | ALGO_DIVERSIFY | ALGO_HYBRID
FORCE_RECOMPUTE = false;   % true => 仍审计缓存但强制忽略并重算
% ========================================================================

% ===================== SECTION 43 开关面板 =====================
% 论文 4.3 节算法检验：GSAA vs GA vs SA（图4.8 + 表4.3）
% 约束：
% - 以下开关均为“流程/审计/输出”控制，不改论文参数（NP/MaxGen/Pc/Pm/T0/Tmin/alpha 等）。
% - 本次为“可回退的一次尝试”：启用全程领先硬门槛，失败则按备份回退。
SECTION43_VERBOSE = true;        % [bool] 控制台详细输出（建议 true；仅日志）
SECTION43_KEEP_FIGURES = true;   % [bool] 运行后是否保留图窗（仅显示行为）
SECTION43_PRINT_TABLES = true;   % [bool] 终端是否打印表4.3（仅显示行为）
SECTION43_BASELINE_PRESET = true; % [bool] 基线预设锁：true=强制使用已验证可用基线组合；false=允许手动调节下列 SECTION43_* 开关
SECTION43_USE_PAPER_TEST = true;  % [bool] true=论文算法套件；false=纯开源基础套件（GSAA=one_run_gsaa，文献中常称 GASA）
SECTION43_TRACK_MODE = 'repro_baseline';  % ['repro_baseline'|'dominance_experiment'] 4.3分轨模式（流程开关）
SECTION43_ALGO_SUITE = 'paper_suite';  % ['paper_suite'|'opensource_suite'|'opensource_strict'] 算法套件映射
SECTION43_POST_RECOVERY_POLICY = 'diag_only';  % ['off'|'diag_only'|'apply_to_all'] 后置恢复策略（默认仅诊断不覆写）
SECTION43_RESULT_SOURCE_FOR_TABLE = 'raw';  % ['raw'|'recovered'] 表4.3主结果口径（默认 raw）
SECTION43_DOMINANCE_MODE = 'diag';  % ['off'|'diag'|'hard'] GSAA全程领先判定模式
SECTION43_DOMINANCE_CURVE_POLICY = 'paired_run';  % ['paired_run'] 全程领先判定曲线口径（仅同run）
SECTION43_CURVE_POLICY_UNIFIED = true;  % [bool] 曲线口径统一开关：true=展示与领先判定统一为 paired_run；false=允许两者分离
SECTION43_REPRO_MAX_BATCHES = 20;                % [int>=1] 最大批次数（本次尝试提高到20；仅调度，不改算法参数）
SECTION43_REPRO_EARLY_STOP_ON_PASS = true;       % [bool] true=命中首个图表双PASS即停（仅调度）
SECTION43_REPRO_GATE_POLICY = 'two_stage';       % ['two_stage'|'single_stage'] 先表后图/每批图检（仅流程）
SECTION43_REPRO_PICK_POLICY = 'closest_after_all_batches'; % ['closest_after_all_batches'] 无PASS时选最接近批次（仅选批）
SECTION43_COST_TOL_PCT = 0.02;                   % [0~1] 论文目标值容差（仅审计阈值）
SECTION43_TIME_BENCH_REPEATS = 3;                % [int>=1] 基准测时重复次数（仅审计）
SECTION43_CURVE_PLATEAU_PROFILE = 'paper_approx'; % ['paper_approx'|'strict'|'loose'] 平台诊断模板（仅审计）
SECTION43_EXPORT_RICH_TABLE = false;             % [bool] 附加富格式表导出（默认关；非核心）
SECTION43_VERIFY_ENABLE = false;                 % [bool] 重型产物校验开关（默认关；不影响主结果）
SECTION43_REF_PDF = '21级邱莹莹大论文.pdf';        % [string] 图4.8参考PDF（仅 pdf_extract 模式使用）
SECTION43_FIGURE_REF_SOURCE = 'pdf_extract';            % ['none'|'pdf_extract'] 图参考来源（none=不提取）
SECTION43_REF_CACHE_ENABLE = true;               % [bool] 参考曲线缓存开关（仅效率）
SECTION43_REF_CACHE_FORCE_REFRESH = false;       % [bool] true=强制刷新参考缓存（仅效率）
SECTION43_CURVE_SELECTION_POLICY = 'best_run';   % ['best_run'|'paired_run'] 曲线口径（best_run=与MIN口径一致）
SECTION43_CURVE_PAIRED_RUN_PICK = 'min_shape_score_nonflat'; % ['min_shape_score'|'min_shape_score_nonflat'] paired_run选run策略（nonflat优先规避平线）
SECTION43_FIGURE_HARD_GATE_ENABLE = false;       % [bool] 图参考硬门槛（baseline默认关，仅做诊断；dominance_experiment 可显式开启）
SECTION43_PAPER_GSAA_ENSURE_OPS = false;         % [bool] 仅GSAA算子保真修补（默认关；保持论文复现基线，必要时再显式开启）
SECTION43_PARALLEL_ENABLE = true;                % [bool] NRun并行（仅执行效率，不改算法语义）
SECTION43_PARALLEL_WORKERS = 0;                  % [int] 0=自动；>0=上限（并行运行，起加速作用）
SECTION43_PARALLEL_LOG_LEVEL = 'detailed';       % ['none'|'summary'|'detailed'] 并行顺序日志级别
SECTION43_DOMINANCE_HARD_ENABLE = false;         % [bool] 全程领先硬门槛：true=未达阈值直接不PASS（仅审计门槛）
SECTION43_DOMINANCE_MIN_RATIO = 0.95;            % [0~1] 全程领先阈值（严格口径）：GSAA代际成本需严格低于GA/SA
% ==========================================================================================================

% ===================== SECTION 531 开关面板 =====================
% 5.3.1 基础配送优化（混合车队 2CV+2EV）
% 说明：以下开关仅影响日志/并行/展示，不改论文参数真源。
SECTION531_VERBOSE = true;       % [bool] 终端详细日志
SECTION531_KEEP_FIGURES = true;  % [bool] 是否保留图窗
SECTION531_PRINT_TABLES = true;  % [bool] 是否打印表格
SECTION531_PARALLEL_ENABLE = true;   % [bool] NRun并行开关（仅效率）
SECTION531_PARALLEL_WORKERS = 0;     % [int] worker 数：0=自动
SECTION531_PARALLEL_LOG_LEVEL = 'detailed'; % ['none'|'summary'|'detailed'] 并行顺序日志
% ==========================================================================================================

% ===================== SECTION 532 开关面板 =====================
% 5.3.2 对比实验（混合车队 vs 自定义车队）
% 说明：自定义车队配置属于实验分组开关，不改变论文模型参数真源。
SECTION532_CUSTOM_NCV = 3;               % [int>=0] 自定义案例 CV 数量（仅分组）
SECTION532_CUSTOM_NEV = 0;               % [int>=0] 自定义案例 EV 数量（仅分组）
SECTION532_CUSTOM_CASE_TAG = 'CV_ONLY';  % [string] 自定义案例标签（影响输出命名）
SECTION532_VERBOSE = true;       % [bool] 终端详细日志
SECTION532_KEEP_FIGURES = true;  % [bool] 是否保留图窗
SECTION532_PRINT_TABLES = true;  % [bool] 是否打印表格
SECTION532_PARALLEL_ENABLE = true;   % [bool] NRun并行开关（仅效率）
SECTION532_PARALLEL_WORKERS = 0;     % [int] worker 数：0=自动
SECTION532_PARALLEL_LOG_LEVEL = 'detailed'; % ['none'|'summary'|'detailed'] 并行顺序日志
% ==========================================================================================================
 
% ===================== SECTION 533 开关面板 =====================
% 5.3.3 敏感性分析（电池容量 B0 / 充电速率 rg）
% 说明：以下开关仅控制敏感性实验流程与输出风格，不改论文固定参数。
SECTION533_INC_PCT_VEC = [0 20 40 60 80 100];  % [row vector] 敏感性点位（论文口径推荐）
SECTION533_PAPER_INDEPENDENT = true;            % [bool] true=各点独立求解；false=可跨点 warm-start
SECTION533_PAPER_LINE_MODE = 'cummin';          % ['cummin'|'pointBest'] 曲线呈现口径
SECTION533_WARMSTART_KICK = 2;                  % [int>=0] 热启动扰动强度（仅 independent=false）
SECTION533_VERBOSE = true;       % [bool] 终端详细日志
SECTION533_KEEP_FIGURES = true;  % [bool] 是否保留图窗
SECTION533_PRINT_TABLES = true;  % [bool] 是否打印表格
SECTION533_PARALLEL_ENABLE = true;   % [bool] 点内 NRun 并行开关（仅效率）
SECTION533_PARALLEL_WORKERS = 0;     % [int] worker 数：0=自动
SECTION533_PARALLEL_LOG_LEVEL = 'detailed'; % ['none'|'summary'|'detailed'] 并行顺序日志
% ==========================================================================================================

% ===================== SECTION 541 开关面板 =====================
% 硬性规定（以后新增 section 也必须遵守）：
% - run_modes.m 是工程唯一“开关控制文件”，所有 section 的用户开关必须在这里集中维护并写清中文旁注。
% - 禁止把用户开关散落在 section 源码/脚本里、或要求用户手动 setenv；如需环境变量传参，本文件必须负责 setenv+恢复。
%
% 541 两种模式：
% - paper_repro（默认）：固定论文口径（q=500kg、T=30min、窗口缺失则默认 08:00-10:00、q 累计=positive_only、固定 seed、warm-start）
% - generalize（自定义模式）：更宽松（允许用户改 q/T/seed/q 累计口径/窗口覆盖/候选车队上界；仍需有限上界防止无限加车）
%
% 注意：
% - SECTION541_* 只在“本次将运行 section_541”时同步到环境变量；run_modes 结束后自动恢复旧值，避免影响其它 section。
SECTION541_MODE = 'paper_repro';      % paper_repro | generalize
SECTION541_DATA_POLICY = 'prefer_data'; % prefer_data(默认：使用论文示例 xlsx；不再默认 internal) | prefer_internal(仅显式指定才允许内置数据)
SECTION541_PAPER_STATIC_XLSX = '论文示例静态节点数据.xlsx';   % 论文静态表（表4.1）xlsx 文件名（位于 data/）
SECTION541_PAPER_EVENTS_XLSX = '论文示例动态需求数据.xlsx';   % 论文动态表（表5.6）xlsx 文件名（位于 data/）
SECTION541_QKG  = 500;               % 仅 generalize：定量触发阈值 q（kg）
SECTION541_TMIN = 30;                % 仅 generalize：定时触发周期 T（min）
SECTION541_SEED = 1;                 % 仅 generalize：整数或 'shuffle'（paper_repro 固定 seed）
SECTION541_QACCUM = 'positive_only';  % 仅 generalize：positive_only(论文示例默认) | net
SECTION541_WINDOW = '';              % 仅 generalize：窗口覆盖，例如 '08:00-10:00' 或 '480-600'；空则由文件/事件推断
SECTION541_MAX_EXTRA_EV = 4;         % 仅 generalize：额外 EV 上界（有限枚举，防止无限加车）
SECTION541_MAX_EXTRA_CV = 2;         % 仅 generalize：额外 CV 上界（有限枚举，防止无限加车）
SECTION541_CONSOLE_VERBOSE = true;   % 控制台详细输出（候选车队/压力审计等）：true/false（建议 paper_repro 开）
SECTION541_KEEP_FIGURES = true;      % 保持图窗不自动关闭（便于编辑/查看）；true/false
SECTION541_PRINT_TABLES = true;      % 在终端打印表格内容（事件/初始/更新方案/成本）；true/false
SECTION541_PARALLEL_ENABLE = true;   % 是否并行执行 GSAA 的 NRun 独立运行（仅加速，不改参数/语义）
SECTION541_PARALLEL_WORKERS = 0;     % 并行 worker 数：0=自动；>0=指定上限
SECTION541_PARALLEL_LOG_LEVEL = 'detailed'; % 并行顺序日志级别：none | summary | detailed
SECTION541_VALIDATE_ENABLE = true;   % 是否启用对齐/产物完整性报告（仅报告不改结果）
SECTION541_WARMSTART = true;         % warm-start 热启动开关（将上一轮未服务序列映射为本轮初始分配）
SECTION541_CACHE_ENABLE = false;     % 缓存开关（默认关闭；若启用需以 build_signature 隔离）
SECTION541_DEFAULT_RECV_WINDOW = '08:00-10:00';  % paper_repro 默认接收窗口（仅当事件表未显式给窗口）
% 说明：section_541 的 NRun 与 5.3.x 统一使用 ctx.SolverCfg.NRun（不提供独立 SECTION541_* 覆盖）
% ==========================================================================================================

% ===================== SECTION 542 开关面板 =====================
% 5.4.2 对比实验：
% - 考虑动态优化：直接复用 section_541 的最终更新结果（同一组论文数据与参数真源）
% - 不考虑动态优化：固定“初始 4 条路线”不重排，仅允许派新车覆盖新增需求，再用 GSAA 求剩余部分
%
% 说明：
% - 下列开关仅影响 section_542 的“对比实验策略/输出表现”，不改变论文规定死的模型参数与 SolverCfg 参数。
% - 环境变量由本文件负责 setenv + 运行后恢复，避免跨 section 污染。
SECTION542_BASELINE_MAX_EXTRAEV = 2;   % [int>=0] baseline 额外 EV 上界（仅策略，不改论文参数）
SECTION542_BASELINE_MAX_EXTRACV = 0;   % [int>=0] baseline 额外 CV 上界（仅策略）
SECTION542_BASE_NCV = 2;              % [int>=0] 基础 CV 数量（初始方案来源）
SECTION542_BASE_NEV = 2;              % [int>=0] 基础 EV 数量（初始方案来源）
SECTION542_BASELINE_MODE = 'paper_repro';  % ['paper_repro'|'generalize'] baseline 运行口径
SECTION542_CONSOLE_VERBOSE = false;   % [bool] 终端详细日志
SECTION542_KEEP_FIGURES = false;      % [bool] 是否保留图窗
SECTION542_PRINT_TABLES = false;      % [bool] 是否打印表格
SECTION542_PARALLEL_ENABLE = true;    % [bool] baseline 子求解 NRun 并行（仅效率）
SECTION542_PARALLEL_WORKERS = 0;      % [int] worker 数：0=自动
SECTION542_PARALLEL_LOG_LEVEL = 'detailed'; % ['none'|'summary'|'detailed'] 并行顺序日志
% ==========================================================================================================

fprintf('[入口] 唯一入口 run_modes.m（已禁用 main_mod/run_main_modular）\n');

rootDir = fileparts(mfilename('fullpath'));
modulesDir = fullfile(rootDir, 'modules');
if ~exist(modulesDir, 'dir')
    error('run_modes:missingModules', 'modules/ not found under: %s', rootDir);
end

% Ensure all modules are on path
addpath(modulesDir);  % to reach init_modules.m
init_modules();

cfg = struct();%配置结构体
cfg.supportedSections = SUPPORTED_SECTIONS;%支持的 section 列表
cfg.runMode = RUN_MODE;%单个运行模式
cfg.runModeMulti = RUN_MODE_MULTI;%批量运行模式
cfg.runTag = RUN_TAG;%输出/审计模式标签
cfg.modeLabel = MODE_LABEL;%模式标签
cfg.runProfile = RUN_PROFILE;%运行模式
cfg.forceRecompute = FORCE_RECOMPUTE;%强制重新计算
cfg.runModesPath = mfilename('fullpath');%运行模式路径

% ===== 将 section_43 开关同步到环境变量（仅当本次将运行 43）；并在结束后恢复 =====
try
    if run_modes_will_run_section_('43', RUN_MODE, RUN_MODE_MULTI)
        if SECTION43_BASELINE_PRESET
            % 已验证可用基线版（只改流程开关，不改论文参数）
            SECTION43_USE_PAPER_TEST = true;
            SECTION43_TRACK_MODE = 'repro_baseline';
            SECTION43_ALGO_SUITE = 'paper_suite';
            SECTION43_POST_RECOVERY_POLICY = 'diag_only';
            SECTION43_RESULT_SOURCE_FOR_TABLE = 'raw';
            SECTION43_REPRO_GATE_POLICY = 'two_stage';
            SECTION43_REPRO_EARLY_STOP_ON_PASS = true;
            SECTION43_FIGURE_HARD_GATE_ENABLE = false;
            SECTION43_PAPER_GSAA_ENSURE_OPS = false;
            SECTION43_DOMINANCE_MODE = 'diag';
            SECTION43_DOMINANCE_CURVE_POLICY = 'paired_run';
            SECTION43_CURVE_POLICY_UNIFIED = true;
            SECTION43_DOMINANCE_HARD_ENABLE = false;
            SECTION43_DOMINANCE_MIN_RATIO = 0.95;
            SECTION43_PARALLEL_ENABLE = true;
            SECTION43_PARALLEL_WORKERS = 0;
            SECTION43_PARALLEL_LOG_LEVEL = 'detailed';
            fprintf('[section_43] 已启用 BASELINE 预设锁定（SECTION43_BASELINE_PRESET=true）：强制使用可用基线组合。\n');
        end
        old43 = run_modes_capture_env_43_();
        envCleanup43 = onCleanup(@() run_modes_restore_env_43_(old43)); %#ok<NASGU>
        run_modes_apply_env_43_(SECTION43_VERBOSE, SECTION43_KEEP_FIGURES, SECTION43_PRINT_TABLES, SECTION43_USE_PAPER_TEST, ...
            SECTION43_TRACK_MODE, SECTION43_ALGO_SUITE, SECTION43_POST_RECOVERY_POLICY, SECTION43_RESULT_SOURCE_FOR_TABLE, SECTION43_DOMINANCE_MODE, SECTION43_DOMINANCE_CURVE_POLICY, SECTION43_CURVE_POLICY_UNIFIED, ...
            SECTION43_REPRO_MAX_BATCHES, SECTION43_REPRO_EARLY_STOP_ON_PASS, SECTION43_REPRO_GATE_POLICY, SECTION43_REPRO_PICK_POLICY, SECTION43_COST_TOL_PCT, SECTION43_TIME_BENCH_REPEATS, SECTION43_CURVE_PLATEAU_PROFILE, ...
            SECTION43_EXPORT_RICH_TABLE, SECTION43_VERIFY_ENABLE, SECTION43_REF_PDF, SECTION43_FIGURE_REF_SOURCE, ...
            SECTION43_REF_CACHE_ENABLE, SECTION43_REF_CACHE_FORCE_REFRESH, SECTION43_CURVE_SELECTION_POLICY, ...
            SECTION43_CURVE_PAIRED_RUN_PICK, SECTION43_FIGURE_HARD_GATE_ENABLE, SECTION43_PAPER_GSAA_ENSURE_OPS, ...
            SECTION43_DOMINANCE_HARD_ENABLE, SECTION43_DOMINANCE_MIN_RATIO, ...
            SECTION43_PARALLEL_ENABLE, SECTION43_PARALLEL_WORKERS, SECTION43_PARALLEL_LOG_LEVEL);
        fprintf('[section_43] 已从 run_modes 开关面板同步 SECTION43_* 环境变量（运行后自动恢复）\n');
    end
catch ME
    warning('run_modes:section43Env', '设置/恢复 SECTION43_* 环境变量失败：%s', ME.message);
end

% ===== 将 section_531 开关同步到环境变量（仅当本次将运行 531）；并在结束后恢复 =====
try
    if run_modes_will_run_section_('531', RUN_MODE, RUN_MODE_MULTI)
        old531 = run_modes_capture_env_531_();
        envCleanup531 = onCleanup(@() run_modes_restore_env_531_(old531)); %#ok<NASGU>
        run_modes_apply_env_531_(SECTION531_VERBOSE, SECTION531_KEEP_FIGURES, SECTION531_PRINT_TABLES, ...
            SECTION531_PARALLEL_ENABLE, SECTION531_PARALLEL_WORKERS, SECTION531_PARALLEL_LOG_LEVEL);
        fprintf('[section_531] 已从 run_modes 开关面板同步 SECTION531_* 环境变量（运行后自动恢复）\n');
    end
catch ME
    warning('run_modes:section531Env', '设置/恢复 SECTION531_* 环境变量失败：%s', ME.message);
end

% ===== 将 section_532 开关同步到环境变量（仅当本次将运行 532）；并在结束后恢复 =====
try
    if run_modes_will_run_section_('532', RUN_MODE, RUN_MODE_MULTI)
        old532 = run_modes_capture_env_532_();
        envCleanup532 = onCleanup(@() run_modes_restore_env_532_(old532)); %#ok<NASGU>
        run_modes_apply_env_532_(SECTION532_CUSTOM_NCV, SECTION532_CUSTOM_NEV, SECTION532_CUSTOM_CASE_TAG, ...
            SECTION532_VERBOSE, SECTION532_KEEP_FIGURES, SECTION532_PRINT_TABLES, SECTION532_PARALLEL_ENABLE, SECTION532_PARALLEL_WORKERS, SECTION532_PARALLEL_LOG_LEVEL);
        fprintf('[section_532] 已从 run_modes 开关面板同步 SECTION532_* 环境变量（运行后自动恢复）\n');
    end
catch ME
    warning('run_modes:section532Env', '设置/恢复 SECTION532_* 环境变量失败：%s', ME.message);
end

% ===== 将 section_533 开关同步到环境变量（仅当本次将运行 533）；并在结束后恢复 =====
try
    if run_modes_will_run_section_('533', RUN_MODE, RUN_MODE_MULTI)
        old533 = run_modes_capture_env_533_();
        envCleanup533 = onCleanup(@() run_modes_restore_env_533_(old533)); %#ok<NASGU>
        run_modes_apply_env_533_(SECTION533_INC_PCT_VEC, SECTION533_PAPER_INDEPENDENT, SECTION533_PAPER_LINE_MODE, SECTION533_WARMSTART_KICK, ...
            SECTION533_VERBOSE, SECTION533_KEEP_FIGURES, SECTION533_PRINT_TABLES, SECTION533_PARALLEL_ENABLE, SECTION533_PARALLEL_WORKERS, SECTION533_PARALLEL_LOG_LEVEL);
        fprintf('[section_533] 已从 run_modes 开关面板同步 SECTION533_* 环境变量（运行后自动恢复）\n');
    end
catch ME
    warning('run_modes:section533Env', '设置/恢复 SECTION533_* 环境变量失败：%s', ME.message);
end

% ===== 将 section_541 开关同步到环境变量（仅当本次将运行 541）；并在结束后恢复 =====
envCleanup = [];%环境清理
try
    if run_modes_will_run_section_541_(RUN_MODE, RUN_MODE_MULTI)
        old = run_modes_capture_env_541_();%541 环境变量捕获
        envCleanup = onCleanup(@() run_modes_restore_env_541_(old));%541 环境变量恢复
        run_modes_apply_env_541_(SECTION541_MODE, SECTION541_DATA_POLICY, SECTION541_QKG, SECTION541_TMIN, SECTION541_SEED, SECTION541_QACCUM, SECTION541_WINDOW, SECTION541_MAX_EXTRA_EV, SECTION541_MAX_EXTRA_CV, ...
            SECTION541_CONSOLE_VERBOSE, SECTION541_PAPER_STATIC_XLSX, SECTION541_PAPER_EVENTS_XLSX, SECTION541_KEEP_FIGURES, SECTION541_PRINT_TABLES, ...
            SECTION541_PARALLEL_ENABLE, SECTION541_PARALLEL_WORKERS, SECTION541_PARALLEL_LOG_LEVEL, SECTION541_VALIDATE_ENABLE, SECTION541_WARMSTART, SECTION541_CACHE_ENABLE, SECTION541_DEFAULT_RECV_WINDOW);%541 环境变量应用
        fprintf('[section_541] 已从 run_modes 开关面板同步 SECTION541_* 环境变量（运行后自动恢复）\n');
    end
catch ME
    warning('run_modes:section541Env', '设置/恢复 SECTION541_* 环境变量失败：%s', ME.message);
end

try
    if run_modes_will_run_section_542_(cfg.runMode, cfg.runModeMulti)
        old542 = run_modes_capture_env_542_();
        envCleanup2 = onCleanup(@() run_modes_restore_env_542_(old542)); %542 环境变量恢复
        run_modes_apply_env_542_(SECTION542_BASELINE_MAX_EXTRAEV, SECTION542_BASELINE_MAX_EXTRACV, SECTION542_BASE_NCV, SECTION542_BASE_NEV, SECTION542_BASELINE_MODE, ...
            SECTION542_CONSOLE_VERBOSE, SECTION542_KEEP_FIGURES, SECTION542_PRINT_TABLES, SECTION542_PARALLEL_ENABLE, SECTION542_PARALLEL_WORKERS, SECTION542_PARALLEL_LOG_LEVEL);%542 环境变量应用
        fprintf('[section_542] 已从 run_modes 开关面板同步 SECTION542_* 环境变量（运行后自动恢复）\n');
    end
catch ME
    warning('run_modes:section542Env', '设置/恢复 SECTION542_* 环境变量失败：%s', ME.message);
end

run_modes_execute(cfg);

% script local helpers（MATLAB 支持脚本尾部 local functions）

% 通用：判断是否将运行指定 section
function tf = run_modes_will_run_section_(sectionId, runMode, runModeMulti)
tf = false;
try
    if nargin >= 3 && ~isempty(runModeMulti)
        lst = runModeMulti;
    else
        lst = {runMode};
    end
    s = lower(strtrim(string(lst)));
    s = replace(s, "section_", "");
    tf = any(s == string(sectionId));
catch
    tf = false;
end
end

% ===== SECTION 43 环境变量辅助函数 =====
function old = run_modes_capture_env_43_()
old = struct();
old.VERBOSE = getenv('SECTION43_VERBOSE');
old.KEEP_FIGURES = getenv('SECTION43_KEEP_FIGURES');
old.PRINT_TABLES = getenv('SECTION43_PRINT_TABLES');
old.USE_PAPER_TEST = getenv('SECTION43_USE_PAPER_TEST');
old.TRACK_MODE = getenv('SECTION43_TRACK_MODE');
old.ALGO_SUITE = getenv('SECTION43_ALGO_SUITE');
old.POST_RECOVERY_POLICY = getenv('SECTION43_POST_RECOVERY_POLICY');
old.RESULT_SOURCE_FOR_TABLE = getenv('SECTION43_RESULT_SOURCE_FOR_TABLE');
old.DOMINANCE_MODE = getenv('SECTION43_DOMINANCE_MODE');
old.DOMINANCE_CURVE_POLICY = getenv('SECTION43_DOMINANCE_CURVE_POLICY');
old.CURVE_POLICY_UNIFIED = getenv('SECTION43_CURVE_POLICY_UNIFIED');
old.REPRO_MAX_BATCHES = getenv('SECTION43_REPRO_MAX_BATCHES');
old.REPRO_EARLY_STOP_ON_PASS = getenv('SECTION43_REPRO_EARLY_STOP_ON_PASS');
old.REPRO_GATE_POLICY = getenv('SECTION43_REPRO_GATE_POLICY');
old.REPRO_PICK_POLICY = getenv('SECTION43_REPRO_PICK_POLICY');
old.COST_TOL_PCT = getenv('SECTION43_COST_TOL_PCT');
old.TIME_BENCH_REPEATS = getenv('SECTION43_TIME_BENCH_REPEATS');
old.CURVE_PLATEAU_PROFILE = getenv('SECTION43_CURVE_PLATEAU_PROFILE');
old.EXPORT_RICH_TABLE = getenv('SECTION43_EXPORT_RICH_TABLE');
old.VERIFY_ENABLE = getenv('SECTION43_VERIFY_ENABLE');
old.REF_PDF = getenv('SECTION43_REF_PDF');
old.FIGURE_REF_SOURCE = getenv('SECTION43_FIGURE_REF_SOURCE');
old.REF_CACHE_ENABLE = getenv('SECTION43_REF_CACHE_ENABLE');
old.REF_CACHE_FORCE_REFRESH = getenv('SECTION43_REF_CACHE_FORCE_REFRESH');
old.CURVE_SELECTION_POLICY = getenv('SECTION43_CURVE_SELECTION_POLICY');
old.CURVE_PAIRED_RUN_PICK = getenv('SECTION43_CURVE_PAIRED_RUN_PICK');
old.FIGURE_HARD_GATE_ENABLE = getenv('SECTION43_FIGURE_HARD_GATE_ENABLE');
old.PAPER_GSAA_ENSURE_OPS = getenv('SECTION43_PAPER_GSAA_ENSURE_OPS');
old.DOMINANCE_HARD_ENABLE = getenv('SECTION43_DOMINANCE_HARD_ENABLE');
old.DOMINANCE_MIN_RATIO = getenv('SECTION43_DOMINANCE_MIN_RATIO');
old.PARALLEL_ENABLE = getenv('SECTION43_PARALLEL_ENABLE');
old.PARALLEL_WORKERS = getenv('SECTION43_PARALLEL_WORKERS');
old.PARALLEL_LOG_LEVEL = getenv('SECTION43_PARALLEL_LOG_LEVEL');
end

function run_modes_apply_env_43_(verbose, keepFigures, printTables, usePaperTest, trackMode, algoSuite, postRecoveryPolicy, resultSourceForTable, dominanceMode, dominanceCurvePolicy, curvePolicyUnified, reproMaxBatches, reproEarlyStopOnPass, reproGatePolicy, reproPickPolicy, costTolPct, timeBenchRepeats, curvePlateauProfile, exportRichTable, verifyEnable, refPdf, figureRefSource, refCacheEnable, refCacheForceRefresh, curveSelectionPolicy, curvePairedRunPick, figureHardGateEnable, paperGsaaEnsureOps, dominanceHardEnable, dominanceMinRatio, parallelEnable, parallelWorkers, parallelLogLevel)
setenv('SECTION43_VERBOSE', char(string(verbose)));
setenv('SECTION43_KEEP_FIGURES', char(string(keepFigures)));
setenv('SECTION43_PRINT_TABLES', char(string(printTables)));
setenv('SECTION43_USE_PAPER_TEST', char(string(usePaperTest)));
setenv('SECTION43_TRACK_MODE', char(string(trackMode)));
setenv('SECTION43_ALGO_SUITE', char(string(algoSuite)));
setenv('SECTION43_POST_RECOVERY_POLICY', char(string(postRecoveryPolicy)));
setenv('SECTION43_RESULT_SOURCE_FOR_TABLE', char(string(resultSourceForTable)));
setenv('SECTION43_DOMINANCE_MODE', char(string(dominanceMode)));
setenv('SECTION43_DOMINANCE_CURVE_POLICY', char(string(dominanceCurvePolicy)));
setenv('SECTION43_CURVE_POLICY_UNIFIED', char(string(curvePolicyUnified)));
setenv('SECTION43_REPRO_MAX_BATCHES', char(string(reproMaxBatches)));
setenv('SECTION43_REPRO_EARLY_STOP_ON_PASS', char(string(reproEarlyStopOnPass)));
setenv('SECTION43_REPRO_GATE_POLICY', char(string(reproGatePolicy)));
setenv('SECTION43_REPRO_PICK_POLICY', char(string(reproPickPolicy)));
setenv('SECTION43_COST_TOL_PCT', char(string(costTolPct)));
setenv('SECTION43_TIME_BENCH_REPEATS', char(string(timeBenchRepeats)));
setenv('SECTION43_CURVE_PLATEAU_PROFILE', char(string(curvePlateauProfile)));
setenv('SECTION43_EXPORT_RICH_TABLE', char(string(exportRichTable)));
setenv('SECTION43_VERIFY_ENABLE', char(string(verifyEnable)));
setenv('SECTION43_REF_PDF', char(string(refPdf)));
setenv('SECTION43_FIGURE_REF_SOURCE', char(string(figureRefSource)));
setenv('SECTION43_REF_CACHE_ENABLE', char(string(refCacheEnable)));
setenv('SECTION43_REF_CACHE_FORCE_REFRESH', char(string(refCacheForceRefresh)));
setenv('SECTION43_CURVE_SELECTION_POLICY', char(string(curveSelectionPolicy)));
setenv('SECTION43_CURVE_PAIRED_RUN_PICK', char(string(curvePairedRunPick)));
setenv('SECTION43_FIGURE_HARD_GATE_ENABLE', char(string(figureHardGateEnable)));
setenv('SECTION43_PAPER_GSAA_ENSURE_OPS', char(string(paperGsaaEnsureOps)));
setenv('SECTION43_DOMINANCE_HARD_ENABLE', char(string(dominanceHardEnable)));
setenv('SECTION43_DOMINANCE_MIN_RATIO', char(string(dominanceMinRatio)));
setenv('SECTION43_PARALLEL_ENABLE', char(string(parallelEnable)));
setenv('SECTION43_PARALLEL_WORKERS', char(string(parallelWorkers)));
setenv('SECTION43_PARALLEL_LOG_LEVEL', char(string(parallelLogLevel)));
end

function run_modes_restore_env_43_(old)
try setenv('SECTION43_VERBOSE', old.VERBOSE); catch, end
try setenv('SECTION43_KEEP_FIGURES', old.KEEP_FIGURES); catch, end
try setenv('SECTION43_PRINT_TABLES', old.PRINT_TABLES); catch, end
try setenv('SECTION43_USE_PAPER_TEST', old.USE_PAPER_TEST); catch, end
try setenv('SECTION43_TRACK_MODE', old.TRACK_MODE); catch, end
try setenv('SECTION43_ALGO_SUITE', old.ALGO_SUITE); catch, end
try setenv('SECTION43_POST_RECOVERY_POLICY', old.POST_RECOVERY_POLICY); catch, end
try setenv('SECTION43_RESULT_SOURCE_FOR_TABLE', old.RESULT_SOURCE_FOR_TABLE); catch, end
try setenv('SECTION43_DOMINANCE_MODE', old.DOMINANCE_MODE); catch, end
try setenv('SECTION43_DOMINANCE_CURVE_POLICY', old.DOMINANCE_CURVE_POLICY); catch, end
try setenv('SECTION43_CURVE_POLICY_UNIFIED', old.CURVE_POLICY_UNIFIED); catch, end
try setenv('SECTION43_REPRO_MAX_BATCHES', old.REPRO_MAX_BATCHES); catch, end
try setenv('SECTION43_REPRO_EARLY_STOP_ON_PASS', old.REPRO_EARLY_STOP_ON_PASS); catch, end
try setenv('SECTION43_REPRO_GATE_POLICY', old.REPRO_GATE_POLICY); catch, end
try setenv('SECTION43_REPRO_PICK_POLICY', old.REPRO_PICK_POLICY); catch, end
try setenv('SECTION43_COST_TOL_PCT', old.COST_TOL_PCT); catch, end
try setenv('SECTION43_TIME_BENCH_REPEATS', old.TIME_BENCH_REPEATS); catch, end
try setenv('SECTION43_CURVE_PLATEAU_PROFILE', old.CURVE_PLATEAU_PROFILE); catch, end
try setenv('SECTION43_EXPORT_RICH_TABLE', old.EXPORT_RICH_TABLE); catch, end
try setenv('SECTION43_VERIFY_ENABLE', old.VERIFY_ENABLE); catch, end
try setenv('SECTION43_REF_PDF', old.REF_PDF); catch, end
try setenv('SECTION43_FIGURE_REF_SOURCE', old.FIGURE_REF_SOURCE); catch, end
try setenv('SECTION43_REF_CACHE_ENABLE', old.REF_CACHE_ENABLE); catch, end
try setenv('SECTION43_REF_CACHE_FORCE_REFRESH', old.REF_CACHE_FORCE_REFRESH); catch, end
try setenv('SECTION43_CURVE_SELECTION_POLICY', old.CURVE_SELECTION_POLICY); catch, end
try setenv('SECTION43_CURVE_PAIRED_RUN_PICK', old.CURVE_PAIRED_RUN_PICK); catch, end
try setenv('SECTION43_FIGURE_HARD_GATE_ENABLE', old.FIGURE_HARD_GATE_ENABLE); catch, end
try setenv('SECTION43_PAPER_GSAA_ENSURE_OPS', old.PAPER_GSAA_ENSURE_OPS); catch, end
try setenv('SECTION43_DOMINANCE_HARD_ENABLE', old.DOMINANCE_HARD_ENABLE); catch, end
try setenv('SECTION43_DOMINANCE_MIN_RATIO', old.DOMINANCE_MIN_RATIO); catch, end
try setenv('SECTION43_PARALLEL_ENABLE', old.PARALLEL_ENABLE); catch, end
try setenv('SECTION43_PARALLEL_WORKERS', old.PARALLEL_WORKERS); catch, end
try setenv('SECTION43_PARALLEL_LOG_LEVEL', old.PARALLEL_LOG_LEVEL); catch, end
end

% ===== SECTION 531 环境变量辅助函数 =====
function old = run_modes_capture_env_531_()
old = struct();
old.VERBOSE = getenv('SECTION531_VERBOSE');
old.KEEP_FIGURES = getenv('SECTION531_KEEP_FIGURES');
old.PRINT_TABLES = getenv('SECTION531_PRINT_TABLES');
old.PARALLEL_ENABLE = getenv('SECTION531_PARALLEL_ENABLE');
old.PARALLEL_WORKERS = getenv('SECTION531_PARALLEL_WORKERS');
old.PARALLEL_LOG_LEVEL = getenv('SECTION531_PARALLEL_LOG_LEVEL');
end

function run_modes_apply_env_531_(verbose, keepFigures, printTables, parallelEnable, parallelWorkers, parallelLogLevel)
setenv('SECTION531_VERBOSE', char(string(verbose)));
setenv('SECTION531_KEEP_FIGURES', char(string(keepFigures)));
setenv('SECTION531_PRINT_TABLES', char(string(printTables)));
setenv('SECTION531_PARALLEL_ENABLE', char(string(parallelEnable)));
setenv('SECTION531_PARALLEL_WORKERS', char(string(parallelWorkers)));
setenv('SECTION531_PARALLEL_LOG_LEVEL', char(string(parallelLogLevel)));
end

function run_modes_restore_env_531_(old)
try setenv('SECTION531_VERBOSE', old.VERBOSE); catch, end
try setenv('SECTION531_KEEP_FIGURES', old.KEEP_FIGURES); catch, end
try setenv('SECTION531_PRINT_TABLES', old.PRINT_TABLES); catch, end
try setenv('SECTION531_PARALLEL_ENABLE', old.PARALLEL_ENABLE); catch, end
try setenv('SECTION531_PARALLEL_WORKERS', old.PARALLEL_WORKERS); catch, end
try setenv('SECTION531_PARALLEL_LOG_LEVEL', old.PARALLEL_LOG_LEVEL); catch, end
end

% ===== SECTION 532 环境变量辅助函数 =====
function old = run_modes_capture_env_532_()
old = struct();
old.CUSTOM_NCV = getenv('SECTION532_CUSTOM_NCV');
old.CUSTOM_NEV = getenv('SECTION532_CUSTOM_NEV');
old.CUSTOM_CASE_TAG = getenv('SECTION532_CUSTOM_CASE_TAG');
old.VERBOSE = getenv('SECTION532_VERBOSE');
old.KEEP_FIGURES = getenv('SECTION532_KEEP_FIGURES');
old.PRINT_TABLES = getenv('SECTION532_PRINT_TABLES');
old.PARALLEL_ENABLE = getenv('SECTION532_PARALLEL_ENABLE');
old.PARALLEL_WORKERS = getenv('SECTION532_PARALLEL_WORKERS');
old.PARALLEL_LOG_LEVEL = getenv('SECTION532_PARALLEL_LOG_LEVEL');
end

function run_modes_apply_env_532_(customNcv, customNev, customCaseTag, verbose, keepFigures, printTables, parallelEnable, parallelWorkers, parallelLogLevel)
setenv('SECTION532_CUSTOM_NCV', char(string(customNcv)));
setenv('SECTION532_CUSTOM_NEV', char(string(customNev)));
setenv('SECTION532_CUSTOM_CASE_TAG', char(string(customCaseTag)));
setenv('SECTION532_VERBOSE', char(string(verbose)));
setenv('SECTION532_KEEP_FIGURES', char(string(keepFigures)));
setenv('SECTION532_PRINT_TABLES', char(string(printTables)));
setenv('SECTION532_PARALLEL_ENABLE', char(string(parallelEnable)));
setenv('SECTION532_PARALLEL_WORKERS', char(string(parallelWorkers)));
setenv('SECTION532_PARALLEL_LOG_LEVEL', char(string(parallelLogLevel)));
end

function run_modes_restore_env_532_(old)
try setenv('SECTION532_CUSTOM_NCV', old.CUSTOM_NCV); catch, end
try setenv('SECTION532_CUSTOM_NEV', old.CUSTOM_NEV); catch, end
try setenv('SECTION532_CUSTOM_CASE_TAG', old.CUSTOM_CASE_TAG); catch, end
try setenv('SECTION532_VERBOSE', old.VERBOSE); catch, end
try setenv('SECTION532_KEEP_FIGURES', old.KEEP_FIGURES); catch, end
try setenv('SECTION532_PRINT_TABLES', old.PRINT_TABLES); catch, end
try setenv('SECTION532_PARALLEL_ENABLE', old.PARALLEL_ENABLE); catch, end
try setenv('SECTION532_PARALLEL_WORKERS', old.PARALLEL_WORKERS); catch, end
try setenv('SECTION532_PARALLEL_LOG_LEVEL', old.PARALLEL_LOG_LEVEL); catch, end
end

% ===== SECTION 533 环境变量辅助函数 =====
function old = run_modes_capture_env_533_()
old = struct();
old.INC_PCT_VEC = getenv('SECTION533_INC_PCT_VEC');
old.PAPER_INDEPENDENT = getenv('SECTION533_PAPER_INDEPENDENT');
old.PAPER_LINE_MODE = getenv('SECTION533_PAPER_LINE_MODE');
old.WARMSTART_KICK = getenv('SECTION533_WARMSTART_KICK');
old.VERBOSE = getenv('SECTION533_VERBOSE');
old.KEEP_FIGURES = getenv('SECTION533_KEEP_FIGURES');
old.PRINT_TABLES = getenv('SECTION533_PRINT_TABLES');
old.PARALLEL_ENABLE = getenv('SECTION533_PARALLEL_ENABLE');
old.PARALLEL_WORKERS = getenv('SECTION533_PARALLEL_WORKERS');
old.PARALLEL_LOG_LEVEL = getenv('SECTION533_PARALLEL_LOG_LEVEL');
end

function run_modes_apply_env_533_(incPctVec, paperIndependent, paperLineMode, warmstartKick, verbose, keepFigures, printTables, parallelEnable, parallelWorkers, parallelLogLevel)
% incPctVec 是数组，需要转为字符串
if isnumeric(incPctVec)
    incPctStr = mat2str(incPctVec);
else
    incPctStr = char(string(incPctVec));
end
setenv('SECTION533_INC_PCT_VEC', incPctStr);
setenv('SECTION533_PAPER_INDEPENDENT', char(string(paperIndependent)));
setenv('SECTION533_PAPER_LINE_MODE', char(string(paperLineMode)));
setenv('SECTION533_WARMSTART_KICK', char(string(warmstartKick)));
setenv('SECTION533_VERBOSE', char(string(verbose)));
setenv('SECTION533_KEEP_FIGURES', char(string(keepFigures)));
setenv('SECTION533_PRINT_TABLES', char(string(printTables)));
setenv('SECTION533_PARALLEL_ENABLE', char(string(parallelEnable)));
setenv('SECTION533_PARALLEL_WORKERS', char(string(parallelWorkers)));
setenv('SECTION533_PARALLEL_LOG_LEVEL', char(string(parallelLogLevel)));
end

function run_modes_restore_env_533_(old)
try setenv('SECTION533_INC_PCT_VEC', old.INC_PCT_VEC); catch, end
try setenv('SECTION533_PAPER_INDEPENDENT', old.PAPER_INDEPENDENT); catch, end
try setenv('SECTION533_PAPER_LINE_MODE', old.PAPER_LINE_MODE); catch, end
try setenv('SECTION533_WARMSTART_KICK', old.WARMSTART_KICK); catch, end
try setenv('SECTION533_VERBOSE', old.VERBOSE); catch, end
try setenv('SECTION533_KEEP_FIGURES', old.KEEP_FIGURES); catch, end
try setenv('SECTION533_PRINT_TABLES', old.PRINT_TABLES); catch, end
try setenv('SECTION533_PARALLEL_ENABLE', old.PARALLEL_ENABLE); catch, end
try setenv('SECTION533_PARALLEL_WORKERS', old.PARALLEL_WORKERS); catch, end
try setenv('SECTION533_PARALLEL_LOG_LEVEL', old.PARALLEL_LOG_LEVEL); catch, end
end

% ===== SECTION 541 环境变量辅助函数 =====
function tf = run_modes_will_run_section_541_(runMode, runModeMulti)
tf = false;
try
    if nargin >= 2 && ~isempty(runModeMulti)
        lst = runModeMulti;
    else
        lst = {runMode};
    end
    s = lower(strtrim(string(lst)));
    s = replace(s, "section_", "");
    tf = any(s == "541");
catch
    tf = false;
end
end

function tf = run_modes_will_run_section_542_(runMode, runModeMulti)
tf = false;
try
    if nargin >= 2 && ~isempty(runModeMulti)
        lst = runModeMulti;
    else
        lst = {runMode};
    end
    s = lower(strtrim(string(lst)));
    s = replace(s, "section_", "");
    tf = any(s == "542");
catch
    tf = false;
end
end

function old = run_modes_capture_env_541_()%541 环境变量捕获
old = struct();
old.MODE = getenv('SECTION541_MODE');
old.DATA_POLICY = getenv('SECTION541_DATA_POLICY');
old.PAPER_STATIC_XLSX = getenv('SECTION541_PAPER_STATIC_XLSX');
old.PAPER_EVENTS_XLSX = getenv('SECTION541_PAPER_EVENTS_XLSX');
old.QKG  = getenv('SECTION541_QKG');
old.TMIN = getenv('SECTION541_TMIN');
old.SEED = getenv('SECTION541_SEED');
old.QACCUM = getenv('SECTION541_QACCUM');
old.WINDOW = getenv('SECTION541_WINDOW');
old.MAX_EXTRAEV = getenv('SECTION541_MAX_EXTRAEV');
old.MAX_EXTRACV = getenv('SECTION541_MAX_EXTRACV');
old.CONSOLE_VERBOSE = getenv('SECTION541_CONSOLE_VERBOSE');
old.KEEP_FIGURES = getenv('SECTION541_KEEP_FIGURES');
old.PRINT_TABLES = getenv('SECTION541_PRINT_TABLES');
old.PARALLEL_ENABLE = getenv('SECTION541_PARALLEL_ENABLE');
old.PARALLEL_WORKERS = getenv('SECTION541_PARALLEL_WORKERS');
old.PARALLEL_LOG_LEVEL = getenv('SECTION541_PARALLEL_LOG_LEVEL');
old.VALIDATE_ENABLE = getenv('SECTION541_VALIDATE_ENABLE');
old.WARMSTART = getenv('SECTION541_WARMSTART');
old.CACHE_ENABLE = getenv('SECTION541_CACHE_ENABLE');
old.DEFAULT_RECV_WINDOW = getenv('SECTION541_DEFAULT_RECV_WINDOW');
end

function run_modes_apply_env_541_(mode, dataPolicy, qkg, tmin, seed, qaccum, win, maxExtraEV, maxExtraCV, consoleVerbose, paperStaticXlsx, paperEventsXlsx, keepFigures, printTables, parallelEnable, parallelWorkers, parallelLogLevel, validateEnable, warmstart, cacheEnable, defaultRecvWindow)%541 环境变量应用
setenv('SECTION541_MODE', char(string(mode)));
setenv('SECTION541_DATA_POLICY', char(string(dataPolicy)));
setenv('SECTION541_PAPER_STATIC_XLSX', char(string(paperStaticXlsx)));
setenv('SECTION541_PAPER_EVENTS_XLSX', char(string(paperEventsXlsx)));
setenv('SECTION541_QKG',  char(string(qkg)));
setenv('SECTION541_TMIN', char(string(tmin)));
setenv('SECTION541_SEED', char(string(seed)));
setenv('SECTION541_QACCUM', char(string(qaccum)));
setenv('SECTION541_WINDOW', char(string(win)));
setenv('SECTION541_MAX_EXTRAEV', char(string(maxExtraEV)));
setenv('SECTION541_MAX_EXTRACV', char(string(maxExtraCV)));
setenv('SECTION541_CONSOLE_VERBOSE', char(string(consoleVerbose)));
setenv('SECTION541_KEEP_FIGURES', char(string(keepFigures)));
setenv('SECTION541_PRINT_TABLES', char(string(printTables)));
setenv('SECTION541_PARALLEL_ENABLE', char(string(parallelEnable)));
setenv('SECTION541_PARALLEL_WORKERS', char(string(parallelWorkers)));
setenv('SECTION541_PARALLEL_LOG_LEVEL', char(string(parallelLogLevel)));
setenv('SECTION541_VALIDATE_ENABLE', char(string(validateEnable)));
setenv('SECTION541_WARMSTART', char(string(warmstart)));
setenv('SECTION541_CACHE_ENABLE', char(string(cacheEnable)));
setenv('SECTION541_DEFAULT_RECV_WINDOW', char(string(defaultRecvWindow)));
end

function run_modes_restore_env_541_(old)%541 环境变量恢复
try setenv('SECTION541_MODE', old.MODE); catch, end
try setenv('SECTION541_DATA_POLICY', old.DATA_POLICY); catch, end
try setenv('SECTION541_PAPER_STATIC_XLSX', old.PAPER_STATIC_XLSX); catch, end
try setenv('SECTION541_PAPER_EVENTS_XLSX', old.PAPER_EVENTS_XLSX); catch, end
try setenv('SECTION541_QKG',  old.QKG); catch, end
try setenv('SECTION541_TMIN', old.TMIN); catch, end
try setenv('SECTION541_SEED', old.SEED); catch, end
try setenv('SECTION541_QACCUM', old.QACCUM); catch, end
try setenv('SECTION541_WINDOW', old.WINDOW); catch, end
try setenv('SECTION541_MAX_EXTRAEV', old.MAX_EXTRAEV); catch, end
try setenv('SECTION541_MAX_EXTRACV', old.MAX_EXTRACV); catch, end
try setenv('SECTION541_CONSOLE_VERBOSE', old.CONSOLE_VERBOSE); catch, end
try setenv('SECTION541_KEEP_FIGURES', old.KEEP_FIGURES); catch, end
try setenv('SECTION541_PRINT_TABLES', old.PRINT_TABLES); catch, end
try setenv('SECTION541_PARALLEL_ENABLE', old.PARALLEL_ENABLE); catch, end
try setenv('SECTION541_PARALLEL_WORKERS', old.PARALLEL_WORKERS); catch, end
try setenv('SECTION541_PARALLEL_LOG_LEVEL', old.PARALLEL_LOG_LEVEL); catch, end
try setenv('SECTION541_VALIDATE_ENABLE', old.VALIDATE_ENABLE); catch, end
try setenv('SECTION541_WARMSTART', old.WARMSTART); catch, end
try setenv('SECTION541_CACHE_ENABLE', old.CACHE_ENABLE); catch, end
try setenv('SECTION541_DEFAULT_RECV_WINDOW', old.DEFAULT_RECV_WINDOW); catch, end
end

function old = run_modes_capture_env_542_()%542 环境变量捕获
old = struct();
old.BASELINE_MAX_EXTRAEV = getenv('SECTION542_BASELINE_MAX_EXTRAEV');
old.BASELINE_MAX_EXTRACV = getenv('SECTION542_BASELINE_MAX_EXTRACV');
old.BASE_NCV = getenv('SECTION542_BASE_NCV');
old.BASE_NEV = getenv('SECTION542_BASE_NEV');
old.BASELINE_MODE = getenv('SECTION542_BASELINE_MODE');
old.CONSOLE_VERBOSE = getenv('SECTION542_CONSOLE_VERBOSE');
old.KEEP_FIGURES = getenv('SECTION542_KEEP_FIGURES');
old.PRINT_TABLES = getenv('SECTION542_PRINT_TABLES');
old.PARALLEL_ENABLE = getenv('SECTION542_PARALLEL_ENABLE');
old.PARALLEL_WORKERS = getenv('SECTION542_PARALLEL_WORKERS');
old.PARALLEL_LOG_LEVEL = getenv('SECTION542_PARALLEL_LOG_LEVEL');
end

function run_modes_apply_env_542_(baselineMaxExtraEV, baselineMaxExtraCV, baseNcv, baseNev, baselineMode, consoleVerbose, keepFigures, printTables, parallelEnable, parallelWorkers, parallelLogLevel)%542 环境变量应用
setenv('SECTION542_BASELINE_MAX_EXTRAEV', char(string(baselineMaxExtraEV)));
setenv('SECTION542_BASELINE_MAX_EXTRACV', char(string(baselineMaxExtraCV)));
setenv('SECTION542_BASE_NCV', char(string(baseNcv)));
setenv('SECTION542_BASE_NEV', char(string(baseNev)));
setenv('SECTION542_BASELINE_MODE', char(string(baselineMode)));
setenv('SECTION542_CONSOLE_VERBOSE', char(string(consoleVerbose)));
setenv('SECTION542_KEEP_FIGURES', char(string(keepFigures)));
setenv('SECTION542_PRINT_TABLES', char(string(printTables)));
setenv('SECTION542_PARALLEL_ENABLE', char(string(parallelEnable)));
setenv('SECTION542_PARALLEL_WORKERS', char(string(parallelWorkers)));
setenv('SECTION542_PARALLEL_LOG_LEVEL', char(string(parallelLogLevel)));
end

function run_modes_restore_env_542_(old)%542 环境变量恢复
try setenv('SECTION542_BASELINE_MAX_EXTRAEV', old.BASELINE_MAX_EXTRAEV); catch, end
try setenv('SECTION542_BASELINE_MAX_EXTRACV', old.BASELINE_MAX_EXTRACV); catch, end
try setenv('SECTION542_BASE_NCV', old.BASE_NCV); catch, end
try setenv('SECTION542_BASE_NEV', old.BASE_NEV); catch, end
try setenv('SECTION542_BASELINE_MODE', old.BASELINE_MODE); catch, end
try setenv('SECTION542_CONSOLE_VERBOSE', old.CONSOLE_VERBOSE); catch, end
try setenv('SECTION542_KEEP_FIGURES', old.KEEP_FIGURES); catch, end
try setenv('SECTION542_PRINT_TABLES', old.PRINT_TABLES); catch, end
try setenv('SECTION542_PARALLEL_ENABLE', old.PARALLEL_ENABLE); catch, end
try setenv('SECTION542_PARALLEL_WORKERS', old.PARALLEL_WORKERS); catch, end
try setenv('SECTION542_PARALLEL_LOG_LEVEL', old.PARALLEL_LOG_LEVEL); catch, end
end

function results = run_modes_execute(cfg)
% 修改日志
% - v1 2026-01-21: 新增 run_modes 统一执行器：集中处理 runTag/modeLabel/profile/section 选择，并强制 run_modes 接入检查。
% - v2 2026-01-22: 控制台输出中文化。
% - v3 2026-01-22: RUN_PROFILE 改为“算法流程档位”（仅流程增强，不改任何参数值）。
% - v4 2026-01-22: 移除旧别名，仅保留技术名 ALGO_*。
% - v5 2026-01-22: 规范说明文字精简，避免出现旧别名。
%
% 说明：
% - run_modes.m 是唯一开关入口；本函数仅负责“执行与校验”，避免脚本里散落逻辑。

    if nargin < 1 || isempty(cfg)
        cfg = struct();
    end
    if ~isstruct(cfg)
        error('run_modes_execute:badCfg', 'cfg 必须是 struct');
    end

    cfg = fill_defaults_(cfg);

    init_modules();

    registry = section_registry();
    regKeys = sort(keys(registry));

    fprintf('可用 section（来自 section_registry）：\n');
    for i = 1:numel(regKeys)
        fprintf('  - %s\n', regKeys{i});
    end

    enforce_run_modes_sync(cfg.supportedSections, registry, 'RunModesPath', cfg.runModesPath);

    % 选择要运行的 section
    runKeys = cfg.runModeMulti;
    if isempty(runKeys)
        runKeys = {cfg.runMode};
    end
    runKeys = normalize_run_keys_(runKeys);

    % 检查：只允许运行 SUPPORTED_SECTIONS 中的 section
    supp = normalize_supported_(cfg.supportedSections);
    missing = setdiff(runKeys, supp);
    if ~isempty(missing)
        error('run_modes_execute:unknownMode', 'RUN_MODE 不在 SUPPORTED_SECTIONS 中：%s', strjoin(missing, ', '));
    end

    % profile -> algoProfile（仅算法流程增强；不改任何参数）
    [algoProfile, profileNote] = build_profile_algo_(cfg.runProfile, cfg.modeLabel);
    if ~isempty(profileNote)
        fprintf('[配置档] %s\n', profileNote);
    end

    fprintf('[运行] 算法档位=%s | 模式=%s | runTag=%s | 强制重算=%d\n', algoProfile, cfg.modeLabel, cfg.runTag, double(cfg.forceRecompute));
    fprintf('[运行] section=%s\n', strjoin(runKeys, ', '));

    results = run_all( ...
        'Sections', runKeys, ...
        'RunTag', cfg.runTag, ...
        'ModeLabel', cfg.modeLabel, ...
        'ForceRecompute', cfg.forceRecompute, ...
        'Override', struct(), ...
        'AlgoProfile', algoProfile ...
        );
end

% ===================== helpers =====================
function cfg = fill_defaults_(cfg)
cfg = set_default_(cfg, 'supportedSections', {});
cfg = set_default_(cfg, 'runMode', '533');
cfg = set_default_(cfg, 'runModeMulti', {});
cfg = set_default_(cfg, 'runTag', 'default');
cfg = set_default_(cfg, 'modeLabel', 'ENHANCED');
cfg = set_default_(cfg, 'runProfile', 'ALGO_INTENSIFY');
cfg = set_default_(cfg, 'forceRecompute', false);
cfg = set_default_(cfg, 'runModesPath', '');

cfg.modeLabel = upper(strtrim(char(string(cfg.modeLabel))));
cfg.runTag = char(string(cfg.runTag));
cfg.runProfile = upper(strtrim(char(string(cfg.runProfile))));
end

function s = set_default_(s, f, v)
if ~isfield(s, f) || isempty(s.(f))
    s.(f) = v;
end
end

function keysOut = normalize_run_keys_(keysIn)
if isstring(keysIn)
    keysIn = cellstr(keysIn);
end
if ~iscell(keysIn)
    error('run_modes_execute:badRunKeys', 'RUN_MODE_MULTI 必须为 cell/string 数组');
end

keysOut = cell(size(keysIn));
for i = 1:numel(keysIn)
    k = char(string(keysIn{i}));
    k = strtrim(k);
    if isempty(k)
        error('run_modes_execute:emptyKey', 'RUN_MODE 不能为空');
    end
    if startsWith(lower(k), 'section_')
        keysOut{i} = k;
    else
        keysOut{i} = ['section_' k];
    end
end
end

function supp = normalize_supported_(supportedSectionIds)
supp = supportedSectionIds;
if isstring(supp)
    supp = cellstr(supp);
end
if ~iscell(supp)
    error('run_modes_execute:badSupported', 'SUPPORTED_SECTIONS 必须为 cell/string 数组');
end
supp = normalize_run_keys_(supp);
supp = unique(supp);
end

function [algoProfile, note] = build_profile_algo_(profile, modeLabel)
    algoProfile = 'BASELINE';
    note = '';

    profile = upper(strtrim(char(string(profile))));
    modeLabel = upper(strtrim(char(string(modeLabel))));

    if startsWith(modeLabel, 'PAPER') && ~any(strcmp(profile, {'BASELINE','FAST'}))
        error('run_modes_execute:paperStrongNotAllowed', 'PAPER 模式仅允许 BASELINE/FAST（严格复现）；请切换 MODE_LABEL=ENHANCED 再使用算法增强档位。');
    end

    switch profile
        case 'BASELINE'
            algoProfile = 'BASELINE';
            note = 'BASELINE：不改任何参数/算法流程，严格使用默认实现。';
            return;

        case 'FAST'
            algoProfile = 'BASELINE';
            note = 'FAST：仅用于流程自检；不改任何参数/算法流程（等同 BASELINE）。';
            return;

        case 'ALGO_INTENSIFY'
            algoProfile = 'ALGO_INTENSIFY';
            note = 'ALGO_INTENSIFY：不改参数，仅增加局部搜索流程频次（强强化）。';
            return;

        case 'ALGO_DIVERSIFY'
            algoProfile = 'ALGO_DIVERSIFY';
            note = 'ALGO_DIVERSIFY：不改参数，仅在停滞时追加多样化操作（强探索）。';
            return;

        case 'ALGO_HYBRID'
            algoProfile = 'ALGO_HYBRID';
            note = 'ALGO_HYBRID：不改参数，同时增强局部搜索与多样化。';
            return;

        otherwise
            error('run_modes_execute:badProfile', '未知 RUN_PROFILE=%s（支持 BASELINE/FAST/ALGO_INTENSIFY/ALGO_DIVERSIFY/ALGO_HYBRID）', profile);
    end
end

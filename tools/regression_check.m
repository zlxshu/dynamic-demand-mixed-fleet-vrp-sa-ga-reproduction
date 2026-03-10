function summary = regression_check(varargin)
% 修改日志
% - v1 2026-01-21: 新增回归验收脚本 regression_check；覆盖 531/532/533，验证签名一致性与旧缓存隔离。
% - v1 2026-01-21: 输出 summary 表到 outputs/regression/tables/，并保存回归 audit 日志。
% - v2 2026-01-21: 控制台输出中文化（回归提示/错误信息/汇总保存路径）。

    p = inputParser();
    p.addParameter('RunTag', 'regression', @(s) ischar(s) || isstring(s));
    p.addParameter('Fast', true, @(x) islogical(x) && isscalar(x));
    p.parse(varargin{:});
    opt = p.Results;

    % 确保 modules 在路径上（允许从任意工作目录调用）
    thisFile = mfilename('fullpath');
    thisDir = fileparts(thisFile);           % .../tools
    modulesDir = fullfile(fileparts(thisDir), 'modules');
    if exist(modulesDir, 'dir') == 7
        addpath(modulesDir);
        addpath(genpath(modulesDir));
    end
    init_modules();

    runTag = char(string(opt.RunTag));

    % 可选：快速回归（不改目标函数，只缩短求解配置）
    override = struct();
    if opt.Fast
        override.SolverCfg = struct();
        override.SolverCfg.NP = 60;
        override.SolverCfg.MaxGen = 80;
        override.SolverCfg.NRun = 3;
    end

    % 预先构造 ctx/签名（用于断言与 dummy legacy cache）
    ctxProbe = get_config('RunTag', runTag, 'ForceRecompute', true);
    if ~isempty(fieldnames(override))
        ctxProbe = apply_override(ctxProbe, override);
        ctxProbe = assert_config(ctxProbe);
    end
    sigProbe = build_signature(ctxProbe);

    % 构造一个“签名不匹配”的 legacy 缓存，确保会被 ignore（不依赖用户已有旧文件）
    legacyDir = fullfile(ctxProbe.Meta.projectRoot, 'CACHE', 'section_532');
    ensure_dir(legacyDir);
    dummyMeta = struct();
    dummyMeta.sectionName = 'section_532';
    dummyMeta.modeTag = 'LEGACY_DUMMY';
    dummyMeta.timestamp = ctxProbe.Meta.timestamp;
    dummyMeta.paramSigFull = repmat('0', 1, 32);
    dummyMeta.paramSigShort = repmat('0', 1, 8);
    dummyMeta.dataSigFull = repmat('1', 1, 32);
    dummyMeta.dataSigShort = repmat('1', 1, 8);
    dummyMeta.cost = -1;
    dummyPayload = struct('note', 'dummy legacy cache for regression_check; should be ignored');
    dummyPath = cache_save(legacyDir, 'mix_2_2', dummyPayload, dummyMeta);
    fprintf('[回归] 已创建 legacy 假缓存（应被忽略）：%s\n', dummyPath);

    % 断言：同 ctx 下 531/532 签名一致（本地计算）
    assert(~isempty(sigProbe.param.full) && ~isempty(sigProbe.data.full));

    % 断言：dummy legacy cache 不会被当作匹配缓存加载
    [~, loadedPathLegacy, ~] = cache_load_best(legacyDir, 'mix_2_2', sigProbe.param.full, sigProbe.data.full);
    if ~isempty(loadedPathLegacy) && strcmp(loadedPathLegacy, dummyPath)
        error('[回归] legacy 假缓存被误加载（应被忽略）：%s', loadedPathLegacy);
    end
    % 清理 dummy legacy 文件（不污染工程根目录输出）
    try
        if exist(dummyPath, 'file') == 2
            delete(dummyPath);
            fprintf('[回归] 已删除 legacy 假缓存：%s\n', dummyPath);
        end
    catch
    end

    % 运行 531/532（强制重算一次）+ 533
    results = run_all('Sections', {'531','532','533'}, 'RunTag', runTag, 'ForceRecompute', true, 'Override', override);

    % 读取两份 audit.txt，比对签名（确保打印口径一致）
    p531 = output_paths(ctxProbe.Meta.projectRoot, 'section_531', runTag);
    p532 = output_paths(ctxProbe.Meta.projectRoot, 'section_532', runTag);
    a531 = fullfile(p531.logs, 'audit.txt');
    a532 = fullfile(p532.logs, 'audit.txt');
    [ps531, ds531] = parse_last_sig_(a531);
    [ps532, ds532] = parse_last_sig_(a532);
    if ~strcmp(ps531, ps532) || ~strcmp(ds531, ds532)
        error('[回归] 531/532 的审计签名不一致：531(%s/%s) vs 532(%s/%s)', ps531, ds531, ps532, ds532);
    end

    % 汇总表（不硬编码正确成本数值，只记录本次运行结果与签名）
    s531 = results.section_531;
    s532 = results.section_532;
    s533 = results.section_533;

    rows = {};
    rows(end+1,:) = {'section_531','bestCost', s531.bestGlobal.cost, 'mix baseline'}; %#ok<AGROW>
    try
        rows(end+1,:) = {'section_532','mixBestCost', s532.mixResult.bestGlobal.cost, 'mix_2_2 (recomputed/signature-isolated)'}; %#ok<AGROW>
    catch
    end
    try
        rows(end+1,:) = {'section_532','customBestCost', s532.customResult.bestGlobal.cost, 'custom fleet'}; %#ok<AGROW>
    catch
    end
    try
        rows(end+1,:) = {'section_533','rg_finalCost(end)', s533.tblR(end).finalCost, 'rg sensitivity (incumbent curve)'}; %#ok<AGROW>
    catch
    end

    summary = cell2table(rows, 'VariableNames', {'Section','Metric','Value','Note'});
    summary.RunTag = repmat(string(runTag), height(summary), 1);
    summary.ParamSigShort = repmat(string(sigProbe.param.short), height(summary), 1);
    summary.DataSigShort = repmat(string(sigProbe.data.short), height(summary), 1);
    summary.Timestamp = repmat(string(ctxProbe.Meta.timestamp), height(summary), 1);

    pReg = output_paths(ctxProbe.Meta.projectRoot, 'regression', runTag);
    sumPath = fullfile(pReg.tables, artifact_filename('regression_summary', 'regression', runTag, sigProbe.param.short, sigProbe.data.short, ctxProbe.Meta.timestamp, '.xlsx'));
    try
        writetable(summary, sumPath);
    catch
        sumPath = replace_ext_(sumPath, '.csv');
        writetable(summary, sumPath);
    end

    % 回归审计日志
    regAudit = sprintf('[回归] runTag=%s | paramSig=%s/%s | dataSig=%s/%s | summary=%s', ...
        runTag, sigProbe.param.short, sigProbe.param.full, sigProbe.data.short, sigProbe.data.full, sumPath);
    append_text_(fullfile(pReg.logs, 'audit.txt'), regAudit);

    fprintf('[回归] 汇总已保存：%s\n', sumPath);
end

function [paramFull, dataFull] = parse_last_sig_(auditFile)
paramFull = '';
dataFull = '';
if exist(auditFile, 'file') ~= 2
    return;
end
txt = '';
try
    txt = fileread(auditFile);
catch
    return;
end
% 取最后一次出现
m1 = regexp(txt, '\\[param_signature\\]\\s+\\S+\\s+\\|\\s+(?<full>[0-9a-f]+)', 'names');
if ~isempty(m1), paramFull = m1(end).full; end
m2 = regexp(txt, '\\[data_signature\\s+\\]\\s+\\S+\\s+\\|\\s+(?<full>[0-9a-f]+)', 'names');
if ~isempty(m2), dataFull = m2(end).full; end
end

function append_text_(filePath, text)
ensure_dir(fileparts(filePath));
fid = fopen(filePath, 'a');
if fid < 0, return; end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', text);
end

function p = replace_ext_(p, newExt)
[d, n] = fileparts(p);
if newExt(1) ~= '.', newExt = ['.' newExt]; end
p = fullfile(d, [n newExt]);
end


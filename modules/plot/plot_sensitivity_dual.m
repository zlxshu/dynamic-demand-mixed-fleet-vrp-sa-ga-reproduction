function out = plot_sensitivity_dual(tbl, meta, paths, cfg)
% 修改日志
% - v1 2026-01-21: 新增统一敏感性双版本绘图：paper(累计最优) + diag(三层信息)；字段名自动映射；中文图例；统一导出与命名。
% - v2 2026-01-21: paper 主曲线强制使用“累计最优(cummin)”避免反直觉抖动；diag 保留“当点最优/均值±标准差”噪声；缺字段层自动降级跳过并提示。
% - v3 2026-01-21: 控制台输出中文化（论文版/诊断版导出路径与缺字段提示）。
% - v4 2026-02-01: 论文版曲线支持“当点最优”模式以对齐论文口径。
% - v5 2026-02-02: 记录标注缺失的调试上下文与放置统计。
% - v6 2026-02-02: 论文版先应用样式再标注，避免样式重置坐标导致标注被裁切。

if nargin < 2 || isempty(meta), meta = struct(); end
if nargin < 3 || isempty(paths), paths = struct(); end
if nargin < 4 || isempty(cfg), cfg = struct(); end

if ~isfield(cfg, 'dpi') || isempty(cfg.dpi), cfg.dpi = 300; end
if ~isfield(cfg, 'exportNoAxisLabels') || isempty(cfg.exportNoAxisLabels), cfg.exportNoAxisLabels = true; end
if ~isfield(cfg, 'labelAllPoints') || isempty(cfg.labelAllPoints), cfg.labelAllPoints = true; end

sectionName = pick_(meta, {'sectionName'}, pick_(paths, {'sectionName'}, 'unknown_section'));
runTag = pick_(meta, {'runTag','modeTag'}, pick_(paths, {'runTag'}, 'default'));
ts = pick_(meta, {'timestamp'}, datestr(now, 'yyyymmddTHHMMSS'));

paramSig = pick_(meta, {'paramSigShort','paramSig'}, 'nosig');
dataSig  = pick_(meta, {'dataSigShort','dataSig'}, 'nodata');

titleZh = pick_(meta, {'titleZh','title'}, '敏感性分析');
xNameZh = pick_(meta, {'xNameZh'}, '变化率(%)');
yNameZh = pick_(meta, {'yNameZh'}, '总成本(元)');

baseName = pick_(meta, {'artifactName','name','nameEn'}, 'Sensitivity');

incPct = must_vec_(tbl, {'incPct','inc','pct'});

% -------- 口径统一：runCosts -> mean/std/pointBest；incumbentBest=累积最优(cummin) --------
runCosts = get_run_costs_(tbl);
meanCost = get_vec_(tbl, {'meanCost','mu'});
stdCost  = get_vec_(tbl, {'stdCost','sd'});

if isempty(meanCost) && ~isempty(runCosts)
    meanCost = cellfun(@(x) mean(x, 'omitnan'), runCosts);
end
if isempty(stdCost) && ~isempty(runCosts)
    stdCost = cellfun(@(x) std(x, 0, 'omitnan'), runCosts);
end

pointBestCost = get_vec_(tbl, {'pointBestCost','bestFoundCost','bestCost','finalCost'});
if isempty(pointBestCost) && ~isempty(runCosts)
    pointBestCost = cellfun(@(x) min(x, [], 'omitnan'), runCosts);
end
if isempty(pointBestCost)
    error('plot_sensitivity_dual:missingField', 'tbl 缺少 pointBestCost/bestFoundCost/runCosts 等字段');
end
% paper/diag 曲线候选：累计最优（优先用 tbl.incumbentBestCost；否则用 cummin(pointBestCost)）
incumbentBestCost = get_vec_(tbl, {'incumbentBestCost','incumbentBest','incumbentBestCostPlot'});
if isempty(incumbentBestCost)
    incumbentBestCost = cummin(pointBestCost(:));
else
    incumbentBestCost = incumbentBestCost(:);
    incumbentBestCost = cummin(incumbentBestCost);
end

paperLineMode = pick_(cfg, {'paperLineMode'}, pick_(meta, {'paperLineMode'}, 'cummin'));
if strcmpi(paperLineMode, 'pointbest')
    paperLine = pointBestCost(:);
    paperLineLabel = '当点最优';
else
    paperLine = incumbentBestCost(:);
    paperLineLabel = '累计最优';
end

% -------- 可选字段（成本构成/机制指标）--------
travelCost = get_vec_(tbl, {'travelCost','driveCost'});
chargeCost = get_vec_(tbl, {'chargeCost','elecCost'});
twCost     = get_vec_(tbl, {'twCost'});
fixedCost  = get_vec_(tbl, {'fixedCost','startCost'});
carbonCost = get_vec_(tbl, {'carbonCost'});

totalChargeTime = get_vec_(tbl, {'totalChargeTime_h','totalChargeTime'});
nCharges = get_vec_(tbl, {'nCharges'});
totalChargedEnergy = get_vec_(tbl, {'totalChargedEnergy_kWh','totalChargedEnergy'});
totalLateness = get_vec_(tbl, {'totalLateness_min','totalLateness'});

% -------- 标注点：默认全点（5.3.3 要求），否则端点+下降点 --------
if cfg.labelAllPoints
    idxAnn = (1:numel(incPct))';
else
    idxAnn = unique([1; numel(incPct); find(diff(paperLine) < -1e-9) + 1]);
    idxAnn = idxAnn(idxAnn >= 1 & idxAnn <= numel(incPct));
end

% ===================== paper 版 =====================
figPaper = figure('Name', sprintf('%s_%s_paper', sectionName, runTag), 'NumberTitle', 'off');
axP = axes(figPaper);
hold(axP, 'on');
pLine = plot(axP, incPct, paperLine, '-o', 'DisplayName', paperLineLabel);
title(axP, titleZh, 'Interpreter','none');
xlabel(axP, xNameZh, 'Interpreter','none');
ylabel(axP, yNameZh, 'Interpreter','none');
legend(axP, 'Location', 'best', 'Interpreter','none');
    apply_plot_style(figPaper, axP, 'sensitivity');
    annotate_points_(axP, incPct, paperLine, idxAnn, pLine.Color, 'paper');

paperPng = fullfile(paths.figures, artifact_filename([baseName '_paper'], sectionName, runTag, paramSig, dataSig, ts, '.png'));
export_figure(figPaper, paperPng, cfg.dpi, struct('exportNoAxisLabels', cfg.exportNoAxisLabels));
fprintf('[敏感性][论文版] %s\n', paperPng);

% ===================== diag 版 =====================
figDiag = figure('Name', sprintf('%s_%s_diag', sectionName, runTag), 'NumberTitle', 'off');
t = tiledlayout(figDiag, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
try
    title(t, [titleZh '（诊断版）'], 'Interpreter','none');
catch
    sgtitle(figDiag, [titleZh '（诊断版）'], 'Interpreter','none');
end

% (1) 成本层
ax1 = nexttile(t, 1);
hold(ax1, 'on');
if ~isempty(meanCost) && ~isempty(stdCost) && all(size(meanCost) == size(incPct)) && all(size(stdCost) == size(incPct))
    errorbar(ax1, incPct, meanCost, stdCost, 'o-', 'DisplayName', '均值±标准差');
else
    fprintf('[敏感性][诊断版] 缺少 meanCost/stdCost -> 跳过“均值±标准差”\n');
end
plot(ax1, incPct, pointBestCost, 's-', 'DisplayName', '当点最优');
lineIB = plot(ax1, incPct, incumbentBestCost, 'd-', 'DisplayName', '累计最优');
title(ax1, '成本层', 'Interpreter','none');
xlabel(ax1, xNameZh, 'Interpreter','none');
ylabel(ax1, yNameZh, 'Interpreter','none');
legend(ax1, 'Location', 'best', 'Interpreter','none');
annotate_points_(ax1, incPct, incumbentBestCost, idxAnn, lineIB.Color, 'diag_cost');

% (2) 成本构成层
ax2 = nexttile(t, 2);
hold(ax2, 'on');
hasBreakdown = false;
if ~isempty(travelCost), plot(ax2, incPct, travelCost, '-o', 'DisplayName', '行驶成本'); hasBreakdown = true; end
if ~isempty(chargeCost), plot(ax2, incPct, chargeCost, '-s', 'DisplayName', '充电成本'); hasBreakdown = true; end
if ~isempty(twCost), plot(ax2, incPct, twCost, '-d', 'DisplayName', '时间窗成本'); hasBreakdown = true; end
if ~isempty(fixedCost), plot(ax2, incPct, fixedCost, '-^', 'DisplayName', '固定成本'); hasBreakdown = true; end
if ~isempty(carbonCost), plot(ax2, incPct, carbonCost, '-v', 'DisplayName', '碳排成本'); hasBreakdown = true; end
title(ax2, '成本构成层', 'Interpreter','none');
xlabel(ax2, xNameZh, 'Interpreter','none');
ylabel(ax2, '成本(元)', 'Interpreter','none');
if hasBreakdown
    legend(ax2, 'Location', 'best', 'Interpreter','none');
else
    axis(ax2, 'off');
    text(ax2, 0.5, 0.5, '缺少成本构成字段，已跳过', 'Units', 'normalized', 'HorizontalAlignment', 'center', 'Interpreter','none');
    fprintf('[敏感性][诊断版] 缺少 travelCost/chargeCost/twCost 等字段 -> 跳过“成本构成层”\n');
end

% (3) 机制层
ax3 = nexttile(t, 3);
hold(ax3, 'on');
hasMech = false;
if ~isempty(totalChargeTime)
    yyaxis(ax3, 'left');
    plot(ax3, incPct, totalChargeTime, '-o', 'DisplayName', '总充电时间(小时)');
    ylabel(ax3, '总充电时间(小时)', 'Interpreter','none');
    hasMech = true;
end
yyaxis(ax3, 'right');
if ~isempty(nCharges)
    plot(ax3, incPct, nCharges, '-s', 'DisplayName', '充电次数');
    ylabel(ax3, '充电次数', 'Interpreter','none');
    hasMech = true;
elseif ~isempty(totalChargedEnergy)
    plot(ax3, incPct, totalChargedEnergy, '-s', 'DisplayName', '充电总电量(kWh)');
    ylabel(ax3, '充电总电量(kWh)', 'Interpreter','none');
    hasMech = true;
end
if ~isempty(totalLateness)
    plot(ax3, incPct, totalLateness, '--', 'DisplayName', '总迟到(分钟)');
    hasMech = true;
end
title(ax3, '机制层', 'Interpreter','none');
xlabel(ax3, xNameZh, 'Interpreter','none');
if hasMech
    legend(ax3, 'Location', 'best', 'Interpreter','none');
else
    axis(ax3, 'off');
    text(ax3, 0.5, 0.5, '缺少机制指标字段，已跳过', 'Units', 'normalized', 'HorizontalAlignment', 'center', 'Interpreter','none');
    fprintf('[敏感性][诊断版] 缺少 totalChargeTime/nCharges 等字段 -> 跳过“机制层”\n');
end

    apply_plot_style(figDiag, findall(figDiag, 'Type', 'axes'), 'sensitivity');
add_footer_(figDiag, meta, runTag, paramSig, dataSig);

diagPng = fullfile(paths.figures, artifact_filename([baseName '_diag'], sectionName, runTag, paramSig, dataSig, ts, '.png'));
export_figure(figDiag, diagPng, cfg.dpi, struct('exportNoAxisLabels', cfg.exportNoAxisLabels));
fprintf('[敏感性][诊断版] %s\n', diagPng);

out = struct();
out.paperPng = paperPng;
out.diagPng = diagPng;
out.paperFigure = figPaper;
out.diagFigure = figDiag;
end

% ===================== helpers =====================
function v = pick_(s, fields, fallback)
v = fallback;
if ~isstruct(s), return; end
for i = 1:numel(fields)
    f = fields{i};
    if isfield(s, f) && ~isempty(s.(f))
        v = s.(f);
        return;
    end
end
end

function incPct = must_vec_(tbl, names)
incPct = get_vec_(tbl, names);
if isempty(incPct)
    error('plot_sensitivity_dual:missingX', 'tbl 缺少 incPct/inc 字段');
end
incPct = incPct(:);
end

function v = get_vec_(tbl, names)
v = [];
for i = 1:numel(names)
    nm = names{i};
    if istable(tbl)
        if any(strcmp(tbl.Properties.VariableNames, nm))
            vv = tbl.(nm);
            if isnumeric(vv)
                v = vv(:);
                return;
            end
        end
    elseif isstruct(tbl) && ~isempty(tbl)
        if isfield(tbl, nm)
            try
                vv = [tbl.(nm)];
                if isnumeric(vv)
                    v = vv(:);
                    return;
                end
            catch
            end
        end
    end
end
end

function runCosts = get_run_costs_(tbl)
runCosts = {};
if istable(tbl)
    if any(strcmp(tbl.Properties.VariableNames, 'runCosts'))
        rc = tbl.runCosts;
        if iscell(rc)
            runCosts = rc;
        elseif isnumeric(rc)
            runCosts = num2cell(rc, 2);
        end
    end
elseif isstruct(tbl) && ~isempty(tbl) && isfield(tbl, 'runCosts')
    try
        runCosts = arrayfun(@(s) s.runCosts, tbl, 'UniformOutput', false);
    catch
        runCosts = {};
    end
end
end

function annotate_points_(ax, x, y, idx, color, tag)
if isempty(idx), return; end
if nargin < 6, tag = ''; end
fontName = '';
try
    f = listfonts();
    if any(strcmpi(f, 'Microsoft YaHei'))
        fontName = 'Microsoft YaHei';
    elseif any(strcmpi(f, 'SimHei'))
        fontName = 'SimHei';
    end
catch
end
try
    idx = idx(:);
    idx = idx(idx >= 1 & idx <= numel(x));
    if isempty(idx), return; end
    xy = [x(idx), y(idx)];
    labels = arrayfun(@(v) sprintf('%.0f', v), y(idx), 'UniformOutput', false);
    segs = build_segments_(x, y);
    opts = struct('fontSize', 10, 'backgroundColor', 'none', 'margin', 1, ...
        'offsetScale', 0.012, 'avoidSegments', segs, 'linePadding', 0.002);
    hText = place_labels_no_overlap(ax, xy, labels, opts);
    if ~isempty(fontName)
        try set(hText, 'FontName', fontName); catch, end
    end
    if nargin >= 5 && ~isempty(color)
        try set(hText, 'Color', color); catch, end
    end
catch
end
end

function segs = build_segments_(x, y)
segs = zeros(0, 4);
try
    x = x(:); y = y(:);
    if numel(x) < 2 || numel(y) < 2
        return;
    end
    n = min(numel(x), numel(y));
    x = x(1:n); y = y(1:n);
    segs = [x(1:end-1) y(1:end-1) x(2:end) y(2:end)];
catch
    segs = zeros(0, 4);
end
end

function add_footer_(fig, ~, runTag, paramSig, dataSig)
note = sprintf('runTag=%s | paramSig=%s | dataSig=%s', char(string(runTag)), char(string(paramSig)), char(string(dataSig)));

try
    ann = annotation(fig, 'textbox', [0.01 0.001 0.98 0.06], 'String', note, 'EdgeColor', 'none', 'HorizontalAlignment', 'left', 'Interpreter','none');
    ann.FontSize = 10;
catch
end
end

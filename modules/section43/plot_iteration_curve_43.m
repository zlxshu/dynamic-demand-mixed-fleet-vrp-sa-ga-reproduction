function fig = plot_iteration_curve_43(gsaaCurve, gaCurve, saCurve, cfg)
% 修改日志
% - v9 2026-02-10: 回归论文风格主图（白底、单坐标轴、无附加放大/叠加标注），修复“主图被末端标记覆盖”显示问题；仅改绘图表现不改结果。
% - v8 2026-02-10: 新增“末段放大子图+终值标注”，仅提升真实曲线可读性，不改变任何算法结果与成本口径。
% - v7 2026-02-08: 新增图元信息字段（curve_lineage/curve_run_idx/figure_ref_sig），用于同run口径追溯。
% - v6 2026-02-08: 纵坐标标签按规定写死为“成本（元）”，禁止显示“目标函数值”口径。
% - v5 2026-02-06: 增加 fillLeadingNaN 开关（默认不回填），避免对前期无可行解区间做人工美化。
% - v1 2026-02-03: 新增 plot_iteration_curve_43；绘制论文图4.8算法迭代曲线。
% - v2 2026-02-03: 增加调试日志（debug.log）：记录曲线范围与前几项。
% - v3 2026-02-04: 处理曲线中的NaN值——用第一个有效值回填前面的NaN（避免SA前几代无可行解导致曲线中断）。
% - v4 2026-02-04: 移除调试日志。
%
% plot_iteration_curve_43 - 绘制三种算法的迭代曲线对比图（图4.8）
%
% 输入:
%   gsaaCurve - GSAA算法迭代曲线（MaxGen x 1）
%   gaCurve   - GA算法迭代曲线（MaxGen x 1）
%   saCurve   - SA算法迭代曲线（MaxGen x 1）
%   cfg       - 配置结构体（包含colors, curveMode等）
%
% 输出:
%   fig - 图形句柄

if nargin < 4 || ~isstruct(cfg)
    cfg = struct();
end

if ~isfield(cfg, 'colors') || ~isstruct(cfg.colors)
    cfg.colors = struct('GSAA', [0 0.4470 0.7410], 'GA', [0.8500 0.3250 0.0980], 'SA', [0.9290 0.6940 0.1250]);
end

doFillLeadingNaN = false;
if isfield(cfg, 'fillLeadingNaN')
    doFillLeadingNaN = logical(cfg.fillLeadingNaN);
end

if doFillLeadingNaN
    gsaaCurve = fill_leading_nan_(gsaaCurve);
    gaCurve = fill_leading_nan_(gaCurve);
    saCurve = fill_leading_nan_(saCurve);
end

gsaaCurve = gsaaCurve(:);
gaCurve = gaCurve(:);
saCurve = saCurve(:);

% 应用曲线模式
if isfield(cfg, 'curveMode') && strcmpi(cfg.curveMode, 'cummin')
    % 累积最优：每代取历史最优
    gsaaCurve = cummin(gsaaCurve);
    gaCurve = cummin(gaCurve);
    saCurve = cummin(saCurve);
end

MaxGen = numel(gsaaCurve);
x = 1:MaxGen;

% 创建图形（论文风格：白底、单图）
fig = figure('Name', '算法迭代曲线', 'NumberTitle', 'off', 'Position', [100 100 820 520], 'Color', 'w');
ax = axes('Parent', fig); %#ok<LAXES>
hold(ax, 'on');

% 绘制曲线
lineWidth = 1.5;
plot(ax, x, gsaaCurve, 'Color', cfg.colors.GSAA, 'LineWidth', lineWidth, 'DisplayName', 'GSAA');
plot(ax, x, gaCurve, 'Color', cfg.colors.GA, 'LineWidth', lineWidth, 'DisplayName', 'GA');
plot(ax, x, saCurve, 'Color', cfg.colors.SA, 'LineWidth', lineWidth, 'DisplayName', 'SA');

hold(ax, 'off');

% 设置图例
legend(ax, 'Location', 'northeast', 'FontSize', 10);

% 设置标签
xlabel(ax, '迭代次数', 'FontSize', 11);
ylabel(ax, '成本（元）', 'FontSize', 11);  % 4.3 规定：纵坐标固定使用“成本（元）”
title(ax, '算法迭代曲线', 'FontSize', 12);

% 设置坐标轴
xlim(ax, [1 MaxGen]);
grid(ax, 'on');
box(ax, 'on');
set(ax, 'FontSize', 10, 'Color', 'w', 'XColor', [0 0 0], 'YColor', [0 0 0]);

% 追溯元信息（用于审计，不改变图面口径）
try
    meta = struct();
    if isfield(cfg, 'curveLineage')
        meta.curve_lineage = char(string(cfg.curveLineage));
    else
        meta.curve_lineage = 'unknown';
    end
    if isfield(cfg, 'curveRunIdx')
        meta.curve_run_idx = double(cfg.curveRunIdx);
    else
        meta.curve_run_idx = NaN;
    end
    if isfield(cfg, 'figureRefSig')
        meta.figure_ref_sig = char(string(cfg.figureRefSig));
    else
        meta.figure_ref_sig = '';
    end
    setappdata(fig, 'section43_curve_meta', meta);
catch
end

end

function curve = fill_leading_nan_(curve)
% 用第一个有效值（非NaN）回填前面的NaN
% 例如：[NaN, NaN, 100, 90, NaN] -> [100, 100, 100, 90, NaN]
% 只处理开头的连续NaN，中间和末尾的NaN保留
firstValid = find(~isnan(curve), 1, 'first');
if ~isempty(firstValid) && firstValid > 1
    curve(1:firstValid-1) = curve(firstValid);
end
end

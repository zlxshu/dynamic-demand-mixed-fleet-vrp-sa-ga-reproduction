function plot_sens(tbl, titleCN, outPngPath)
% =========================================================================
% [模块] plot_sens
%  功能: 绘制灵敏度分析曲线
%  论文对应: 第5章 灵敏度分析
%  说明: 模块化版本.
% =========================================================================
incPct = [];
finalCost = [];

if istable(tbl)
    if any(strcmp(tbl.Properties.VariableNames,'incPct'))
        incPct = tbl.incPct;
    elseif any(strcmp(tbl.Properties.VariableNames,'inc'))
        incPct = tbl.inc;
    end
    if any(strcmp(tbl.Properties.VariableNames,'finalCost'))
        finalCost = tbl.finalCost;
    elseif any(strcmp(tbl.Properties.VariableNames,'totalCost'))
        finalCost = tbl.totalCost;
    end
elseif isstruct(tbl)
    if isfield(tbl,'incPct')
        incPct = [tbl.incPct];
    elseif isfield(tbl,'inc')
        incPct = [tbl.inc];
    end
    if isfield(tbl,'finalCost')
        finalCost = [tbl.finalCost];
    elseif isfield(tbl,'totalCost')
        finalCost = [tbl.totalCost];
    end
end

if isempty(incPct) || isempty(finalCost)
    error('plot_sens:invalidInput', 'tbl 必须包含 incPct/finalCost 或 inc/totalCost 字段。');
end

fig = figure('Color','w');
hold on; box on; grid on;

plot(incPct, finalCost, '-o', 'LineWidth', 1.5, 'MarkerSize', 8);

xlabel('变化率 (%)');
ylabel('总成本 (元)');
if nargin >= 2 && ~isempty(titleCN)
    title(titleCN, 'FontSize', 14, 'FontWeight', 'bold');
end

% 标注每个点的 y 值（两位小数）
for i = 1:numel(incPct)
    text(incPct(i), finalCost(i), sprintf('%.2f', finalCost(i)), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 9);
end

if nargin >= 3 && ~isempty(outPngPath)
    try
        if exist('exportgraphics','file')
            exportgraphics(fig, outPngPath, 'Resolution', 300);
        else
            print(fig, outPngPath, '-dpng', '-r300');
        end
    catch ME
        warning('plot_sens:saveFailed', '%s', ME.message);
    end
    try
        close(fig);
    catch
    end
end
end

function out = render_table_grid_43(tbl, highlightMask, outBasePath, cfg)
% 修改日志
% - v1 2026-02-06: 新增将 MATLAB table 渲染为可高亮的 PDF/PNG（矢量/位图）导出，用于 section_43 表4.3 一致性校验与报告截图。
%
% render_table_grid_43
% - 用纯 MATLAB 绘制网格 + 文本的方式生成表格渲染（支持逐单元格背景色与加粗）。
%
% 输入:
%   tbl           : MATLAB table（行列均为标量单元格内容）
%   highlightMask : logical(height(tbl), width(tbl))，true 表示该单元格需要高亮
%   outBasePath   : 不含扩展名的输出路径，例如 ...\tables\Table43_render
%   cfg           : 可选结构体
%
% 输出:
%   out.pdfPath / out.pngPath / out.figHandle

if nargin < 2 || isempty(highlightMask)
    highlightMask = false(height(tbl), width(tbl));
end
if nargin < 3 || isempty(outBasePath)
    error('render_table_grid_43:badOutPath', 'outBasePath is required');
end
if nargin < 4 || isempty(cfg)
    cfg = struct();
end
if ~isfield(cfg,'fontName') || isempty(cfg.fontName), cfg.fontName = 'Times New Roman'; end
if ~isfield(cfg,'fontSize') || isempty(cfg.fontSize), cfg.fontSize = 10; end
if ~isfield(cfg,'highlightColor') || isempty(cfg.highlightColor), cfg.highlightColor = [1, 0.9216, 0.2314]; end % #FFEB3B
if ~isfield(cfg,'gridColor') || isempty(cfg.gridColor), cfg.gridColor = [0 0 0]; end
if ~isfield(cfg,'textColor') || isempty(cfg.textColor), cfg.textColor = [0 0 0]; end
if ~isfield(cfg,'dpi') || isempty(cfg.dpi), cfg.dpi = 300; end
if ~isfield(cfg,'colWidths') || isempty(cfg.colWidths), cfg.colWidths = []; end
if ~isfield(cfg,'rowHeight') || isempty(cfg.rowHeight), cfg.rowHeight = 1; end
if ~isfield(cfg,'numFormat') || isempty(cfg.numFormat), cfg.numFormat = '%.2f'; end
if ~isfield(cfg,'nanText') || isempty(cfg.nanText), cfg.nanText = ''; end

tbl = tbl;
nRow = height(tbl) + 1;
nCol = width(tbl);

if ~isequal(size(highlightMask), [height(tbl), nCol])
    error('render_table_grid_43:badMask', 'highlightMask size mismatch');
end

if isempty(cfg.colWidths)
    cfg.colWidths = ones(1, nCol);
    if any(strcmp(tbl.Properties.VariableNames, 'Run'))
        cfg.colWidths(1) = 0.8;
    end
end

colW = cfg.colWidths(:).';
colW = colW / sum(colW);
rowH = cfg.rowHeight;

fig = figure('Color','w', 'Units','pixels', 'Position',[80 80 1200 420], 'Visible','off');
ax = axes(fig);
axis(ax, 'off');
hold(ax, 'on');

xEdges = [0, cumsum(colW)];
yEdges = [0, cumsum(ones(1, nRow) * rowH)];
W = xEdges(end);
H = yEdges(end);

set(ax, 'XLim', [0 W], 'YLim', [0 H], 'YDir', 'reverse');

for r = 1:nRow
    for c = 1:nCol
        x0 = xEdges(c);
        y0 = yEdges(r);
        w = xEdges(c+1) - xEdges(c);
        h = rowH;

        face = [1 1 1];
        bold = false;
        if r >= 2
            if highlightMask(r-1, c)
                face = cfg.highlightColor;
                bold = true;
            end
        end

        rectangle(ax, 'Position', [x0 y0 w h], 'FaceColor', face, 'EdgeColor', cfg.gridColor, 'LineWidth', 0.8);

        if r == 1
            txt = tbl.Properties.VariableNames{c};
            fw = 'bold';
        else
            v = tbl{r-1, c};
            txt = cell_value_to_text_(v, cfg.numFormat, cfg.nanText);
            fw = ternary_(bold, 'bold', 'normal');
        end

        text(ax, x0 + 0.5*w, y0 + 0.55*h, txt, ...
            'HorizontalAlignment','center', 'VerticalAlignment','middle', ...
            'FontName', cfg.fontName, 'FontSize', cfg.fontSize, ...
            'FontWeight', fw, 'Color', cfg.textColor, 'Interpreter','none');
    end
end

drawnow;

pdfPath = [outBasePath '.pdf'];
pngPath = [outBasePath '.png'];

try
    exportgraphics(fig, pdfPath, 'ContentType','vector');
catch
    try
        print(fig, pdfPath, '-dpdf');
    catch
    end
end

try
    exportgraphics(fig, pngPath, 'Resolution', cfg.dpi);
catch
    try
        print(fig, pngPath, '-dpng', sprintf('-r%d', round(cfg.dpi)));
    catch
    end
end

out = struct();
out.pdfPath = pdfPath;
out.pngPath = pngPath;
out.figHandle = fig;
end

function s = cell_value_to_text_(v, numFmt, nanText)
try
    if iscell(v)
        if isempty(v)
            s = '';
            return;
        end
        v = v{1};
    end
    if ismissing(v)
        s = '';
        return;
    end
    if isstring(v) || ischar(v)
        s = char(string(v));
        return;
    end
    if isnumeric(v) || islogical(v)
        x = double(v);
        if isempty(x) || ~isfinite(x)
            s = nanText;
            return;
        end
        s = sprintf(numFmt, x);
        return;
    end
    s = char(string(v));
catch
    s = '';
end
end

function v = ternary_(cond, a, b)
if cond
    v = a;
else
    v = b;
end
end


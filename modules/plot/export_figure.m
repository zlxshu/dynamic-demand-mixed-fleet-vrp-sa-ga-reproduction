function export_figure(fig, outPngPath, dpi, cfg)
% 修改日志
% - v1 2026-01-21: 新增统一导出 export_figure(fig,outPngPath,dpi)。
% - v1 2026-01-21: 运行时保留工具栏；导出前临时隐藏 axes Toolbar，并可选清空 xlabel/ylabel（导出图无轴标签）。
% - v2 2026-01-21: 增加 cfg.exportNoAxisLabels（默认 true）。
% - v3 2026-01-21: 修复 yyaxis 导出仍残留轴标签：导出时同时清空左右 YAxis(k).Label.String。

if nargin < 1 || isempty(fig)
    fig = gcf;
end
if nargin < 2 || isempty(outPngPath)
    error('export_figure:missingPath', 'outPngPath 不能为空');
end
if nargin < 3 || isempty(dpi)
    dpi = 300;
end
if nargin < 4 || isempty(cfg)
    cfg = struct();
end
if ~isfield(cfg, 'exportNoAxisLabels')
    cfg.exportNoAxisLabels = true;
end
if ~isfield(cfg, 'exportNoTitle')
    cfg.exportNoTitle = false;
end

outPngPath = char(string(outPngPath));
ensure_dir(fileparts(outPngPath));

% 固定白底
try
    fig.Color = 'w';
catch
end

axList = findall(fig, 'Type', 'axes');
axList = axList(:).';

% 记录并临时隐藏 axes toolbar（避免 UI 进入导出图）
oldTbVis = cell(numel(axList), 1);
oldXLab = cell(numel(axList), 1);
oldYLab = cell(numel(axList), 1);
oldYAxisLabels = cell(numel(axList), 1); % support yyaxis (left/right)
oldTitle = cell(numel(axList), 1);
oldSubtitle = cell(numel(axList), 1);
for i = 1:numel(axList)
    a = axList(i);
    oldTbVis{i} = '';
    try
        if isprop(a, 'Toolbar') && ~isempty(a.Toolbar) && isprop(a.Toolbar,'Visible')
            oldTbVis{i} = a.Toolbar.Visible;
            a.Toolbar.Visible = 'off';
        end
    catch
    end

    if cfg.exportNoAxisLabels
        % X label
        try
            oldXLab{i} = a.XLabel.String;
            a.XLabel.String = '';
        catch
            oldXLab{i} = '';
        end

        % Y label (active side)
        try
            oldYLab{i} = a.YLabel.String;
            a.YLabel.String = '';
        catch
            oldYLab{i} = '';
        end

        % yyaxis left/right labels
        try
            yl = {};
            if isprop(a, 'YAxis') && numel(a.YAxis) >= 1
                for k = 1:numel(a.YAxis)
                    try
                        yl{k} = a.YAxis(k).Label.String; %#ok<AGROW>
                        a.YAxis(k).Label.String = '';
                    catch
                        yl{k} = ''; %#ok<AGROW>
                    end
                end
            end
            oldYAxisLabels{i} = yl;
        catch
            oldYAxisLabels{i} = {};
        end
    else
        oldXLab{i} = '';
        oldYLab{i} = '';
        oldYAxisLabels{i} = {};
    end

    if cfg.exportNoTitle
        try
            oldTitle{i} = a.Title.String;
            a.Title.String = '';
        catch
            oldTitle{i} = '';
        end
        try
            if isprop(a, 'Subtitle') && ~isempty(a.Subtitle)
                oldSubtitle{i} = a.Subtitle.String;
                a.Subtitle.String = '';
            else
                oldSubtitle{i} = '';
            end
        catch
            oldSubtitle{i} = '';
        end
    else
        oldTitle{i} = '';
        oldSubtitle{i} = '';
    end
end

try
    if exist('exportgraphics', 'file') == 2
        exportgraphics(fig, outPngPath, 'Resolution', dpi);
    else
        % fallback
        print(fig, outPngPath, '-dpng', sprintf('-r%d', dpi));
    end
catch ME
    warning('export_figure:exportFailed', '%s', ME.message);
end

% 恢复 UI 状态
for i = 1:numel(axList)
    a = axList(i);
    try
        if ~isempty(oldTbVis{i}) && isprop(a, 'Toolbar') && ~isempty(a.Toolbar)
            a.Toolbar.Visible = oldTbVis{i};
        end
    catch
    end
    if cfg.exportNoAxisLabels
        try, a.XLabel.String = oldXLab{i}; catch, end
        try, a.YLabel.String = oldYLab{i}; catch, end

        try
            yl = oldYAxisLabels{i};
            if isprop(a, 'YAxis') && numel(a.YAxis) >= 1 && iscell(yl)
                for k = 1:min(numel(a.YAxis), numel(yl))
                    try, a.YAxis(k).Label.String = yl{k}; catch, end
                end
            end
        catch
        end
    end

    if cfg.exportNoTitle
        try, a.Title.String = oldTitle{i}; catch, end
        try
            if isprop(a, 'Subtitle') && ~isempty(a.Subtitle)
                a.Subtitle.String = oldSubtitle{i};
            end
        catch
        end
    end
end
end

function apply_plot_style(fig, ax, styleName)
% 修改日志
% - v1 2026-01-21: 新增统一绘图样式 apply_plot_style(fig,ax,styleName)；所有图复用同一排版口径。
% - v1 2026-01-21: sensitivity 风格固定 xlim/xticks；统一字体/字号/线宽/网格/指数显示等。
% - v2 2026-01-21: 设置 groot 默认字体（优先微软雅黑/黑体），确保中文图例/标注不乱码。

    if nargin < 1 || isempty(fig)
        fig = gcf;
    end
    if nargin < 2 || isempty(ax)
        ax = findall(fig, 'Type', 'axes');
    end
    if nargin < 3 || isempty(styleName)
        styleName = 'default';
    end

    styleName = char(string(styleName));

    % 字体：优先常见中文字体（Windows/macOS），fallback 系统默认
    fontName = '';
    try
        f = listfonts();
        if any(strcmpi(f, 'Microsoft YaHei'))
            fontName = 'Microsoft YaHei';
        elseif any(strcmpi(f, 'SimHei'))
            fontName = 'SimHei';
        elseif any(strcmpi(f, 'PingFang SC'))
            fontName = 'PingFang SC';
        elseif any(strcmpi(f, 'Heiti SC'))
            fontName = 'Heiti SC';
        elseif any(strcmpi(f, 'STHeiti'))
            fontName = 'STHeiti';
        elseif any(strcmpi(f, 'Songti SC'))
            fontName = 'Songti SC';
        elseif any(strcmpi(f, 'Arial Unicode MS'))
            fontName = 'Arial Unicode MS';
        end
    catch
    end

    % 全局默认字体（避免 legend/text 未显式指定时中文乱码）
    persistent didSetDefaults;
    if isempty(didSetDefaults) || ~didSetDefaults
        try
            if ~isempty(fontName)
                set(groot, 'defaultAxesFontName', fontName);
                set(groot, 'defaultTextFontName', fontName);
            end
        catch
        end
        didSetDefaults = true;
    end

    % Figure defaults
    try
        set(fig, 'Color', 'w');
    catch
    end

    ax = ax(:).';
    for i = 1:numel(ax)
        a = ax(i);
        try
            set(a, 'Box', 'on', 'TickDir', 'out');
            grid(a, 'on');
            a.GridAlpha = 0.15;
            a.FontSize = 12;
            if ~isempty(fontName)
                a.FontName = fontName;
            end
            % 避免 ×10^k 影响可读性
            try, a.YAxis.Exponent = 0; catch, end
            try, a.XAxis.Exponent = 0; catch, end
        catch
        end

        % Title
        try
            if isprop(a, 'Title') && isprop(a.Title, 'FontSize')
                a.Title.FontSize = 16;
                if ~isempty(fontName)
                    a.Title.FontName = fontName;
                end
            end
        catch
        end

        % Lines
        try
            ln = findall(a, 'Type', 'line');
            for k = 1:numel(ln)
                try, ln(k).LineWidth = 2.0; catch, end
                try, ln(k).MarkerSize = 7; catch, end
            end
        catch
        end

        try
            lgList = findall(fig, 'Type', 'legend');
            for li = 1:numel(lgList)
                lg = lgList(li);
                if ~isvalid(lg)
                    continue;
                end
                lg.FontSize = 11;
                try lg.Interpreter = 'none'; catch, end
                if ~isempty(fontName)
                    lg.FontName = fontName;
                end
                nStr = 0;
                try nStr = numel(lg.String); catch, nStr = 0; end
                if nStr >= 6
                    try lg.NumColumns = 2; catch, end
                    try lg.Location = 'southoutside'; catch, end
                else
                    try lg.Location = 'best'; catch, end
                end
            end
        catch
        end

        % sensitivity 固定刻度
        if contains(lower(styleName), 'sensitivity')
            try
                xlim(a, [0 100]);
                xticks(a, 0:20:100);
            catch
            end
        end
    end
end

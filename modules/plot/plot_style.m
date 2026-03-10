function plot_style(fig, ax, styleName)
% 修改日志
% - v1 2026-01-21: 兼容入口 plot_style(fig,ax,styleName) -> apply_plot_style；避免调用方记错文件名。
% - v2 2026-01-21: 强制设置默认中文字体（groot），避免图例/标注中文乱码。

    try
        f = listfonts();
        if any(strcmpi(f, 'Microsoft YaHei'))
            set(groot, 'defaultAxesFontName', 'Microsoft YaHei');
            set(groot, 'defaultTextFontName', 'Microsoft YaHei');
        elseif any(strcmpi(f, 'SimHei'))
            set(groot, 'defaultAxesFontName', 'SimHei');
            set(groot, 'defaultTextFontName', 'SimHei');
        end
    catch
    end

    if nargin < 3 || isempty(styleName)
        styleName = 'default';
    end
    apply_plot_style(fig, ax, styleName);
end


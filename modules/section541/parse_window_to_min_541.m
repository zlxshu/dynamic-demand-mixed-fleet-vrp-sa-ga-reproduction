function win = parse_window_to_min_541(x)
% parse_window_to_min_541 - 解析窗口 [t0,tEnd]（分钟）
% 支持：
% - 数值向量： [480 600]
% - 字符串： '480-600' / '08:00-10:00' / '480–600'
% 修改日志
% - v1 2026-01-24: 初版。
% - v2 2026-01-26: 支持方括号/中文括号/全角括号包裹的时间窗字符串。
% - v3 2026-01-27: 修复正则反斜杠转义，保证窗口分隔解析。

    win = [];
    if nargin < 1
        return;
    end

    if iscell(x) && numel(x) == 1
        x = x{1};
    end

    if isnumeric(x) && numel(x) == 2
        v = double(x(:).');
        if all(isfinite(v))
            win = v;
            return;
        end
    end

    if ~(ischar(x) || isstring(x))
        return;
    end

    s = char(string(x));
    s = strtrim(s);
    if isempty(s)
        return;
    end
    % 去除常见括号
    s = strrep(s, '[', '');
    s = strrep(s, ']', '');
    s = strrep(s, '【', '');
    s = strrep(s, '】', '');
    s = strrep(s, '（', '');
    s = strrep(s, '）', '');
    s = strrep(s, '(', '');
    s = strrep(s, ')', '');
    s = strtrim(s);
    s = strrep(s, '–', '-');
    s = strrep(s, '—', '-');
    s = strrep(s, '－', '-');
    s = strrep(s, '～', '-');
    s = strrep(s, '至', '-');

    parts = regexp(s, '\s*-\s*', 'split');
    if numel(parts) < 2
        return;
    end

    t0 = parse_time_to_min_541(parts{1});
    t1 = parse_time_to_min_541(parts{2});
    if isfinite(t0) && isfinite(t1)
        win = [t0 t1];
    end
end

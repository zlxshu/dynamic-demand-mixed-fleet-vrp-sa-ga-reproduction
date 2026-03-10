function tMin = parse_time_to_min_541(x)
% parse_time_to_min_541 - 将时间解析为“分钟（0~1440）”口径
% 支持：
% - 数值：480 表示 480min；0~1 视为 Excel/日分数
% - 字符串：'08:30' / '480' / '480.0'
% - datetime/duration
% 修改日志
% - v2 2026-01-27: 修正正则以兼容 MATLAB：用 [0-9] 替代 \\d，避免 HH:MM 解析失败。
% - v3 2026-01-27: 修复正则反斜杠转义，保证 HH:MM 可解析。

    tMin = NaN;

    if nargin < 1
        return;
    end

    if iscell(x) && numel(x) == 1
        x = x{1};
    end

    % datetime / duration
    try
        if isa(x, 'datetime')
            x = timeofday(x);
        end
        if isa(x, 'duration')
            tMin = minutes(x);
            return;
        end
    catch
    end

    % numeric
    if isnumeric(x) && isscalar(x)
        if ~isfinite(x)
            return;
        end
        v = double(x);
        if v >= 0 && v <= 1
            % Excel time fraction of day
            tMin = v * 24 * 60;
            return;
        end
        if v > 0 && v <= 24 && abs(v - round(v)) < 1e-12
            % likely hour-of-day
            tMin = v * 60;
            return;
        end
        tMin = v;
        return;
    end

    % string/char
    if isstring(x) || ischar(x)
        s = char(string(x));
        s = strtrim(s);
        if isempty(s)
            return;
        end
        s = strrep(s, '：', ':');
        s = strrep(s, '点', ':');
        s = strrep(s, '分', '');

        % hh:mm
        m = regexp(s, '^(?<h>[0-9]{1,2})\s*:\s*(?<m>[0-9]{1,2})$', 'names');
        if ~isempty(m)
            hh = str2double(m.h);
            mm = str2double(m.m);
            if isfinite(hh) && isfinite(mm)
                tMin = 60 * hh + mm;
                return;
            end
        end

        % plain number
        v = str2double(s);
        if isfinite(v)
            tMin = v;
            return;
        end
    end
end

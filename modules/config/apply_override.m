function ctx2 = apply_override(ctx, override)
% 修改日志
% - v1 2026-01-21: 新增 apply_override(ctx, override)；仅做局部覆盖并保持基准 ctx 不被污染。
% - v1 2026-01-21: 默认禁止引入新字段，避免“静默拼写错误”导致的口径漂移。

    if nargin < 2 || isempty(override)
        ctx2 = ctx;
        return;
    end
    if ~isstruct(override)
        error('apply_override:invalidOverride', 'override 必须是 struct');
    end

    ctx2 = ctx;
    ctx2 = merge_struct_strict_(ctx2, override, '');
end

function base = merge_struct_strict_(base, ov, prefix)
fn = fieldnames(ov);
for i = 1:numel(fn)
    f = fn{i};
    path = f;
    if ~isempty(prefix)
        path = [prefix '.' f];
    end
    if ~isfield(base, f)
        error('apply_override:unknownField', 'override 字段不存在: %s', path);
    end
    if isstruct(ov.(f))
        if ~isstruct(base.(f))
            error('apply_override:typeMismatch', 'override 类型不匹配(期望 struct): %s', path);
        end
        base.(f) = merge_struct_strict_(base.(f), ov.(f), path);
    else
        base.(f) = ov.(f);
    end
end
end



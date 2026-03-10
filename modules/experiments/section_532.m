function varargout = section_532(varargin)
% 修改日志
% - v1 2026-01-21: section_532 改为兼容入口；统一转发到 run_section_532(ctx)。
% - v1 2026-01-21: 修复旧缓存跨参数污染：签名校验由 cache_load_best 实现，旧 CACHE/ 目录仅允许忽略。

ctx = get_config();
out = run_section_532(ctx);

if nargout > 0
    varargout{1} = out;
end
end


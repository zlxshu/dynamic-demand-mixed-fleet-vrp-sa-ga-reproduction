function varargout = section_531(varargin)
% 修改日志
% - v1 2026-01-21: section_531 改为兼容入口；统一转发到 run_section_531(ctx)。
% - v1 2026-01-21: 禁止在 section 内硬编码参数/路径/缓存；统一由 get_config/output_paths/build_signature 管线接管。

ctx = get_config();
out = run_section_531(ctx);

if nargout > 0
    varargout{1} = out;
end
end


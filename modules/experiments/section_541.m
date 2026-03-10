function varargout = section_541(varargin)
% 修改日志
% - v1 2026-01-24: section_541 兼容入口；统一转发到 run_section_541(ctx)（推荐仍从 run_modes 进入）。

ctx = get_config(); %#ok<NASGU>
out = run_section_541(ctx);

if nargout > 0
    varargout{1} = out;
end
end


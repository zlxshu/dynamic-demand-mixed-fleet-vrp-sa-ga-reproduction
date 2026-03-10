function varargout = section_533(varargin)
% 修改日志
% - v1 2026-01-21: section_533 改为兼容入口；统一转发到 run_section_533(ctx)。
% - v1 2026-01-21: 充电速率敏感性图升级由 run_section_533 实现（三层信息+脚注+统一导出）。

ctx = get_config();
out = run_section_533(ctx);

if nargout > 0
    varargout{1} = out;
end
end


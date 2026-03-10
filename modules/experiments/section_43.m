function varargout = section_43(varargin)
% 修改日志
% - v1 2026-02-03: 新增 section_43；论文4.3节算法检验入口包装。
%
% section_43 - 论文4.3节算法检验（图4.8 + 表4.3）
%
% 说明：
% - 本函数是 section_43 的统一入口，与其他 section 保持一致的调用接口。
% - 从 get_config 获取配置，调用 run_section_43 执行主逻辑。
% - 所有参数通过 section43_constants 硬校验，不允许外部覆盖论文规定参数。

ctx = get_config();
out = run_section_43(ctx);

if nargout > 0
    varargout{1} = out;
end

end

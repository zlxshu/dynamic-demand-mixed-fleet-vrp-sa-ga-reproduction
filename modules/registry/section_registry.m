function registry = section_registry()
% 修改日志
% - v1 2026-01-21: 新增 section_registry；未来新增 section 只需注册函数句柄即可自动继承统一管线。
% - v2 2026-01-24: 注册 section_541（5.4.1 动态需求下车辆组合与调度 DVRP）。
% - v3 2026-02-03: 预留 section_43（论文 4.3 节，待开发）。
% - v4 2026-02-03: 实现 section_43（论文 4.3 节算法检验：GSAA vs GA vs SA）。

registry = containers.Map();

% section_43（论文 4.3 节算法检验）
registry('section_43') = @run_section_43;

registry('section_531') = @run_section_531;
registry('section_532') = @run_section_532;
registry('section_533') = @run_section_533;
registry('section_541') = @run_section_541;
registry('section_542') = @run_section_542;
end

% section_43 占位函数已移除（v4 2026-02-03 实现）

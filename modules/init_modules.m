function init_modules()
% =========================================================================
% [模块] init_modules
%  作用: 初始化模块路径，确保 modules 下所有子目录可访问
%  说明: 建议所有入口先调用此函数，不要在外部直接 addpath(genpath('modules'))
% =========================================================================

% 获取 modules 目录绝对路径
thisFile = mfilename('fullpath');
modulesDir = fileparts(thisFile);

% 将 modules 及其所有子目录加入 MATLAB 路径
addpath(genpath(modulesDir));

% 输出模块加载信息
fprintf('[模块化] 已加载 modules 目录及其子模块:\n');
fprintf('  - modules/utils: 工具函数\n');
fprintf('  - modules/operators: 算子模块\n');
fprintf('  - modules/core/fitness: 适应度计算\n');
fprintf('  - modules/core/repair: 染色体修复\n');
fprintf('  - modules/core/gsaa: GSAA 主循环\n');
fprintf('  - modules/cv_only: CV-only 增强\n');
fprintf('  - modules/visualization: 可视化绘图\n');
fprintf('  - modules/config: 配置与模式开关\n');
end

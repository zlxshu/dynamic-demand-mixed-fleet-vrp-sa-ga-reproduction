function init_modules()
% =========================================================================
% [模块] init_modules
%  功能: 初始化模块路径,确保所有子目录可访问
%  说明: 在主程序开头调用此函数,或直接使用 addpath(genpath('modules'))
% =========================================================================

% 获取 modules 目录的绝对路径
thisFile = mfilename('fullpath');
modulesDir = fileparts(thisFile);

% 添加所有子目录到 MATLAB 路径
addpath(genpath(modulesDir));

% 显示模块加载信息
fprintf('[模块化] 已加载 modules 目录及所有子模块:\n');
fprintf('  - modules/utils: 工具函数\n');
fprintf('  - modules/operators: 遗传算子\n');
fprintf('  - modules/core/fitness: 适应度评估\n');
fprintf('  - modules/core/repair: 染色体修复\n');
fprintf('  - modules/core/gsaa: GSAA主循环\n');
fprintf('  - modules/cv_only: CV-only增强\n');
fprintf('  - modules/visualization: 表格与绘图\n');
fprintf('  - modules/config: 配置与模式选择\n');
end

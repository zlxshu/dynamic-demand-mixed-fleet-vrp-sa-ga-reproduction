function run_main_modular()
% 修改日志
% - v2 2026-01-23: 禁用旧入口，强制使用 run_modes.m。
% =========================================================================
% [模块化主程序] run_main_modular - 简化版（已禁用）
% 说明:
% - 旧入口：仅保留历史代码，不得用于正式运行
% - 统一入口：run_modes.m
% =========================================================================

error('run_main_modular:disabled', ...
    ['run_main_modular 已禁用（旧入口）。请使用 run_modes.m 作为唯一入口：', ...
     '在 run_modes.m 里设置 RUN_MODE/RUN_MODE_MULTI/RUN_TAG/MODE_LABEL/RUN_PROFILE。']);
end
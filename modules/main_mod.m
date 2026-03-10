function main_mod()
% 修改日志
% - v2 2026-01-23: 禁用旧入口，强制使用 run_modes.m。
% =========================================================================
% [模块化主入口] main_mod
% 说明:
% - 保留 opt27 原始单文件: reproduce_section_5_3_1_actual_final_fixed10_opt27_gen97_modeswitch.m
% - 本文件为旧入口：仅保留历史代码，不得用于正式运行
% - 统一入口：run_modes.m
% =========================================================================

error('main_mod:disabled', ...
    ['main_mod 已禁用（旧入口）。请使用 run_modes.m 作为唯一入口：', ...
     '在 run_modes.m 里设置 RUN_MODE/RUN_MODE_MULTI/RUN_TAG/MODE_LABEL/RUN_PROFILE。']);
end

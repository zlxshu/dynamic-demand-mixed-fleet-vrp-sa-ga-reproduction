function main_mod()
% 修改日志
% - v2 2026-01-23: 禁用旧入口，强制使用 run_modes.m。
% =========================================================================
% [模块化入口占位] main_mod
% 说明:
% - 源于历史入口文件: reproduce_section_5_3_1_actual_final_fixed10_opt27_gen97_modeswitch.m
% - 本文件仅用于兼容历史调用，避免误用旧入口。
% - 统一入口: run_modes.m
% =========================================================================

error('main_mod:disabled', ...
    ['main_mod 已禁用（历史入口），请使用 run_modes.m 作为唯一入口；', ...
     '并在 run_modes.m 中配置 RUN_MODE/RUN_MODE_MULTI/RUN_TAG/MODE_LABEL/RUN_PROFILE。']);
end

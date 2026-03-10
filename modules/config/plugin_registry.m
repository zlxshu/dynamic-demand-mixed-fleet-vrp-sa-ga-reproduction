function plugins = plugin_registry()
% PLUGIN_REGISTRY - 插件注册表（支持动态扩展）
%
% 功能：集中管理所有可用插件/模块
% 优势：便于添加新功能，支持插件式架构
%
% 返回：结构体数组，包含所有注册的插件信息

    plugins = struct();
    
    % ========== 局部搜索插件 ==========
    plugins.local_search = struct();
    plugins.local_search.two_opt = @two_opt_within_routes_rs;
    plugins.local_search.or_opt = @or_opt_within_routes_rs;
    plugins.local_search.relocate = @relocate_longest_ev_to_cv;
    
    % ========== 遗传算子插件 ==========
    plugins.operators = struct();
    plugins.operators.selection = @roulette_selection_fast;
    plugins.operators.crossover = @crossover_OX_withCuts_fast;
    plugins.operators.mutation = @mutation_withCuts;
    
    % ========== 修复算子插件 ==========
    plugins.repair = struct();
    plugins.repair.deterministic = @repair_chromosome_deterministic;
    plugins.repair.all_constraints = @repair_all_constraints;
    plugins.repair.station_insertion = @repair_with_station_insertion;
    
    % ========== CV-only 专用插件 ==========
    plugins.cv_only = struct();
    plugins.cv_only.improve = @post_improve_cv_only;
    plugins.cv_only.two_opt = @cv_only_2opt_full;
    plugins.cv_only.cross = @cv_only_cross_improve;
    
    % ========== 如何添加新插件 ==========
    % 示例：添加自定义局部搜索算子
    % plugins.local_search.my_custom = @my_custom_operator;
    
end

function plugin = get_plugin(category, name)
% GET_PLUGIN - 获取指定插件
%
% 输入：
%   category - 插件类别（如 'local_search', 'operators'）
%   name - 插件名称（如 'two_opt', 'crossover'）
%
% 返回：函数句柄

    registry = plugin_registry();
    
    if isfield(registry, category) && isfield(registry.(category), name)
        plugin = registry.(category).(name);
    else
        error('插件不存在: %s.%s', category, name);
    end
end

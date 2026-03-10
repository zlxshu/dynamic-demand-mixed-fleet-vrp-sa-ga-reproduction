function result = example_new_module(input, G)
% EXAMPLE_NEW_MODULE - 新模块示例模板
%
% 这是一个模板文件，展示如何创建新模块
%
% 输入：
%   input - 输入数据
%   G - 全局配置结构体（替代 global G）
%
% 输出：
%   result - 处理结果
%
% 使用示例：
%   result = example_new_module(myData, G);
%
% 扩展说明：
%   1. 复制此文件并重命名
%   2. 修改函数名和功能实现
%   3. 在主代码中调用
%   4. （可选）在 plugin_registry.m 中注册

    % ========== 参数验证 ==========
    if nargin < 2
        error('需要提供 input 和 G 参数');
    end
    
    % ========== 功能实现 ==========
    % 在这里实现你的新功能
    % 注意：使用 G.xxx 访问配置，而不是 global G
    
    % 示例：访问配置
    if isfield(G, 'opt') && isfield(G.opt, 'enableEliteLS')
        enableLS = G.opt.enableEliteLS;
    else
        enableLS = false;
    end
    
    % 示例：处理输入
    result = input;  % 替换为实际处理逻辑
    
    % ========== 日志输出（可选） ==========
    if isfield(G, 'verbose') && G.verbose
        fprintf('[example_new_module] 处理完成\n');
    end
    
end

% ========== 辅助函数（可选） ==========
function helper_function()
    % 模块内部辅助函数
    % 注意：这些函数只在模块内部可见
end

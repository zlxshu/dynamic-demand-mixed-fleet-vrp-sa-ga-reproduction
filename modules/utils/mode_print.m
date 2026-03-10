function mode_print()
% MODE_PRINT - 打印当前模式信息
state = mode_state('get');
if isempty(state) || ~isfield(state,'key') || isempty(state.key)
    return;
end
fprintf('[MODE] current=%s | tag=%s | sub=%s\n', state.key, state.tag, state.subtag);
end

function state = mode_state(action, key, tag, subtag)
% MODE_STATE - 管理运行模式状态(共享持久变量)

persistent currentKey currentTag currentSubtag

if nargin < 1 || isempty(action)
    action = 'get';
end

switch lower(action)
    case 'init'
        currentKey = key;
        currentTag = tag;
        currentSubtag = subtag;
    case 'set_subtag'
        if nargin >= 4
            currentSubtag = subtag;
        end
    case 'clear'
        currentKey = '';
        currentTag = '';
        currentSubtag = '';
end

state = struct('key', currentKey, 'tag', currentTag, 'subtag', currentSubtag);
end

function [tag, subtag] = mode_autotags(key)
% MODE_AUTOTAGS - 根据 key 自动生成标签
switch key
    case '531'
        tag = '复现';
        subtag = '';
    case '532'
        tag = '自适应车队';
        subtag = '';
    case '533'
        tag = '灵敏度分析';
        subtag = '灵敏度分析';
    otherwise
        tag = '未命名模式';
        subtag = '';
end
end

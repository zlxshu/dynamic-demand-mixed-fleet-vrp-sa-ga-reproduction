function cv_only_print_diag(stats, tag)
% =========================================================================
% [模块] cv_only_print_diag
%  功能: 打印 CV-only 统计信息
%  论文对应: 实现层
%  说明: 模块化版本.
% =========================================================================
if nargin < 2 || isempty(tag)
    tag = '[CV-only diag]';
end
opLabel = { ...
    'twoOpt','2opt'; ...
    'exch21','2-1'; ...
    'exch12','1-2'; ...
    'swap22','2-2'; ...
    'kick','kick'; ...
    'lns','lns'; ...
    'chain','chain'};
for i = 1:size(opLabel,1)
    op = opLabel{i,1};
    lab = opLabel{i,2};
    if ~isfield(stats,'fail') || ~isfield(stats.fail, op)
        continue;
    end
    s = stats.fail.(op);
    fprintf('%s %s try=%d ok=%d dup=%d miss=%d cap=%d tw=%d inv=%d noImp=%d\n', ...
        tag, lab, s.try, s.ok, s.duplicate, s.missing, s.capacity, s.timewindow, s.invalid, s.noImprove);
end
end

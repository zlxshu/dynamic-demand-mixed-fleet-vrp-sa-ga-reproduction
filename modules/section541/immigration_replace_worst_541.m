function [Pop, fit, isFe] = immigration_replace_worst_541(Pop, fit, isFe, NP, n, K, G)
% =========================================================================
% [模块] immigration_replace_worst
%  功能: 随机移民:替换最差个体(保留当前最优)
%  论文对应: 实现层(多样性注入)
%  说明: 模块化版本,接受 G 参数而非 global.
% =========================================================================
% 修改日志
% - v541 2026-01-27: 从 core/gsaa 拷贝到 section541，仅供 section_541 使用；保持逻辑不变，仅改函数名（支持 FitnessFcn 由 G.fitnessFcn 提供）。
% - v2 2026-01-27: 支持自定义适应度函数句柄（从 G.fitnessFcn 读取，默认 strict penalty）。

nImm = max(1, round(NP * G.opt.immigrationRatio));
fitnessFcn = get_fitness_fcn_(G);

% 保护:不替换全局罚最优/严格可行最优(若存在)
[~, idxBestPen] = min(fit);
idxBestFea = [];
idxF = find(isFe);
if ~isempty(idxF)
    [~, kk] = min(fit(idxF));
    idxBestFea = idxF(kk);
end
protect = unique([idxBestPen; idxBestFea(:)]);

[~, ord] = sort(fit, 'descend'); % worst first
rep = [];
for t = 1:numel(ord)
    if ~ismember(ord(t), protect)
        rep(end+1,1) = ord(t); %#ok<AGROW>
        if numel(rep) >= nImm, break; end
    end
end
if isempty(rep), return; end

for j = 1:numel(rep)
    ii = rep(j);
    perm = randperm(n);
    cuts = sort(randperm(n-1, K-1));
    ch = [perm cuts];
    ch = repair_chromosome_deterministic(ch, n, K, G);
    if rand < 0.6
        ch = repair_all_constraints(ch, n, K, 1, G);
    end
    [fit(ii), isFe(ii), Pop(ii,:), ~] = fitnessFcn(ch, G);
end
end

function f = get_fitness_fcn_(G)
    f = @fitness_strict_penalty;
    try
        if isfield(G,'fitnessFcn') && isa(G.fitnessFcn,'function_handle')
            f = G.fitnessFcn;
        end
    catch
        f = @fitness_strict_penalty;
    end
end


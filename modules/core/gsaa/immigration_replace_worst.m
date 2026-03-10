function [Pop, fit, isFe] = immigration_replace_worst(Pop, fit, isFe, NP, n, K, G)
% =========================================================================
% [模块] immigration_replace_worst
%  功能: 随机移民:替换最差个体(保留当前最优)
%  论文对应: 实现层(多样性注入)
%  说明: 模块化版本,接受 G 参数而非 global.
% =========================================================================
% 修改日志
% - v3 2026-01-27: section_541 的 FitnessFcn 适配已迁移到 modules/section541/*_541.m；本文件保持通用实现（并统一为 UTF-8 编码）。

nImm = max(1, round(NP * G.opt.immigrationRatio));

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
    [fit(ii), isFe(ii), Pop(ii,:), ~] = fitness_strict_penalty(ch, G);
end
end

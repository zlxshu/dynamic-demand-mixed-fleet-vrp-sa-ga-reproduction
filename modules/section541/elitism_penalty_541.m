function [Xo, fxo, feaso] = elitism_penalty_541(X, fx, feas, Xn, fxn, feasn, Pe)
% 修改日志
% - v1 2026-01-30: 从 core 版本拷贝并修复索引 pick 为行向量，避免列向量索引导致全选的 BUG。
% - v2 2026-01-30: 移除 debug 日志（seed/feasible 复核已完成）。

N = size(X,1);
Ne = max(0, ceil(Pe*N));

Xa = [X; Xn];
fxa = [fx; fxn];
feasa = [feas; feasn];

eliteIdx = [];

idxFeas = find(feasa);
if ~isempty(idxFeas)
    [~, ord] = sort(fxa(idxFeas));
    eliteIdx = idxFeas(ord(1:min(Ne,numel(ord))));
end

restIdx = setdiff(1:numel(fxa), eliteIdx, 'stable');
[~, ord2] = sort(fxa(restIdx));
need = N - numel(eliteIdx);
restPick = restIdx(ord2);

if need > numel(restPick), need = numel(restPick); end
pick = [eliteIdx(:); restPick(1:need)];
pick = pick(1:N);
pick = pick(:).';  % 确保 pick 是行向量

Xo = Xa(pick,:);
fxo = fxa(pick);
feaso = feasa(pick);
end

function [Xo, fxo, feaso] = elitism_penalty(X, fx, feas, Xn, fxn, feasn, Pe)
% =========================================================================
% [模块] elitism_penalty
%  功能: 精英保留:合并父代与子代,按可行性+适应度选出下一代.
%  论文对应: 第4章 精英策略(若论文未写可关闭)
%  说明: 模块化版本,无global依赖.
% =========================================================================

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
restPick = restPick(:);

if need > numel(restPick), need = numel(restPick); end
pick = [eliteIdx(:); restPick(1:need)];
pick = pick(1:N);

Xo = Xa(pick,:);
fxo = fxa(pick);
feaso = feasa(pick);
end

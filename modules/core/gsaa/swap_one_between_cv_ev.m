function candCh = swap_one_between_cv_ev(ch, n, K, G, rs)
% =========================================================================
% [模块] swap_one_between_cv_ev
%  功能: 跨车交换:在CV与EV之间交换一个客户,促进结构重组.
%  论文对应: 实现层
%  说明: 模块化版本,接受 G 参数而非 global.
% =========================================================================

if G.nCV < 1 || G.nEV < 1 || K < 2
    candCh = ch;
    return;
end
perm = ch(1:n);
cuts = sort(ch(n+1:end));
cuts = max(1, min(n-1, cuts));
cuts = unique(cuts,'stable');
while numel(cuts) < (K-1)
    cand = randi(rs, [1,n-1]);
    if ~ismember(cand,cuts), cuts(end+1)=cand; cuts=sort(cuts); end
end
cuts = cuts(1:K-1);

bounds = [0 cuts n];

cv = randi(rs, [1, G.nCV]);
ev = randi(rs, [G.nCV+1, K]);

a1 = bounds(cv)+1; b1 = bounds(cv+1);
a2 = bounds(ev)+1; b2 = bounds(ev+1);

candPerm = perm;
if b1>=a1 && b2>=a2
    p1 = randi(rs, [a1,b1]);
    p2 = randi(rs, [a2,b2]);
    tmp = candPerm(p1); candPerm(p1)=candPerm(p2); candPerm(p2)=tmp;
end
candCh = [candPerm cuts];
end

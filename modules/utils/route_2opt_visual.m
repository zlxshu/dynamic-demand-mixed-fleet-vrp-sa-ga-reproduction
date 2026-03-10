function seq2 = route_2opt_visual(seq, G)
% route_2opt_visual - 绘图美化用 2-opt（不影响成本）
% 输入:
%   seq - 节点序列（含 0/站点）
%   G   - 结构体，需包含 coord
% 输出:
%   seq2 - 优化后的序列（仅视觉）

    if numel(seq) <= 4
        seq2 = seq; 
        return;
    end

    seq2 = seq;
    fixedStart = seq2(1);
    fixedEnd = seq2(end);
    mid = seq2(2:end-1);

    coords = G.coord;
    best = mid;
    bestLen = route_len([fixedStart best fixedEnd], coords);

    improved = true;
    iter = 0; 
    iterMax = 50;
    while improved && iter < iterMax
        improved = false;
        iter = iter + 1;
        for i=1:(numel(best)-2)
            for j=i+1:(numel(best)-1)
                cand = best;
                cand(i:j) = best(j:-1:i);
                L = route_len([fixedStart cand fixedEnd], coords);
                if L < bestLen - 1e-9
                    best = cand;
                    bestLen = L;
                    improved = true;
                end
            end
        end
    end

    seq2 = [fixedStart best fixedEnd];
end

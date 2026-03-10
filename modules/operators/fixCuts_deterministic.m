function cuts = fixCuts_deterministic(cuts, n, K)
% fixCuts_deterministic - 修复 cuts，确保合法且递增
% 与原脚本逻辑一致，用于交叉/变异后合法化。
%
% ????
% - v2 2026-01-31: ?? cuts ??????? K-1 ?????

    cuts = sort(cuts(:)');
    cuts = cuts(cuts>=1 & cuts <= n-1);

    % 去重并截断到 K-1 个
    cuts = unique(cuts,'stable');
    if numel(cuts) > (K-1)
        cuts = cuts(1:(K-1));
    end

    % 若数量不足，补齐等距 cuts
    if numel(cuts) < (K-1)
        need = (K-1) - numel(cuts);
        addCuts = round(linspace(1, n-1, need+2));
        addCuts = addCuts(2:end-1);
        cuts = sort(unique([cuts, addCuts]));
        if numel(cuts) > (K-1)
            cuts = cuts(1:(K-1));
        end
        if numel(cuts) < (K-1)
            pool = setdiff(1:(n-1), cuts, 'stable');
            addN = min(numel(pool), (K-1) - numel(cuts));
            if addN > 0
                cuts = [cuts, pool(1:addN)];
                cuts = sort(unique(cuts, 'stable'));
                if numel(cuts) > (K-1)
                    cuts = cuts(1:(K-1));
                end
            end
        end
    end
end

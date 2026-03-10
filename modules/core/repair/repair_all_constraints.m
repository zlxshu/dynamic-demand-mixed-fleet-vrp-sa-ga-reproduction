function ch2 = repair_all_constraints(ch, n, K, level, G)
% repair_all_constraints - 结构/时间窗/容量/EV长度启发式修复
% level=1: 轻量; level=2: 强修复（含时间窗切分）

    if nargin < 4, level = 1; end

    ch2 = repair_chromosome_deterministic(ch, G);

    perm = ch2(1:n);
    cuts = ch2(n+1:end);
    routes = split_perm_by_cuts_pub(perm, cuts, n, K);

    % 时间窗启发 (EDD)
    for k = 1:K
        if numel(routes{k}) <= 1, continue; end
        [~, idx] = sort(G.RT(routes{k}+1), 'ascend');
        routes{k} = routes{k}(idx);
    end

    % 容量均衡
    for k = 1:K
        while ~isempty(routes{k}) && sum(G.q(routes{k}+1)) > G.Qmax(k)
            if k == K
                break;
            end
            mv = routes{k}(end);
            routes{k}(end) = [];
            routes{k+1} = [mv, routes{k+1}];
        end
    end

    % 强修复: 时间窗切分
    if level >= 2
        for k = 1:(K-1)
            if isempty(routes{k}), continue; end
            latePos = first_late_position(routes{k}, k, G);
            if latePos > 0 && latePos <= numel(routes{k})
                tail = routes{k}(latePos:end);
                routes{k}(latePos:end) = [];
                routes{k+1} = [tail, routes{k+1}];
            end
        end
    end

    % EV 路线长度软限制
    avgLen = ceil(n / K);
    for k = (G.nCV+1):K
        while numel(routes{k}) > (avgLen + 2)
            mv = routes{k}(end);
            routes{k}(end) = [];
            if G.nCV > 0
                lens = cellfun(@numel, routes(1:G.nCV));
                [~, idx] = min(lens);
                routes{idx} = [routes{idx}, mv];
            else
                routes{1} = [routes{1}, mv];
            end
        end
    end

    % 编码回染色体
    [perm2, cuts2] = merge_routes_to_perm_pub(routes, n, K);
    ch2 = [perm2 cuts2];
    ch2 = repair_chromosome_deterministic(ch2, G);
end

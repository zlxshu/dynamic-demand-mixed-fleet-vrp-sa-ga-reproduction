function Xc = crossover_OX_withCuts_fast(X, Pc, n, K)
% crossover_OX_withCuts_fast - OX/CX 交叉（含 cuts 修复）
% 完全与原脚本一致，含子代生成与 cuts 修复。

    N = size(X,1);
    Xc = X;

    for i = 1:2:N-1
        p1 = X(i,:); p2 = X(i+1,:);
        if rand < Pc
            c1 = cx_child_fast(p1(1:n), p2(1:n), n);
            c2 = cx_child_fast(p2(1:n), p1(1:n), n);

            % cuts 继承并修复
            cuts1 = fixCuts_deterministic(p1(n+1:end), n, K);
            cuts2 = fixCuts_deterministic(p2(n+1:end), n, K);

            Xc(i,:)   = [c1 cuts1];
            Xc(i+1,:) = [c2 cuts2];
        end
    end
end

function child = cx_child_fast(p1, p2, n)
% Cycle Crossover (CX) for permutations

    child = zeros(1,n);
    assigned = false(1,n);

    while any(~assigned)
        startPos = find(~assigned, 1, 'first');
        pos = startPos;
        while ~assigned(pos)
            child(pos) = p1(pos);
            assigned(pos) = true;

            val = p2(pos);
            pos = find(p1 == val, 1);
            if isempty(pos)
                break;
            end
        end
    end

    % 未填充位置用 p2
    mask = (child == 0);
    child(mask) = p2(mask);

    % 防呆:确保仍是排列
    if numel(unique(child)) ~= n
        child = p2;
    end
end

function child = ox_child_fast(parentA, parentB, a, b, n) %#ok<DEFNU>
% ox_child_fast - OX 子代生成（保留以便独立复用）

    child = zeros(1,n);
    child(a:b) = parentA(a:b);
    used = false(1,n);
    used(child(a:b)) = true;

    pos = b+1; if pos>n, pos=1; end
    for t = 1:n
        idxB = mod(b + t - 1, n) + 1;
        valB = parentB(idxB);
        if ~used(valB)
            child(pos) = valB;
            used(valB) = true;
            pos = pos + 1;
            if pos>n, pos=1; end
        end
    end
end


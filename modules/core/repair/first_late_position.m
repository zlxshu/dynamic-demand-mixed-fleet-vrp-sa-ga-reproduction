function pos = first_late_position(route, k, G)
% first_late_position - 返回路径中第一个违反 RT 的位置
    pos = 0;
    t = 0;
    cur = 0;
    for i = 1:numel(route)
        nxt = route(i);
        d = G.D(cur+1, nxt+1);
        t = t + d / G.Speed(k);
        if t > G.RT(nxt+1)
            pos = i;
            return;
        end
        if t < G.LT(nxt+1), t = G.LT(nxt+1); end
        t = t + G.ST;
        cur = nxt;
    end
end

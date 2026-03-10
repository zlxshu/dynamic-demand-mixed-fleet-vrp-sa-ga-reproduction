function detail2 = remap_detail_station_nodes_541(detail, nOld, nNew, E)
% remap_detail_station_nodes_541 - 当客户数 n 改变时，平移“充电站节点编号”
% 规则：
% - 旧站点编号：nOld+1 .. nOld+E
% - 新站点编号：nNew+1 .. nNew+E
% - 平移量：delta = nNew - nOld
%
% 注意：客户节点（1..nOld）保持不变；仅平移站点节点。

    detail2 = detail;
    delta = nNew - nOld;
    if delta == 0
        return;
    end

    for k = 1:numel(detail2)
        if ~isfield(detail2(k),'route') || isempty(detail2(k).route)
            continue;
        end
        r = detail2(k).route(:).';
        mask = (r >= (nOld+1)) & (r <= (nOld+E));
        r(mask) = r(mask) + delta;
        detail2(k).route = r;
    end
end


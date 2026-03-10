function state = build_state_at_time_541(tNow, planPrev, timelinePrev, cfg)
% 修改日志
% - v3 2026-01-27: 支持“未派车车辆”长期保持在库可用（route 无客户时不再被判定为 done），避免后续更新无法再派车。
% - v4 2026-01-31: 增加 5 车排查日志（debug）。
% build_state_at_time_541 - 在更新时刻构建车辆状态与冻结/待配送切分
% 关键口径（论文图示精神）：
% - 若车辆正在驶向下一节点：当前在途弧段 + 其目的节点 视为“正在配送段”（冻结）
% - 仅允许重排“目的节点之后”的待配送序列
% 修改日志
% - v1 2026-01-24: 初版：基于 timelinePrev.steps/visits 构建冻结/待配送切分。
% - v2 2026-01-25: servedOrStarted 口径改为 serviceStart < tNow（严格小于），用于取消/变更失败边界判定。

    if nargin < 4, cfg = struct(); end %#ok<NASGU>

    state = struct();
    state.tNow = tNow;
    state.vehicles = struct([]);
    state.servedCustomers = [];
    state.servedOrStartedCustomers = [];
    state.frozenCustomers = [];
    state.customerServiceStartMin = [];
    state.customerServiceEndMin = [];

    if isempty(timelinePrev) || ~isfield(timelinePrev,'vehicles')
        return;
    end

    servedAll = [];
    servedOrStartedAll = [];
    frozenAll = [];

    % 便于 apply_event_batch_541 直接查询（若 timelinePrev 已包含则直接复用）
    try
        if isfield(timelinePrev,'customerServiceStartMin')
            state.customerServiceStartMin = timelinePrev.customerServiceStartMin;
        end
        if isfield(timelinePrev,'customerServiceEndMin')
            state.customerServiceEndMin = timelinePrev.customerServiceEndMin;
        end
    catch
    end

    for k = 1:numel(timelinePrev.vehicles)
        v = timelinePrev.vehicles(k);
        route = v.route(:).';
        if isempty(route)
            route = [0 0];
        end

        hasCustomer = false;
        try
            if isfield(v,'visits') && ~isempty(v.visits)
                hasCustomer = any([v.visits.isCustomer]);
            end
        catch
            hasCustomer = false;
        end

        % 默认：未开始
        phase = 'not_started';
        stepIdx = NaN;
        curFrom = 0;
        curTo = 0;
        curNode = 0;
        frozenIdx = 1;
        batNow = NaN;

        % servedCompleted（已完成服务） / servedOrStarted（已开始服务，含已完成）
        servedCompleted = [];
        servedOrStarted = [];
        try
            for i = 1:numel(v.visits)
                vi = v.visits(i);
                if ~vi.isCustomer
                    continue;
                end
                % 已开始服务：严格小于 tNow（边界按论文口径）
                if isfinite(vi.tServiceStartMin) && (vi.tServiceStartMin < (tNow - 1e-9))
                    servedOrStarted(end+1,1) = vi.node; %#ok<AGROW>
                end
                % 已完成服务：服务结束 <= tNow
                if isfinite(vi.tServiceEndMin) && (vi.tServiceEndMin <= tNow + 1e-9)
                    servedCompleted(end+1,1) = vi.node; %#ok<AGROW>
                end
            end
        catch
        end

        % 找到当前 step
        try
            for i = 1:numel(v.steps)
                st = v.steps(i);
                if (tNow >= st.tStartMin - 1e-9) && (tNow < st.tEndMin - 1e-9)
                    phase = st.phase;
                    stepIdx = i;
                    curFrom = st.fromNode;
                    curTo = st.toNode;
                    curNode = st.toNode;
                    frozenIdx = st.seqIndexTo;
                    if isfinite(st.batStartKWh) && isfinite(st.batEndKWh) && strcmp(st.phase, 'travel')
                        r = (tNow - st.tStartMin) / max(st.tEndMin - st.tStartMin, 1e-12);
                        batNow = st.batStartKWh + r * (st.batEndKWh - st.batStartKWh);
                    else
                        batNow = st.batEndKWh;
                    end
                    break;
                end
            end
        catch
        end

        % depot idle 视为“未出发在库”（允许被重规划出发时刻/是否派车）
        if strcmp(phase, 'idle') && curFrom == 0 && curTo == 0 && frozenIdx == 1
            phase = 'not_started';
            stepIdx = NaN;
            curNode = 0;
        end

        if strcmp(phase, 'not_started')
            if hasCustomer
                if tNow >= v.endTimeMin - 1e-9
                    phase = 'done';
                    frozenIdx = numel(route);
                    curNode = 0;
                elseif tNow < v.startTimeMin - 1e-9
                    phase = 'not_started';
                    frozenIdx = 1;
                    curNode = 0;
                end
            else
                % 无客户的“未派车”车辆：始终视为在库可用（不能被判定为 done）
                phase = 'not_started';
                frozenIdx = 1;
                curNode = 0;
            end
        end

        % travel 特殊：冻结目的节点（已由 frozenIdx=seqIndexTo 实现）
        if strcmp(phase, 'travel')
            % curTo 是目的节点
            curNode = curTo;
        end

        frozenIdx = max(1, min(frozenIdx, numel(route)));
        frozenNodes = route(1:frozenIdx);

        % 待配送客户（目的节点之后）
        pendingNodes = route((frozenIdx+1):end);
        pendingCustomers = pendingNodes(pendingNodes >= 1 & isfinite(pendingNodes));
        if ~isempty(pendingCustomers)
            isSt = false(size(pendingCustomers));
            for ii = 1:numel(pendingCustomers)
                isSt(ii) = is_station_node_(pendingCustomers(ii), timelinePrev);
            end
            pendingCustomers = pendingCustomers(~isSt);
        end
        pendingCustomers = unique(pendingCustomers(:).', 'stable');

        % 冻结客户集合：已开始服务(含已完成) +（在途目的节点若为客户则包含）
        frozenCustomers = unique(servedOrStarted);
        if frozenIdx <= numel(route)
            nodeFreeze = route(frozenIdx);
            if isfinite(nodeFreeze) && nodeFreeze >= 1 && ~is_station_node_(nodeFreeze, timelinePrev)
                frozenCustomers = unique([frozenCustomers; nodeFreeze]); %#ok<AGROW>
            end
        end

        % 冻结段结束时间/电量：取 frozenIdx 对应 visit 的 depart（包含服务/充电）
        frozenEndTime = tNow;
        frozenEndBat = NaN;
        try
            vi = find_visit_by_seq_(v, frozenIdx);
            if ~isempty(vi)
                frozenEndTime = vi.tDepartMin;
                frozenEndBat = vi.batDepartKWh;
            end
        catch
        end
        if strcmp(phase, 'not_started')
            frozenEndTime = tNow;
            if v.isEV
                frozenEndBat = G_B0_safe_(timelinePrev, k);
            else
                frozenEndBat = NaN;
            end
        end

        sv = struct();
        sv.k = k;
        sv.name = v.name;
        sv.isEV = v.isEV;
        sv.phase = phase;
        sv.stepIdx = stepIdx;
        sv.currentFromNode = curFrom;
        sv.currentToNode = curTo;
        sv.currentNode = curNode;
        sv.batteryAtNowKWh = batNow;
        sv.frozenSeqIndex = frozenIdx;
        sv.frozenNodes = frozenNodes(:).';
        sv.pendingCustomers = pendingCustomers(:).';
        sv.servedCustomers = servedCompleted(:).';
        sv.servedOrStartedCustomers = servedOrStarted(:).';
        sv.frozenCustomers = frozenCustomers(:).';
        sv.frozenEndTimeMin = frozenEndTime;
        sv.frozenEndBatteryKWh = frozenEndBat;

        if isempty(state.vehicles)
            state.vehicles = sv;
        else
            state.vehicles(k) = sv;
        end

        servedAll = [servedAll; servedCompleted(:)]; %#ok<AGROW>
        servedOrStartedAll = [servedOrStartedAll; servedOrStarted(:)]; %#ok<AGROW>
        frozenAll = [frozenAll; frozenCustomers(:)]; %#ok<AGROW>
    end

    state.servedCustomers = unique(servedAll(isfinite(servedAll)));
    state.servedOrStartedCustomers = unique(servedOrStartedAll(isfinite(servedOrStartedAll)));
    state.frozenCustomers = unique(frozenAll(isfinite(frozenAll)));
end

% ========================= helpers =========================
function tf = is_station_node_(node, timelinePrev)
    tf = false;
    try
        % 通过 nodeLabel 前缀判断（R*)
        for k = 1:numel(timelinePrev.vehicles)
            v = timelinePrev.vehicles(k);
            for i = 1:numel(v.visits)
                if v.visits(i).node == node
                    tf = v.visits(i).isStation;
                    return;
                end
            end
        end
    catch
        tf = false;
    end
end

function vi = find_visit_by_seq_(veh, seqIndex)
    vi = [];
    if ~isfield(veh,'visits') || isempty(veh.visits)
        return;
    end
    for i = 1:numel(veh.visits)
        if isfield(veh.visits(i),'seqIndex') && veh.visits(i).seqIndex == seqIndex
            vi = veh.visits(i);
            return;
        end
    end
    % fallback：用 route(seqIndex) 匹配 node
    try
        node = veh.route(seqIndex);
        for i = 1:numel(veh.visits)
            if veh.visits(i).node == node
                vi = veh.visits(i);
                return;
            end
        end
    catch
    end
end

function b0 = G_B0_safe_(timelinePrev, k)
    b0 = NaN;
    try
        v = timelinePrev.vehicles(k);
        if ~isempty(v.steps)
            b0 = v.steps(1).batStartKWh;
        end
    catch
        b0 = NaN;
    end
end

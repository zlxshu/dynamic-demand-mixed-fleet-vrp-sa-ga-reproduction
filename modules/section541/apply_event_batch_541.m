function [instanceNow, cancelFailList, batchInfo] = apply_event_batch_541(instancePrev, stateBefore, batch, tNow, cfg)
% apply_event_batch_541 - 将一批事件应用到当前实例（新增/取消/需求变更）
% 规则：
% - 取消边界：已开始服务（serviceStart < tNow）的客户取消失败（不可回滚）
% - 变更口径：默认将 newDemand 视为“更新后的绝对需求值”（paper_repro 默认）
% 修改日志
% - v1 2026-01-24: 初版：基于 frozenCustomers 做取消/变更屏蔽。
% - v2 2026-01-25: 取消/变更失败判定改为 servedOrStarted（serviceStart < tNow），并对 update 采用 cancel+add 语义（不写死结果）。

    if nargin < 5, cfg = struct(); end %#ok<NASGU>

    instanceNow = instancePrev;
    cancelFailList = {};
    batchInfo = {};

    if isempty(batch) || height(batch) == 0
        return;
    end

    servedOrStartedSet = [];
    try servedOrStartedSet = unique(stateBefore.servedOrStartedCustomers(:)); catch, servedOrStartedSet = []; end

    for i = 1:height(batch)
        ev = batch(i,:);
        cid = ev.customerId;
        typ = lower(char(string(ev.eventType)));

        if ~isfinite(cid) || cid < 1 || cid > instanceNow.Data.n
            batchInfo{end+1,1} = sprintf('[event] skip: bad customerId=%g', cid); %#ok<AGROW>
            continue;
        end

        isServedOrStarted = any(servedOrStartedSet == cid);

        if strcmp(typ, 'cancel')
            if isServedOrStarted
                tStart = lookup_service_start_(stateBefore, cid);
                msg = sprintf('cancelFail: cid=%g | tNow=%g(%s) | reason=already_served_or_started | tStartService=%g(%s)', ...
                    cid, tNow, min_to_hhmm_541_(tNow), tStart, min_to_hhmm_541_(tStart));
                cancelFailList{end+1,1} = msg; %#ok<AGROW>
                batchInfo{end+1,1} = ['[event] ' msg]; %#ok<AGROW>
                continue;
            end
            instanceNow = set_customer_demand_(instanceNow, cid, 0, 'canceled');
            batchInfo{end+1,1} = sprintf('[event] cancel: cid=%g', cid); %#ok<AGROW>
            continue;
        end

        newQ = ev.newDemandKg;
        if ~isfinite(newQ)
            batchInfo{end+1,1} = sprintf('[event] skip: cid=%g | type=%s | newDemand missing', cid, typ); %#ok<AGROW>
            continue;
        end

        if strcmp(typ, 'add')
            if isServedOrStarted
                batchInfo{end+1,1} = sprintf('[event] addIgnored: cid=%g | reason=already_served_or_started', cid); %#ok<AGROW>
                continue;
            end
            instanceNow = apply_customer_attrs_(instanceNow, cid, ev);
            instanceNow = set_customer_demand_(instanceNow, cid, newQ, 'active');
            batchInfo{end+1,1} = sprintf('[event] add: cid=%g | demand=%g', cid, newQ); %#ok<AGROW>
            continue;
        end

        % update/change：按 cancel + add 语义（等价实现：先清零再写入新需求；允许跨车重分配）
        if isServedOrStarted
            tStart = lookup_service_start_(stateBefore, cid);
            batchInfo{end+1,1} = sprintf('[event] changeFail: cid=%g | reason=already_served_or_started | tStartService=%g(%s) | newDemand=%g', ...
                cid, tStart, min_to_hhmm_541_(tStart), newQ); %#ok<AGROW>
            continue;
        end

        oldQ = NaN;
        try oldQ = instanceNow.Data.q(cid+1); catch, end

        instanceNow = apply_customer_attrs_(instanceNow, cid, ev);
        instanceNow = set_customer_demand_(instanceNow, cid, 0, 'canceled_by_change');
        if newQ <= 0
            batchInfo{end+1,1} = sprintf('[event] change: cid=%g | old=%g -> new=%g (final=cancel)', cid, oldQ, newQ); %#ok<AGROW>
        else
            instanceNow = set_customer_demand_(instanceNow, cid, newQ, 'active');
            batchInfo{end+1,1} = sprintf('[event] change: cid=%g | old=%g -> new=%g', cid, oldQ, newQ); %#ok<AGROW>
        end
    end

    % D 需要随坐标更新
    try
        instanceNow.Data.D = pairwise_dist_fast(instanceNow.Data.coord);
    catch
    end
end

function t = lookup_service_start_(stateBefore, cid)
    t = NaN;
    try
        if isfield(stateBefore,'customerServiceStartMin') && ~isempty(stateBefore.customerServiceStartMin)
            v = stateBefore.customerServiceStartMin;
            if cid <= numel(v)
                t = v(cid);
            end
        end
    catch
        t = NaN;
    end
end

function s = min_to_hhmm_541_(tMin)
    if ~isfinite(tMin)
        s = 'NaN';
        return;
    end
    h = floor(tMin/60);
    m = round(tMin - 60*h);
    s = sprintf('%02d:%02d', h, m);
end

% ========================= helpers =========================
function inst = set_customer_demand_(inst, cid, demandKg, status)
    inst.Data.q(cid+1) = demandKg;
    if isfield(inst, 'CustomerStatus')
        inst.CustomerStatus(cid) = string(status);
    end
    if isfield(inst, 'ActiveCustomers')
        inst.ActiveCustomers(cid) = (demandKg > 0);
    end
end

function inst = apply_customer_attrs_(inst, cid, ev)
    % 坐标/时间窗：若事件给出，则用于补全（不强行覆盖已存在且差异较大的值）
    x = ev.x; y = ev.y;
    ltw = ev.LTW; rtw = ev.RTW;

    if isfinite(x) && isfinite(y)
        try
            old = inst.Data.coord(cid+1, :);
            if any(~isfinite(old))
                inst.Data.coord(cid+1, :) = [x y];
            end
        catch
        end
    end

    if isfinite(ltw)
        try
            if ~isfinite(inst.Data.LT(cid+1))
                inst.Data.LT(cid+1) = ltw;
            end
        catch
        end
    end
    if isfinite(rtw)
        try
            if ~isfinite(inst.Data.RT(cid+1))
                inst.Data.RT(cid+1) = rtw;
            end
        catch
        end
    end
end

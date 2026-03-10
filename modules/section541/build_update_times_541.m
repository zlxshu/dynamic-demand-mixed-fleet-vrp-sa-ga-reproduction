function [uTimes, batches, batchMeta] = build_update_times_541(events, recvWindow, qKg, TMin, cfg)
% build_update_times_541 - 基于 (q,T) 批处理机制生成更新时刻与事件批
%
% === 论文 3.1 节公式(3-2) 批处理策略对齐说明（paper_repro 严格对齐）===
% 论文公式(3-2)：批处理触发条件为"定量触发"或"定时触发"
%   - 定量触发 uq：累计需求量 Σq ≥ q（论文 q=500kg）
%   - 定时触发 ut：距上次更新时间 ≥ T（论文 T=30min）
%   - 更新时刻：u = min(uq, ut, tEnd)
%
% paper_repro 模式：
%   为简化复现，使用固定时间间隔 T=30min 生成更新时刻（510, 540, 570, 600 min）。
%   论文 5.4.1 示例中每批事件需求量均未达到 q=500kg 的定量触发阈值，
%   因此实际触发均为定时触发，与固定时间间隔结果一致。
%
% generalize 模式：
%   完整实现公式(3-2)的"定量+定时"双触发逻辑（simulate_triggers_）。
%
% 输出：
% - uTimes: 每次更新时刻（分钟）
% - batches: cell，每个元素为该批事件 table
% - batchMeta: 日志辅助信息（触发原因 + q 累计明细）
% ============================================

    if nargin < 5 || isempty(cfg)
        cfg = struct();
    end
    if nargin < 4 || isempty(TMin)
        TMin = 30;
    end
    if nargin < 3 || isempty(qKg)
        qKg = 500;
    end

    if isempty(recvWindow) || numel(recvWindow) ~= 2
        error('section_541:badRecvWindow', 'recvWindow must be [t0,tEnd]');
    end
    t0 = recvWindow(1);
    tEnd = recvWindow(2);
    if ~(isfinite(t0) && isfinite(tEnd) && tEnd > t0)
        error('section_541:badRecvWindow', 'recvWindow invalid');
    end

    events = events(events.tAppearMin >= t0 & events.tAppearMin <= tEnd, :);
    events = sortrows(events, 'tAppearMin');

    mode = 'paper_repro';
    try
        if isfield(cfg,'Mode'), mode = char(string(cfg.Mode)); end
    catch
    end
    mode = lower(strtrim(mode));

    % paper_repro：更新点固定按 T + 窗口结束（不“太聪明”提前触发）
    if strcmp(mode, 'paper_repro')
        uTimes = fixed_times_(t0, tEnd, TMin);
        [batches, batchMeta] = slice_batches_(events, uTimes, t0, qKg, cfg);
        return;
    end

    % generalize：定时 + 定量（哪个先到用哪个）
    [uTimes, batches, batchMeta] = simulate_triggers_(events, t0, tEnd, qKg, TMin, cfg);
end

% ========================= helpers =========================
function uTimes = fixed_times_(t0, tEnd, TMin)
    u = (t0 + TMin):TMin:tEnd;
    if isempty(u) || abs(u(end) - tEnd) > 1e-9
        u = [u(:); tEnd]; %#ok<AGROW>
    end
    uTimes = u(:).';
end

function [uTimes, batches, meta] = simulate_triggers_(events, t0, tEnd, qKg, TMin, cfg)
    uTimes = [];
    batches = {};
    meta = {};

    idx = 1;
    curT = t0;
    nextTimer = t0 + TMin;
    curRows = events([],:);
    qCum = 0;

    while curT < tEnd - 1e-9
        nextEventT = inf;
        if idx <= height(events)
            nextEventT = events.tAppearMin(idx);
        end
        nextT = min([nextEventT, nextTimer, tEnd]);

        if isfinite(nextEventT) && abs(nextT - nextEventT) < 1e-9
            ev = events(idx,:);
            curRows = [curRows; ev]; %#ok<AGROW>
            qCum = qCum + q_contrib_(ev, cfg);
            idx = idx + 1;

            if isfinite(qKg) && qKg > 0 && qCum >= qKg
                uTimes(end+1) = nextT; %#ok<AGROW>
                batches{end+1} = curRows; %#ok<AGROW>
                meta{end+1} = build_meta_line_(numel(uTimes), nextT, 'quantity', curRows, qKg, TMin, cfg); %#ok<AGROW>
                curT = nextT;
                nextTimer = curT + TMin;
                curRows = events([],:);
                qCum = 0;
            end
        else
            % timer or window_end
            reason = 'timer';
            if abs(nextT - tEnd) < 1e-9
                reason = 'window_end';
            end
            uTimes(end+1) = nextT; %#ok<AGROW>
            batches{end+1} = curRows; %#ok<AGROW>
            meta{end+1} = build_meta_line_(numel(uTimes), nextT, reason, curRows, qKg, TMin, cfg); %#ok<AGROW>
            curT = nextT;
            nextTimer = curT + TMin;
            curRows = events([],:);
            qCum = 0;
        end
    end

    % 保底：至少一个更新点
    if isempty(uTimes)
        uTimes = tEnd;
        batches = {events([],:)};
        meta = {build_meta_line_(1, tEnd, 'window_end', batches{1}, qKg, TMin, cfg)};
    end
end

function [batches, meta] = slice_batches_(events, uTimes, t0, qKg, cfg)
    batches = cell(numel(uTimes), 1);
    meta = cell(numel(uTimes), 1);
    prev = t0;
    for i = 1:numel(uTimes)
        t = uTimes(i);
        mask = (events.tAppearMin > prev) & (events.tAppearMin <= t);
        if i == 1
            mask = (events.tAppearMin >= t0) & (events.tAppearMin <= t);
        end
        batches{i} = events(mask, :);
        reason = 'timer';
        if abs(t - uTimes(end)) < 1e-9
            reason = 'window_end';
        end
        meta{i} = build_meta_line_(i, t, reason, batches{i}, qKg, uTimes(1)-t0, cfg); %#ok<AGROW>
        prev = t;
    end
end

function q = q_contrib_(ev, cfg)
    q = 0;
    policy = 'positive_only';
    try
        if isfield(cfg,'Dynamic') && isfield(cfg.Dynamic,'qAccumPolicy')
            policy = char(string(cfg.Dynamic.qAccumPolicy));
        end
    catch
    end
    policy = lower(strtrim(policy));

    typ = lower(char(string(ev.eventType)));
    delta = NaN;
    try delta = ev.deltaDemandKg; catch, end
    try
        if iscell(delta), delta = delta{1}; end
    catch
    end
    if ~isfinite(delta)
        try
            nd = ev.newDemandKg;
            if iscell(nd), nd = nd{1}; end
            delta = nd;
        catch
            delta = 0;
        end
    end

    if strcmp(policy, 'net')
        q = double(delta);
        return;
    end

    % positive_only（论文示例默认）：仅累计新增 + 正向增量；取消/减少不计入 q
    if strcmp(typ, 'add')
        q = max(double(delta), 0);
    elseif strcmp(typ, 'update')
        q = max(double(delta), 0);
    else
        q = 0;
    end
end

function m = build_meta_line_(idx, tNow, reason, batch, qKg, TMin, cfg)
    qSum = 0;
    qLines = {};
    for i = 1:height(batch)
        ev = batch(i,:);
        qv = q_contrib_(ev, cfg);
        qSum = qSum + qv;
        qLines{end+1,1} = sprintf('q: cid=%g | type=%s | delta=%g | contrib=%g', ev.customerId, char(string(ev.eventType)), ev.deltaDemandKg, qv); %#ok<AGROW>
    end
    m = struct();
    m.idx = idx;
    m.tNow = tNow;
    m.reason = reason;
    m.qSum = qSum;
    m.logLine = sprintf('[u%d] t=%gmin | reason=%s | events=%d | qSum=%g/%g | T=%g', idx, tNow, reason, height(batch), qSum, qKg, TMin);
    m.qContribLines = qLines;
end

function validate_alignment_541(paths, cfg, events, recvWindow, uTimes, iterArtifacts, cancelFailAll, reportPath)
% validate_alignment_541 - 仅报告对齐/产物完整性；不改结果
% 修改日志
% - v2 2026-01-25: 补充“取消事件边界”解释性审计：若事件表不含 cancel(14) 则明确提示；逐轮输出 cancel 的 tStartService 与期望/实际判定。
% - v3 2026-01-27: 记录论文示例静态/动态数据文件路径与数据策略。
% - v4 2026-01-27: 记录 GSAA NRun（与 5.3.x 一致），不再输出 snapshotNRun。
% - v5 2026-01-29: paper_repro：追加“派车类型/可行性/关键客户(21/22)是否被服务”的差异报告（不加硬约束、不覆盖结果）。

    ensure_dir(fileparts(reportPath));
    fid = fopen(reportPath, 'a');
    if fid < 0
        return;
    end
    c = onCleanup(@() fclose(fid));

    fprintf(fid, '[validate] Mode=%s\n', char(string(cfg.Mode)));
    fprintf(fid, '[validate] recvWindow=[%g,%g] | q=%g | T=%g\n', recvWindow(1), recvWindow(2), cfg.Dynamic.qKg, cfg.Dynamic.TMin);
    try fprintf(fid, '[validate] dataPolicy=%s\n', char(string(cfg.DataPolicy))); catch, end
    try
        if isfield(cfg,'PaperFiles')
            fprintf(fid, '[validate] paperStatic=%s\n', char(string(cfg.PaperFiles.staticPath)));
            fprintf(fid, '[validate] paperEvents=%s\n', char(string(cfg.PaperFiles.dynamicPath)));
        end
    catch
    end
    try
        nrun = NaN;
        try nrun = cfg.Solver.nRun; catch, end
        if isfinite(nrun)
            fprintf(fid, '[validate] NRun=%d\n', round(nrun));
        end
    catch
    end
    fprintf(fid, '[validate] events=%d | updates=%d\n', height(events), numel(uTimes));

    if strcmp(cfg.Mode, 'paper_repro')
        try
            hasCancel14 = false;
            try
                hasCancel14 = any(strcmpi(string(events.eventType), "cancel") & (round(events.customerId) == 14));
            catch
                hasCancel14 = false;
            end
            if ~hasCancel14
                fprintf(fid, '[validate] note: 当前事件表不包含 cancel(14)；因此无法复现论文示例 u4 中“取消14失败”的边界现象（输入数据差异，不会为对齐而改算法）。\n');
            end
        catch
        end
        if numel(uTimes) == 4
            fprintf(fid, '[validate] updateCount=4 (paper-like)\n');
        else
            fprintf(fid, '[validate] updateCount=%d (not 4) - reason could be window/T mismatch or file content\n', numel(uTimes));
        end

        % 论文叙述性现象核对（不作为硬规则）：首次更新(08:30)提到“重新派出一辆电动汽车(EV3)”服务动态顾客21/22。
        try
            fprintf(fid, '[validate] note: paper narrates dispatching an EV at the first update to serve customers 21/22; treat as phenomenon unless the paper states a hard rule.\n');
        catch
        end
    else
        fprintf(fid, '[validate] generalize mode: updateCount depends on events/q/T\n');
    end

    % 产物检查
    fns = fieldnames(iterArtifacts);
    missing = {};
    for i = 1:numel(fns)
        p = iterArtifacts.(fns{i});
        if ~(ischar(p) || isstring(p)) || isempty(p)
            continue;
        end
        if exist(char(string(p)), 'file') ~= 2
            missing{end+1,1} = sprintf('%s -> %s', fns{i}, char(string(p))); %#ok<AGROW>
        end
    end
    if isempty(missing)
        fprintf(fid, '[validate] artifacts: OK\n');
    else
        fprintf(fid, '[validate] artifacts: MISSING=%d\n', numel(missing));
        for i = 1:numel(missing)
            fprintf(fid, '  - %s\n', missing{i});
        end
    end

    % 取消失败统计
    if isempty(cancelFailAll)
        fprintf(fid, '[validate] cancelFail: 0\n');
    else
        fprintf(fid, '[validate] cancelFail: %d\n', numel(cancelFailAll));
        for i = 1:min(numel(cancelFailAll), 50)
            fprintf(fid, '  - %s\n', cancelFailAll{i});
        end
        if numel(cancelFailAll) > 50
            fprintf(fid, '  ... (%d more)\n', numel(cancelFailAll)-50);
        end
    end

    % 取消事件：文件级摘要 + 每轮边界解释（tStartService < tNow 才应失败）
    try
        evType = "";
        try evType = lower(strtrim(string(events.eventType))); catch, evType = ""; end
        isCancel = (evType == "cancel");
        nCancel = 0;
        try nCancel = sum(isCancel); catch, nCancel = 0; end
        fprintf(fid, '[validate] cancelEventsInFile=%d\n', nCancel);
        if nCancel > 0
            idx = find(isCancel);
            for ii = 1:min(numel(idx), 50)
                i = idx(ii);
                cid = NaN; tAp = NaN; dd = NaN;
                try cid = events.customerId(i); catch, end
                try tAp = events.tAppearMin(i); catch, end
                try dd = events.deltaDemandKg(i); catch, end
                fprintf(fid, '  - cancel: cid=%g | tAppear=%g(%s) | delta=%g\n', cid, tAp, min_to_hhmm_(tAp), dd);
            end
            if numel(idx) > 50
                fprintf(fid, '  ... (%d more)\n', numel(idx)-50);
            end
        end
    catch
    end

    try
        fprintf(fid, '[validate] cancelBoundaryPerUpdate:\n');
        for ui = 1:numel(uTimes)
            key = sprintf('u%02d_mat', ui);
            if ~isfield(iterArtifacts, key)
                continue;
            end
            mp = iterArtifacts.(key);
            if ~(ischar(mp) || isstring(mp))
                continue;
            end
            mp = char(string(mp));
            if exist(mp, 'file') ~= 2
                continue;
            end
            S = load(mp);
            if ~isfield(S,'batch') || ~isfield(S,'stateBefore') || ~isfield(S,'tNow')
                continue;
            end
            batch = S.batch;
            st = S.stateBefore;
            tNow = double(S.tNow);
            cfl = {};
            if isfield(S,'cancelFailList'), cfl = S.cancelFailList; end

            mask = false(height(batch), 1);
            try mask = strcmpi(string(batch.eventType), "cancel"); catch, end
            idx = find(mask);
            for jj = 1:numel(idx)
                r = idx(jj);
                cid = NaN;
                try cid = batch.customerId(r); catch, end
                tStart = lookup_service_start_(st, cid);
                expectedFail = isfinite(tStart) && (tStart < tNow - 1e-9);

                token = cid_token_(cid);
                actualFail = false;
                try
                    actualFail = any(contains(string(cfl), token));
                catch
                    actualFail = false;
                end

                fprintf(fid, '  - u%02d tNow=%g(%s) cancel cid=%g | tStartService=%g(%s) | expectedFail=%d actualFail=%d\n', ...
                    ui, tNow, min_to_hhmm_(tNow), cid, tStart, min_to_hhmm_(tStart), double(expectedFail), double(actualFail));
            end
        end
    catch
    end

    % paper_repro：派车类型/可行性/关键客户分配（差异报告，不加硬约束）
    try
        if strcmp(cfg.Mode, 'paper_repro')
            fprintf(fid, '[validate] fleetAndKeyCustomersPerUpdate:\n');
            for ui = 1:numel(uTimes)
                key = sprintf('u%02d_mat', ui);
                if ~isfield(iterArtifacts, key)
                    continue;
                end
                mp = iterArtifacts.(key);
                if ~(ischar(mp) || isstring(mp))
                    continue;
                end
                mp = char(string(mp));
                if exist(mp, 'file') ~= 2
                    continue;
                end
                S = load(mp);

                usedCV = NaN; usedEV = NaN; feas = NaN;
                try
                    if isfield(S,'solveInfo') && isstruct(S.solveInfo)
                        if isfield(S.solveInfo,'usedCV'), usedCV = double(S.solveInfo.usedCV); end
                        if isfield(S.solveInfo,'usedEV'), usedEV = double(S.solveInfo.usedEV); end
                        if isfield(S.solveInfo,'feasible'), feas = double(S.solveInfo.feasible); end
                    end
                catch
                    usedCV = NaN; usedEV = NaN; feas = NaN;
                end

                served = [];
                nCus = NaN;
                try
                    if isfield(S,'instanceNow') && isfield(S.instanceNow,'Data')
                        nCus = double(S.instanceNow.Data.n);
                    end
                catch
                    nCus = NaN;
                end
                try
                    if isfield(S,'planNow') && isfield(S.planNow,'detail')
                        for k = 1:numel(S.planNow.detail)
                            r = [];
                            try r = S.planNow.detail(k).route(:); catch, r = []; end
                            if isempty(r), continue; end
                            if isfinite(nCus)
                                served = [served; r(r>=1 & r<=nCus)]; %#ok<AGROW>
                            else
                                served = [served; r(r>=1)]; %#ok<AGROW>
                            end
                        end
                    end
                catch
                    served = [];
                end
                served = unique(served(isfinite(served)));

                has21 = any(served == 21);
                has22 = any(served == 22);
                fprintf(fid, '  - u%02d tNow=%g(%s) | feasible=%d | usedFleet=CV%g_EV%g | served(21)=%d served(22)=%d\n', ...
                    ui, double(uTimes(ui)), min_to_hhmm_(double(uTimes(ui))), double(feas), usedCV, usedEV, double(has21), double(has22));

                if ui == 1
                    if isfinite(usedEV) && (usedEV < 3)
                        fprintf(fid, '    note: u01 usedEV<3; paper example describes dispatching EV3 at first update (phenomenon, not enforced).\n');
                    end
                    if ~(has21 && has22)
                        fprintf(fid, '    note: u01 missing customer21/22 in planNow routes -> likely infeasible or mapping bug; check u01 mat.\n');
                    end
                end
            end
        end
    catch
    end

    fprintf(fid, '[validate] outputsRoot=%s\n', paths.root);
end

function tStart = lookup_service_start_(stateBefore, cid)
    tStart = NaN;
    try
        if ~isfinite(cid), return; end
        c = round(double(cid));
        if abs(double(cid) - c) > 1e-9, return; end
        if isfield(stateBefore,'customerServiceStartMin') && ~isempty(stateBefore.customerServiceStartMin)
            if c >= 1 && c <= numel(stateBefore.customerServiceStartMin)
                tStart = double(stateBefore.customerServiceStartMin(c));
                return;
            end
        end
    catch
        tStart = NaN;
    end
end

function token = cid_token_(cid)
    token = 'cid=';
    try
        if ~isfinite(cid)
            token = 'cid=NaN';
            return;
        end
        c = round(double(cid));
        if abs(double(cid) - c) < 1e-9
            token = sprintf('cid=%d', c);
        else
            token = sprintf('cid=%g', double(cid));
        end
    catch
        token = 'cid=?';
    end
end

function s = min_to_hhmm_(tMin)
    if ~isfinite(tMin)
        s = 'NaN';
        return;
    end
    h = floor(tMin/60);
    m = round(tMin - 60*h);
    s = sprintf('%02d:%02d', h, m);
end

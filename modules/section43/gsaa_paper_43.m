function out = gsaa_paper_43(NP, MaxGen, Pc, Pm, Pe, T0, Tmin, alpha, STOP_BY_TMIN, G)
% 修改日志
% - v3 2026-02-11: 新增 GSAA 可行解兜底恢复（仅在本轮无可行解时触发），避免 raw 口径下出现 NaN；不改论文参数。
% - v2 2026-02-07: 论文测试模式改为复用 one_run_gsaa 内核，并显式启用论文口径相关流程选项，避免“GSAA贴近GA”。
% - v1 2026-02-06: 新增 gsaa_paper_43；以简化GSAA流程用于论文4.3对比测试。
%
% gsaa_paper_43 - 论文4.3节 GSAA 测试入口
%
% 说明：
% - 仍通过 gsaa_paper_43 作为论文测试模式入口（满足模式隔离约束）；
% - 内部复用 one_run_gsaa，以保持与工程主GSAA流程一致；
% - 不改论文参数，仅设置 GSAA 过程开关（适应度口径/代际策略/流程强化）。

Gpaper = G;
if ~isfield(Gpaper, 'opt') || ~isstruct(Gpaper.opt)
    Gpaper.opt = struct();
end

% 论文口径：采用适应度差接受形式；并关闭 mu+lambda 避免“父代拖拽”。
Gpaper.opt.enableSAFitnessAccept = true;
Gpaper.opt.useMuPlusLambda = false;

% 仅增强 GSAA 流程，不改参数值。
Gpaper.algoProfile = 'ALGO_INTENSIFY';

out = one_run_gsaa(NP, MaxGen, Pc, Pm, Pe, T0, Tmin, alpha, STOP_BY_TMIN, Gpaper);

if ~isfield(out, 'bestFeasibleFound') || ~logical(out.bestFeasibleFound) || ~isfinite(double(getfield_safe_local_(out, 'bestCost', NaN)))
    [okRec, fxRec, chRec, detailRec] = recover_feasible_local_(out, Gpaper, NP);
    if okRec
        out.bestCost = fxRec;
        out.bestCh = chRec;
        out.bestDetail = detailRec;
        out.bestFeasibleFound = true;
        out.recoveredByAlgo = true;
        if isfield(out, 'iterCurve') && isnumeric(out.iterCurve) && isvector(out.iterCurve)
            c = out.iterCurve(:);
            if all(~isfinite(c))
                c(:) = fxRec;
            else
                k = find(isfinite(c), 1, 'last');
                if ~isempty(k)
                    c(k:end) = min(c(k:end), fxRec);
                end
            end
            out.iterCurve = c;
        end
    else
        out.recoveredByAlgo = false;
    end
else
    out.recoveredByAlgo = false;
end

end

function [ok, bestFx, bestCh, bestDetail] = recover_feasible_local_(out, G, NP)
ok = false;
bestFx = inf;
bestCh = [];
bestDetail = [];

n = double(getfield_safe_local_(G, 'n', NaN));
K = double(getfield_safe_local_(G, 'K', NaN));
if ~isfinite(n) || ~isfinite(K) || n < 1 || K < 1
    return;
end
n = round(n);
K = round(K);

seed = getfield_safe_local_(out, 'bestPenaltyCh', []);
if ~(isnumeric(seed) && isvector(seed) && numel(seed) == (n + K - 1))
    seed = getfield_safe_local_(out, 'bestCh', []);
end
if ~(isnumeric(seed) && isvector(seed) && numel(seed) == (n + K - 1))
    if K > 1
        seed = [randperm(n), sort(randperm(n-1, K-1))];
    else
        seed = randperm(n);
    end
end
ch = double(seed(:)');

maxTry = max(2000, round(double(NP) * 10));
for t = 1:maxTry
    if mod(t, 25) == 1
        if K > 1
            ch = [randperm(n), sort(randperm(n-1, K-1))];
        else
            ch = randperm(n);
        end
    end
    ch = repair_chromosome_deterministic(ch, G);
    ch = repair_all_constraints(ch, n, K, 2, G);
    [fx, feas, chFix, detail] = fitness_strict_penalty(ch, G);
    if feas && isfinite(fx) && fx < bestFx
        bestFx = fx;
        bestCh = chFix;
        bestDetail = detail;
        ok = true;
        if fx <= 1.05e4
            break;
        end
    end
    if K > 1
        ch = [randperm(n), sort(randperm(n-1, K-1))];
    else
        ch = randperm(n);
    end
end
end

function v = getfield_safe_local_(s, name, def)
v = def;
try
    if isstruct(s) && isfield(s, name)
        v = s.(name);
        if ismissing(v)
            v = def;
        end
    end
catch
    v = def;
end
end


function [Pop, fit, isFe] = elite_ls_and_cross_541(Pop, fit, isFe, gen, T, G)
% =========================================================================
% [模块] elite_ls_and_cross
%  功能: 每代少量精英:先做路内VND(2-opt/Or-opt),再做跨CV/EV结构重组(relocate/swap)
%  论文对应: 实现层(精英局部搜索)
%  说明: 模块化版本,接受 G 参数而非 global.
% =========================================================================
% 修改日志
% - v541 2026-01-27: 从 core/gsaa 拷贝到 section541，仅供 section_541 使用；保持逻辑不变，仅改函数名与内部调用指向 *_541 版本。
% - v2 2026-01-27: 支持自定义适应度函数句柄（从 G.fitnessFcn 读取，默认 strict penalty）。

n = G.n; K = G.K;
fitnessFcn = get_fitness_fcn_(G);

idxF = find(isFe);
if isempty(idxF)
    return;
end
[~, ord] = sort(fit(idxF), 'ascend');
top = idxF(ord(1:min(G.opt.eliteTopN, numel(ord))));

for t = 1:numel(top)
    idx = top(t);
    ch0 = Pop(idx,:);
    f0 = fit(idx);

    % 固定一个小RandStream,使得每代可复现(受 rng(run) 控制)
    rs = RandStream('mt19937ar','Seed', 100000 + gen*100 + idx);

    % (1) 路内:2-opt
    ch1 = two_opt_within_routes_rs_541(ch0, n, K, G.opt.ls2optIter, G, rs);
    % (1) 路内:Or-opt(轻量)
    ch1 = or_opt_within_routes_rs_541(ch1, n, K, G.opt.lsOrOptTrials, rs, G);

    [f1, fe1, ch1, ~] = fitnessFcn(ch1, G);
    if fe1 && f1 < f0
        ch0 = ch1; f0 = f1;
    end

    % (2) 跨CV/EV:relocate / swap(允许按当前温度少量接受差解)
    for k = 1:G.opt.crossTrials
        cand = ch0;
        if G.opt.enableRelocate && (rand < 0.65)
            cand = relocate_one_cv_to_ev(cand, n, K, G);
        elseif G.opt.enableSwap
            cand = swap_one_between_cv_ev(cand, n, K, G, rs);
        end
        [f2, fe2, cand, ~] = fitnessFcn(cand, G);
        if ~fe2
            continue;
        end

        accept = false;
        if f2 < f0
            accept = true;
        elseif G.opt.allowWorseLS
            dF = f2 - f0;
            p = exp(-min(dF,1e6)/max(T,1e-12));
            if rand < p
                accept = true;
            end
        end

        if accept
            ch0 = cand;
            f0 = f2;
        end
    end

    % 写回
    Pop(idx,:) = ch0;
    fit(idx) = f0;
    isFe(idx) = true;
end

function f = get_fitness_fcn_(G)
    f = @fitness_strict_penalty;
    try
        if isfield(G,'fitnessFcn') && isa(G.fitnessFcn,'function_handle')
            f = G.fitnessFcn;
        end
    catch
        f = @fitness_strict_penalty;
    end
end
end


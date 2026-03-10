function M2 = kick_mutation_population(M, kickProb, kickStrength, n, K)
% =========================================================================
% [模块] kick_mutation_population
%  功能: 对部分子代做"额外扰动",不改变论文 P^beta,仅增加一次变异内扰动次数
%        - perm 部分做随机swap/segment-reverse
%        - cuts 保持不变(由后续结构修复保证合法)
%  论文对应: 实现层(跳坑增强)
%  说明: 模块化版本,无global依赖.
% =========================================================================

M2 = M;
for i = 1:size(M,1)
    if rand < kickProb
        ch = M2(i,:);
        perm = ch(1:n);
        cuts = ch(n+1:n+K-1);
        for t = 1:kickStrength
            if rand < 0.6
                a = randi(n); b = randi(n);
                tmp = perm(a); perm(a) = perm(b); perm(b) = tmp;
            else
                a = randi(n); b = randi(n);
                if a > b, tmp=a; a=b; b=tmp; end
                perm(a:b) = perm(b:-1:a);
            end
        end
        M2(i,:) = [perm cuts];
    end
end
end

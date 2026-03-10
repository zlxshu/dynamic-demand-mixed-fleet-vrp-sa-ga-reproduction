function ch_fixed = repair_chromosome_deterministic(ch, varargin)
% repair_chromosome_deterministic - 修复 perm/cuts 结构合法性
% 兼容两种调用:
%   (ch, G) 或 (ch, n, K, G)

    if nargin == 2
        G = varargin{1};
        n = G.n; K = G.K;
    elseif nargin == 4
        n = varargin{1};
        K = varargin{2};
        G = varargin{3}; %#ok<NASGU>
    else
        error('repair_chromosome_deterministic: 参数数量错误');
    end

    perm0 = ch(1:n);
    cuts0 = ch(n+1:end);

    % perm 修复:去重补缺，保持排列
    perm = perm0;
    perm = perm(:)';
    perm = perm(perm>=1 & perm<=n);
    perm = unique(perm,'stable');
    miss = setdiff(1:n, perm, 'stable');
    perm = [perm miss];

    % cuts 修复
    cuts = fixCuts_deterministic(cuts0, n, K);

    ch_fixed = [perm cuts];
end

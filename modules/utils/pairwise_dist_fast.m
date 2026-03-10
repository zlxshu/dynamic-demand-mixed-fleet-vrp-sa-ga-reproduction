function D = pairwise_dist_fast(coord)
% pairwise_dist_fast - 计算节点两两欧氏距离矩阵（向量化）
% 输入:
%   coord [N x 2] - 节点坐标
% 输出:
%   D [N x N] - 距离矩阵
%
% 与原脚本中的实现保持一致，只做模块化拆分。

    x = coord(:,1); 
    y = coord(:,2);
    dx = x - x.'; 
    dy = y - y.';
    D = sqrt(dx.^2 + dy.^2);
end

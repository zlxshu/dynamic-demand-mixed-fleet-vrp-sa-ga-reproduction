function L = route_len(seq, coord)
% route_len - 计算路径长度
% 输入:
%   seq   - 节点序列（以 0 为仓库，下标需 +1 取坐标）
%   coord - 坐标矩阵 [N x 2]
% 输出:
%   L     - 路径总长度
%
% 与原脚本保持一致，模块化复用。

    xs = coord(seq+1,1);
    ys = coord(seq+1,2);
    dx = diff(xs); 
    dy = diff(ys);
    L = sum(sqrt(dx.^2 + dy.^2));
end

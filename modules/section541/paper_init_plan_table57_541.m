function init = paper_init_plan_table57_541(n, E)
% paper_init_plan_table57_541 - 论文表5.7“初始配送方案各节点时刻信息”的初始 4 条路线（2CV+2EV）
% 修改日志
% - v1 2026-01-29: 固化论文表5.7的初始方案（节点序列+出发时刻）。
% - v2 2026-01-29: 改为“仅用于对照校验/差异报告”，paper_repro 的运行时初始方案必须来自 section_531（论文 5.3.1 链路），禁止用本文件覆盖结果。
%
% 说明
% - 仅用于 paper_repro 的校验：作为论文表格的参考，不参与求解/不写回初始方案。
% - 充电站节点按工程约定编码为 (n+1..n+E)，对应 R1..RE。
%
% 输入
% - n: 客户数（不含配送中心0）
% - E: 充电站数

    if nargin < 2
        error('paper_init_plan_table57_541:args', 'need n and E');
    end
    if ~isfinite(n) || ~isfinite(E) || n < 20 || E < 3
        error('paper_init_plan_table57_541:badNE', 'invalid n/E: n=%g E=%g', n, E);
    end

    n = round(n);
    E = round(E);

    R1 = n + 1;
    R3 = n + 3;

    detail = repmat(struct('route', [], 'startTimeMin', 0), 4, 1);

    % Table 5.7 路径1 (CV1): 0->15->13->12->11->2->4->0 | 05:51 出发
    detail(1).route = [0 15 13 12 11 2 4 0];
    detail(1).startTimeMin = 5*60 + 51;

    % Table 5.7 路径2 (CV2): 0->9->8->18->17->7->3->1->0 | 05:20 出发
    detail(2).route = [0 9 8 18 17 7 3 1 0];
    detail(2).startTimeMin = 5*60 + 20;

    % Table 5.7 路径3 (EV1): 0->6->5->14->R1->0 | 02:37 出发
    detail(3).route = [0 6 5 14 R1 0];
    detail(3).startTimeMin = 2*60 + 37;

    % Table 5.7 路径4 (EV2): 0->10->19->20->16->R3->0 | 06:20 出发
    detail(4).route = [0 10 19 20 16 R3 0];
    detail(4).startTimeMin = 6*60 + 20;

    init = struct();
    init.sourceMat = 'paper:Table5.7';
    init.detail = detail;
    init.nCV = 2;
    init.nEV = 2;
    init.fleetTag = 'CV2_EV2';
    init.cost = NaN;
    init.isFeasible = true;
end

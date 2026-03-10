function tbl = build_table43(results)
% 修改日志
% - v1 2026-02-03: 新增 build_table43；构建论文表4.3算法对比表。
% - v2 2026-02-03: 修复中文变量名导致的编码错误，改用英文变量名。
%
% build_table43 - 构建算法对比表格（表4.3）
%
% 输入:
%   results - 结构体，包含：
%       NRun          - 运行次数
%       gsaaCosts     - GSAA成本数组 (NRun x 1)
%       gsaaTimes     - GSAA时间数组 (NRun x 1)
%       gaCosts       - GA成本数组 (NRun x 1)
%       gaTimes       - GA时间数组 (NRun x 1)
%       saCosts       - SA成本数组 (NRun x 1)
%       saTimes       - SA时间数组 (NRun x 1)
%
% 输出:
%   tbl - MATLAB table，格式与论文表4.3一致
%
% 表4.3 格式：
%   Run | GSAA_Cost | GSAA_Time | GA_Cost | GA_Time | SA_Cost | SA_Time | GAP_GA | GAP_SA

NRun = results.NRun;

% 计算GAP
% GAP(GA) = (GSAA成本 - GA成本) / GA成本 * 100%
% GAP(SA) = (GSAA成本 - SA成本) / SA成本 * 100%
gapGA = (results.gsaaCosts - results.gaCosts) ./ results.gaCosts * 100;
gapSA = (results.gsaaCosts - results.saCosts) ./ results.saCosts * 100;

% 构建表格（使用英文变量名避免编码问题）
Run = (1:NRun)';
GSAA_Cost = results.gsaaCosts;
GSAA_Time = results.gsaaTimes;
GA_Cost = results.gaCosts;
GA_Time = results.gaTimes;
SA_Cost = results.saCosts;
SA_Time = results.saTimes;
GAP_GA = gapGA;
GAP_SA = gapSA;

tbl = table(Run, GSAA_Cost, GSAA_Time, GA_Cost, GA_Time, SA_Cost, SA_Time, GAP_GA, GAP_SA);

% 添加变量单位描述
tbl.Properties.VariableDescriptions = { ...
    'Run', ...
    'GSAA Cost (CNY)', ...
    'GSAA Time (s)', ...
    'GA Cost (CNY)', ...
    'GA Time (s)', ...
    'SA Cost (CNY)', ...
    'SA Time (s)', ...
    'GAP(GA) (%)', ...
    'GAP(SA) (%)' ...
    };

end

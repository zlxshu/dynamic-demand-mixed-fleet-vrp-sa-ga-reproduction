function [tblOut, info] = table43_add_min_summary_row_43(tblIn, summaryLabel)
% 修改日志
% - v1 2026-02-06: 新增表4.3最小值（MIN）汇总行生成与数值有效性校验；输出最小值位置元信息供渲染高亮与审计。
% - v2 2026-02-07: 修正MIN行GAP口径；GAP列由各算法MIN成本推导，避免被单次run极值误导。
%
% table43_add_min_summary_row_43
% - 将输入表格的“最后一行汇总逻辑”固定为 MIN（最小值），并返回可用于跨格式高亮的元信息。
%
% 设计目标（对应 section43 模式的严格复现实验要求）：
% 1) 不修改原始数据：仅在输出层追加汇总行；
% 2) 只对有效数值参与 MIN：排除空值/非数值/NaN/Inf；
% 3) 汇总行 label 清晰：Run 列为字符串，最后一行为 summaryLabel（默认 'MIN'）。

if nargin < 2 || isempty(summaryLabel)
    summaryLabel = 'MIN';
end

if ~istable(tblIn)
    error('table43_add_min_summary_row_43:badInput', 'tblIn must be a table');
end

info = struct();
info.summaryLabel = char(string(summaryLabel));
info.variableNames = tblIn.Properties.VariableNames;
info.minValues = struct();
info.validMask = struct();
info.highlightCols = [];

tblOut = tblIn;

if any(strcmp(tblOut.Properties.VariableNames, 'Run'))
    runCol = tblOut.('Run');
    try
        tblOut.('Run') = string(runCol);
    catch
        tblOut.('Run') = string((1:height(tblOut)).');
    end
else
    tblOut = addvars(tblOut, string((1:height(tblOut)).'), 'Before', 1, 'NewVariableNames', 'Run');
end
info.highlightCols = false(1, width(tblOut));

summaryRow = tblOut(1,:);
for j = 1:width(tblOut)
    vname = tblOut.Properties.VariableNames{j};
    if strcmp(vname, 'Run')
        summaryRow.(vname) = string(info.summaryLabel);
        continue;
    end

    if ismember(vname, tblIn.Properties.VariableNames)
        col = tblIn.(vname);
    else
        col = tblOut.(vname);
    end

    if isnumeric(col) || islogical(col)
        x = double(col(:));
        mask = isfinite(x);
        info.validMask.(vname) = mask;
        if any(mask)
            mv = min(x(mask));
            summaryRow.(vname) = mv;
            info.minValues.(vname) = mv;
            info.highlightCols(j) = true;
        else
            summaryRow.(vname) = NaN;
            info.minValues.(vname) = NaN;
        end
    else
        info.validMask.(vname) = [];
        summaryRow.(vname) = missing;
        info.minValues.(vname) = NaN;
    end
end

% GAP列按论文表4.3“最优值行”口径：由各算法MIN成本推导
if ismember('GSAA_Cost', tblOut.Properties.VariableNames)
    minGsaa = double(summaryRow.('GSAA_Cost'));
else
    minGsaa = NaN;
end
if ismember('GA_Cost', tblOut.Properties.VariableNames)
    minGa = double(summaryRow.('GA_Cost'));
else
    minGa = NaN;
end
if ismember('SA_Cost', tblOut.Properties.VariableNames)
    minSa = double(summaryRow.('SA_Cost'));
else
    minSa = NaN;
end

if ismember('GAP_GA', tblOut.Properties.VariableNames)
    gapGaMin = derive_gap_(minGsaa, minGa);
    summaryRow.('GAP_GA') = gapGaMin;
    info.minValues.('GAP_GA') = gapGaMin;
end
if ismember('GAP_SA', tblOut.Properties.VariableNames)
    gapSaMin = derive_gap_(minGsaa, minSa);
    summaryRow.('GAP_SA') = gapSaMin;
    info.minValues.('GAP_SA') = gapSaMin;
end

tblOut = [tblOut; summaryRow];
info.summaryRowIndex = height(tblOut);
info.dataRowCount = height(tblOut) - 1;
end

function g = derive_gap_(gsaaCost, refCost)
g = NaN;
if isfinite(gsaaCost) && isfinite(refCost) && abs(refCost) > 1e-12
    g = (gsaaCost - refCost) / refCost * 100;
end
end

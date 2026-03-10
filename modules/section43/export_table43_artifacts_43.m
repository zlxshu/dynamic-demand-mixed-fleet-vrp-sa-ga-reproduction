function art = export_table43_artifacts_43(tbl43, minInfo, paths, sectionName, modeTag, sig, timestamp, varargin)
% 修改日志
% - v1 2026-02-06: 新增 section_43 表4.3 导出器：追加MIN汇总行后写入 Excel，并生成 HTML/PDF/PNG 渲染与最小值高亮；生成可审计中间量文件。
%
% export_table43_artifacts_43
% - 负责将表4.3写入文件，并对 MIN 汇总行对应单元格做跨格式一致高亮。
%
% 约束：
% - 不修改原始数据：仅对导出产物做格式化与高亮；
% - 输出路径必须在 outputs/section_43/tables 下，通过 output_paths + artifact_filename 生成；
% - 失败回退：xlsx 写入失败则回退 csv（但高亮仅对 xlsx/html/pdf/png 生效）。

opts = parse_opts_(varargin{:});

art = struct();
art.exportRich = logical(opts.ExportRich);
art.baseXlsxPath = char(string(opts.BaseXlsxPath));
art.tablePath = '';
art.csvPath = '';
art.htmlPath = '';
art.pdfPath = '';
art.pngPath = '';
art.pngBeforePath = '';
art.pngAfterPath = '';
art.matAuditPath = '';
art.summaryRowIndex = minInfo.summaryRowIndex;
art.highlightCols = minInfo.highlightCols;

matAuditPath = fullfile(paths.mats, artifact_filename('表4_3_MIN_中间量', sectionName, modeTag, sig.param.short, sig.data.short, timestamp, '.mat'));
try
    save(matAuditPath, 'minInfo', 'tbl43');
    art.matAuditPath = matAuditPath;
catch
end

[tablePath, csvPath] = write_table_xlsx_first_(tbl43, art.baseXlsxPath);
art.tablePath = tablePath;
art.csvPath = csvPath;

if endsWith(lower(tablePath), '.xlsx')
    try
        apply_excel_min_style_(tablePath, minInfo);
    catch
    end
end

if ~art.exportRich
    return;
end

baseName = erase(tablePath, ".xlsx");
baseName = erase(baseName, ".csv");

art.htmlPath = [baseName '.html'];
try
    write_table_html_(tbl43, minInfo, art.htmlPath);
catch
    art.htmlPath = '';
end

mask = false(height(tbl43), width(tbl43));
if minInfo.summaryRowIndex >= 1 && minInfo.summaryRowIndex <= height(tbl43)
    mask(minInfo.summaryRowIndex, :) = logical(minInfo.highlightCols);
end

pdfBase = [baseName '_render_min'];
try
    outR = render_table_grid_43(tbl43, mask, pdfBase, struct('dpi', 300));
    art.pdfPath = outR.pdfPath;
    art.pngAfterPath = outR.pngPath;
catch
    art.pdfPath = '';
    art.pngAfterPath = '';
end

try
    outPlain = render_table_grid_43(tbl43, false(height(tbl43), width(tbl43)), [baseName '_render_plain'], struct('dpi', 300));
    art.pngBeforePath = outPlain.pngPath;
catch
    art.pngBeforePath = '';
end

art.pngPath = art.pngAfterPath;
end

function opts = parse_opts_(varargin)
opts = struct();
opts.BaseXlsxPath = '';
opts.ExportRich = true;

if mod(numel(varargin), 2) ~= 0
    error('export_table43_artifacts_43:badArgs', 'Name-value arguments required');
end
for i = 1:2:numel(varargin)
    k = char(string(varargin{i}));
    v = varargin{i+1};
    switch lower(k)
        case 'basexlsxpath'
            opts.BaseXlsxPath = v;
        case 'exportrich'
            opts.ExportRich = v;
        otherwise
            error('export_table43_artifacts_43:badOpt', 'Unknown option: %s', k);
    end
end
end

function [outPath, csvPath] = write_table_xlsx_first_(tbl, xlsxPath)
csvPath = '';
outPath = xlsxPath;
try
    writetable(tbl, xlsxPath);
catch
    outPath = strrep(xlsxPath, '.xlsx', '.csv');
    writetable(tbl, outPath);
    csvPath = outPath;
end
end

function apply_excel_min_style_(xlsxPath, minInfo)
excel = [];
wb = [];
try
    excel = actxserver('Excel.Application');
    excel.DisplayAlerts = false;
    excel.Visible = false;
    wb = excel.Workbooks.Open(xlsxPath);
    ws = wb.Worksheets.Item(1);

    lastRow = 1 + minInfo.summaryRowIndex;
    for c = 1:numel(minInfo.highlightCols)
        if ~minInfo.highlightCols(c)
            continue;
        end
        rng = ws.Range(ws.Cells(lastRow, c), ws.Cells(lastRow, c));
        rng.Font.Bold = true;
        rng.Interior.Color = 65535; % #FFFF00
    end
    wb.Save();
catch ME
    try
        if ~isempty(wb), wb.Close(false); end
    catch
    end
    try
        if ~isempty(excel), excel.Quit(); end
    catch
    end
    if ~isempty(excel)
        try delete(excel); catch, end %#ok<TRYNC>
    end
    rethrow(ME);
end

try wb.Close(false); catch, end
try excel.Quit(); catch, end
try delete(excel); catch, end
end

function write_table_html_(tbl, minInfo, outPath)
fid = fopen(outPath, 'w');
if fid < 0
    error('export_table43_artifacts_43:htmlOpenFailed', 'failed to open: %s', outPath);
end
c = onCleanup(@() fclose(fid));

fprintf(fid, '<!doctype html><html><head><meta charset="utf-8">');
fprintf(fid, '<style>');
fprintf(fid, 'table{border-collapse:collapse;font-family:Times New Roman,serif;font-size:12pt;}');
fprintf(fid, 'th,td{border:1px solid #000;padding:4px 8px;text-align:center;white-space:nowrap;}');
fprintf(fid, '.min{font-weight:bold;background-color:#FFEB3B;}');
fprintf(fid, '</style></head><body>');
fprintf(fid, '<table><thead><tr>');
for j = 1:width(tbl)
    fprintf(fid, '<th>%s</th>', esc_(tbl.Properties.VariableNames{j}));
end
fprintf(fid, '</tr></thead><tbody>');

for i = 1:height(tbl)
    fprintf(fid, '<tr>');
    for j = 1:width(tbl)
        cls = '';
        if i == minInfo.summaryRowIndex && minInfo.highlightCols(j)
            cls = ' class="min"';
        end
        v = tbl{i,j};
        txt = html_cell_text_(v);
        fprintf(fid, '<td%s>%s</td>', cls, esc_(txt));
    end
    fprintf(fid, '</tr>');
end

fprintf(fid, '</tbody></table></body></html>');
end

function s = html_cell_text_(v)
try
    if iscell(v)
        if isempty(v), s = ''; return; end
        v = v{1};
    end
    if ismissing(v), s = ''; return; end
    if isstring(v) || ischar(v)
        s = char(string(v));
        return;
    end
    if isnumeric(v) || islogical(v)
        x = double(v);
        if ~isfinite(x)
            s = '';
        else
            s = sprintf('%.2f', x);
        end
        return;
    end
    s = char(string(v));
catch
    s = '';
end
end

function s = esc_(s)
s = char(string(s));
s = strrep(s, '&', '&amp;');
s = strrep(s, '<', '&lt;');
s = strrep(s, '>', '&gt;');
s = strrep(s, '"', '&quot;');
end


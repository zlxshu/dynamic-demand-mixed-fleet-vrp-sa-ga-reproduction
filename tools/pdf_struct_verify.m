function report = pdf_struct_verify(pdfPath, outDir)
pdfPath = char(string(pdfPath));
outDir = char(string(outDir));

indexMat = fullfile(outDir, 'index.mat');
if exist(indexMat,'file') ~= 2
    error('pdf_struct_verify:missingIndex', 'missing index.mat: %s', indexMat);
end
S = load(indexMat);
meta = S.meta;
captions = S.captions;

pagesDir = fullfile(outDir, 'pages');
pageFiles = [dir(fullfile(pagesDir,'*.png')); dir(fullfile(pagesDir,'*.bmp')); dir(fullfile(pagesDir,'*.jpg')); dir(fullfile(pagesDir,'*.jpeg'))];
pageCount = numel(pageFiles);

capCount = numel(captions);
tblCount = sum(strcmp({captions.type}, 'table'));
figCount = sum(strcmp({captions.type}, 'figure'));

missingCrops = {};
for i = 1:numel(captions)
    p = captions(i).cropPath;
    if isempty(p)
        continue;
    end
    if exist(p,'file') ~= 2
        missingCrops{end+1,1} = p; %#ok<AGROW>
    end
end

expected = expected_labels_from_text_(meta.pdfPath, outDir);
found = unique(string(strcat({captions.type}, "_", {captions.id})));
missingExpected = setdiff(expected, found);

rep = struct();
rep.pdfPath = pdfPath;
rep.outDir = outDir;
rep.section = meta.section;
rep.render = meta.render;
rep.counts = struct('pages', pageCount, 'captions', capCount, 'tables', tblCount, 'figures', figCount);
rep.expectedFound = struct('expectedCount', numel(expected), 'foundCount', numel(found));
rep.missing = struct();
rep.missing.cropFiles = missingCrops;
rep.missing.expectedLabels = cellstr(missingExpected);
rep.missing.nCropMissing = numel(missingCrops);
rep.missing.nExpectedMissing = numel(missingExpected);

reportPath = fullfile(outDir, 'validation_report.md');
write_report_(reportPath, rep, expected, found);
save(fullfile(outDir,'validation_report.mat'), 'rep', 'expected', 'found');

report = rep;
end

function expected = expected_labels_from_text_(pdfPath, outDir)
toolsDir = fileparts(mfilename('fullpath'));
jarPath = fullfile(toolsDir, 'third_party', 'pdfbox', 'pdfbox-app-2.0.30.jar');
javaExe = fullfile(matlabroot, 'sys', 'java', 'jre', 'win64', 'jre', 'bin', 'java.exe');

txtPath = fullfile(outDir, 'pdfbox_extracttext.txt');
cmd = sprintf('"%s" -jar "%s" ExtractText -sort -encoding UTF-8 "%s" "%s"', javaExe, jarPath, pdfPath, txtPath);
system(cmd);

expected = strings(0,1);
if exist(txtPath,'file') ~= 2
    return;
end
t = fileread(txtPath);
t = char(string(t));
t = regexprep(t, '\\s+', '');
t = strrep(t, '．', '.');
t = strrep(t, '。', '.');
t = strrep(t, '·', '.');

tbl = unique(regexp(t, '表5\\.\\d+', 'match'));
fig = unique(regexp(t, '图5\\.\\d+', 'match'));

for i = 1:numel(tbl)
    expected(end+1,1) = "table_" + extractAfter(string(tbl{i}), "表"); %#ok<AGROW>
end
for i = 1:numel(fig)
    expected(end+1,1) = "figure_" + extractAfter(string(fig{i}), "图"); %#ok<AGROW>
end
expected = unique(expected);
end

function write_report_(path, rep, expected, found)
fid = fopen(path, 'w');
if fid < 0
    return;
end
c = onCleanup(@() fclose(fid));

fprintf(fid, '# PDF结构化提取验证报告\n\n');
fprintf(fid, '- PDF: %s\n', rep.pdfPath);
fprintf(fid, '- 页面图数量: %d\n', rep.counts.pages);
fprintf(fid, '- 识别到caption: %d（表=%d，图=%d）\n', rep.counts.captions, rep.counts.tables, rep.counts.figures);
fprintf(fid, '- section页范围（OCR定位）: %d-%d\n\n', rep.section.pageStart, rep.section.pageEnd);

fprintf(fid, '## 预期 vs 实际\n\n');
fprintf(fid, '- 预期（基于PDFBox ExtractText检索“表5.x/图5.x”）: %d\n', rep.expectedFound.expectedCount);
fprintf(fid, '- 实际（基于OCR页面caption检索）: %d\n\n', rep.expectedFound.foundCount);

if rep.missing.nExpectedMissing
    fprintf(fid, '### 缺失的预期元素\n\n');
    for i = 1:rep.missing.nExpectedMissing
        fprintf(fid, '- %s\n', rep.missing.expectedLabels{i});
    end
    fprintf(fid, '\n');
end

if rep.missing.nCropMissing
    fprintf(fid, '### 缺失的裁剪文件\n\n');
    for i = 1:rep.missing.nCropMissing
        fprintf(fid, '- %s\n', rep.missing.cropFiles{i});
    end
    fprintf(fid, '\n');
end

fprintf(fid, '## 结论\n\n');
if (rep.missing.nExpectedMissing == 0) && (rep.missing.nCropMissing == 0) && rep.counts.pages > 0
    fprintf(fid, '结构化数据提取通过：页面图、表/图caption与裁剪产物均可用。\n');
else
    fprintf(fid, '结构化数据提取未完全通过：存在缺失项，需要人工复核对应页面与caption识别策略。\n');
end
end


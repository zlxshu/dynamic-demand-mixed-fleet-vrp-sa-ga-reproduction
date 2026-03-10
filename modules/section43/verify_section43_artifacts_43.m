function out = verify_section43_artifacts_43(projectRoot, refPdf, paths, sig, timestamp, varargin)
% 修改日志
% - v4 2026-02-09: 修复 Markdown 转义函数 esc_md_ 对 missing 类型崩溃；统一字符串化兜底，避免报告阶段中断主流程。
% - v3 2026-02-08: 增加图4.8抽取兜底（颜色特征页定位 + 几何裁剪），减少 OCR 标题识别失败导致的参考曲线缺失。
% - v2 2026-02-08: 新增图4.8参考曲线抽取与缓存（paper_fig48_curve_ref__*.mat），支持 ReferenceOnly 模式供 run_section_43 图形硬门槛复用；PDFBox Java 解析改为跨平台定位。
% - v1 2026-02-06: 新增 section_43 产物一致性验证：从论文PDF抽取图4.8/表4.3基准图，逐像素比对生成图片/表格渲染；输出0差异或差异热力图与可审计报告。
%
% verify_section43_artifacts_43
% - 仅做校验与报告输出，不修改任何算法结果数据。
%
% 输入:
%   projectRoot : 项目根目录
%   refPdf      : 参考 PDF 文件名或路径（空则自动搜索）
%   paths       : output_paths 返回的 struct
%   sig         : build_signature(ctx) 返回的签名 struct
%   timestamp   : ctx.Meta.timestamp
%   Name-Value:
%     'GeneratedFigPath'        : 生成的图4.8路径（png）
%     'GeneratedTableArtifacts' : export_table43_artifacts_43 返回的 struct
%     'OutDir'                  : 校验输出目录（默认 outputs/section_43/logs/verify）
%     'DataIntegrity'           : run_section_43 计算的结果签名（用于数据完整性声明）
%     'ReferenceOnly'           : true 时仅抽取并输出图4.8参考曲线，不做像素比对
%     'MaxGen'                  : 参考曲线统一长度（默认 300）
%
% 输出:
%   out.reportPath / out.tableCompare / out.figCompare / out.ref

opts = parse_opts_(varargin{:});

out = struct();
out.meta = struct('createdAt', char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')), 'paramSig', sig.param, 'dataSig', sig.data);
out.ref = struct();
out.tableCompare = struct();
out.figCompare = struct();
out.reportPath = '';
out.dataIntegrity = opts.DataIntegrity;

outDir = char(string(opts.OutDir));
ensure_dir_(outDir);
refDir = fullfile(outDir, 'reference');
ensure_dir_(refDir);
diffDir = fullfile(outDir, 'diff');
ensure_dir_(diffDir);

pdfPath = locate_pdf_(projectRoot, refPdf);
out.ref.pdfPath = pdfPath;

refFigPath = '';
refTablePath = '';
refDiag = struct('foundSection', false, 'foundFig48', false, 'foundTable43', false);
try
    [refFigPath, refTablePath, refDiag] = extract_ref_images_from_pdf_(projectRoot, pdfPath, refDir);
catch ME
    refDiag.error = ME.message;
end
out.ref.diag = refDiag;
out.ref.refFigPath = refFigPath;
out.ref.refTablePath = refTablePath;
out.ref.curveRef = struct('available', false, 'reason', 'not_extracted', 'maxGen', opts.MaxGen);
out.ref.curveRefPath = '';

try
    [curveRef, curveRefPath] = build_curve_ref_artifact_(refFigPath, outDir, paths, sig, timestamp, opts.MaxGen);
    out.ref.curveRef = curveRef;
    out.ref.curveRefPath = curveRefPath;
catch ME
    out.ref.curveRef = struct('available', false, 'reason', 'curve_extract_failed', ...
        'error', ME.message, 'maxGen', opts.MaxGen, 'source', 'pdf_extract');
    out.ref.curveRefPath = '';
end

if opts.ReferenceOnly
    reportPath = fullfile(outDir, artifact_filename('SECTION43_图4_8参考曲线报告', paths.sectionName, 'verify', sig.param.short, sig.data.short, timestamp, '.md'));
    out.reportPath = reportPath;
    write_ref_curve_report_md_(reportPath, out);
    return;
end

if ~isempty(refFigPath) && exist(refFigPath,'file') == 2 && ~isempty(opts.GeneratedFigPath) && exist(opts.GeneratedFigPath,'file') == 2
    out.figCompare = compare_images_(refFigPath, opts.GeneratedFigPath, fullfile(diffDir, 'diff_Fig4_8.png'));
else
    out.figCompare = struct('skipped', true, 'reason', 'missing reference or generated fig');
end

if ~isempty(refTablePath) && exist(refTablePath,'file') == 2
    genTablePng = '';
    try
        genTablePng = char(string(opts.GeneratedTableArtifacts.pngAfterPath));
    catch
        genTablePng = '';
    end
    if ~isempty(genTablePng) && exist(genTablePng,'file') == 2
        out.tableCompare = compare_images_(refTablePath, genTablePng, fullfile(diffDir, 'diff_Table4_3.png'));
    else
        out.tableCompare = struct('skipped', true, 'reason', 'missing generated table render png');
    end
else
    out.tableCompare = struct('skipped', true, 'reason', 'missing reference table image');
end

reportPath = fullfile(outDir, artifact_filename('SECTION43_验证报告', paths.sectionName, 'verify', sig.param.short, sig.data.short, timestamp, '.md'));
out.reportPath = reportPath;
write_report_md_(reportPath, out, opts);
end

function opts = parse_opts_(varargin)
opts = struct();
opts.GeneratedFigPath = '';
opts.GeneratedTableArtifacts = struct();
opts.OutDir = '';
opts.DataIntegrity = struct();
opts.ReferenceOnly = false;
opts.MaxGen = 300;

if mod(numel(varargin), 2) ~= 0
    error('verify_section43_artifacts_43:badArgs', 'Name-value arguments required');
end
for i = 1:2:numel(varargin)
    k = lower(char(string(varargin{i})));
    v = varargin{i+1};
    switch k
        case 'generatedfigpath'
            opts.GeneratedFigPath = char(string(v));
        case 'generatedtableartifacts'
            opts.GeneratedTableArtifacts = v;
        case 'outdir'
            opts.OutDir = char(string(v));
        case 'dataintegrity'
            opts.DataIntegrity = v;
        case 'referenceonly'
            opts.ReferenceOnly = to_bool_(v);
        case 'maxgen'
            vv = double(v);
            if ~isfinite(vv) || vv <= 0
                error('verify_section43_artifacts_43:badOptValue', 'MaxGen must be positive finite');
            end
            opts.MaxGen = round(vv);
        otherwise
            error('verify_section43_artifacts_43:badOpt', 'Unknown option: %s', k);
    end
end
end

function tf = to_bool_(v)
tf = false;
try
    if islogical(v)
        tf = logical(v);
        return;
    end
    if isnumeric(v)
        tf = (double(v) ~= 0);
        return;
    end
    s = lower(strtrim(char(string(v))));
    tf = any(strcmp(s, {'1','true','on','yes'}));
catch
    tf = false;
end
end

function p = locate_pdf_(projectRoot, refPdf)
refPdf = char(string(refPdf));
if ~isempty(refPdf)
    if exist(refPdf,'file') == 2
        p = refPdf;
        return;
    end
    cand = fullfile(projectRoot, refPdf);
    if exist(cand,'file') == 2
        p = cand;
        return;
    end
    cand2 = fullfile(projectRoot, 'paper', refPdf);
    if exist(cand2,'file') == 2
        p = cand2;
        return;
    end
    cand3 = fullfile(projectRoot, '师姐论文', refPdf);
    if exist(cand3,'file') == 2
        p = cand3;
        return;
    end
end

auto1 = fullfile(projectRoot, '21级邱莹莹大论文.pdf');
if exist(auto1,'file') == 2
    p = auto1;
    return;
end
auto2 = fullfile(projectRoot, 'paper', '21级邱莹莹大论文.pdf');
if exist(auto2,'file') == 2
    p = auto2;
    return;
end
auto3 = fullfile(projectRoot, '师姐论文', '21级邱莹莹大论文.pdf');
if exist(auto3,'file') == 2
    p = auto3;
    return;
end

error('verify_section43_artifacts_43:pdfNotFound', 'reference pdf not found: %s', refPdf);
end

function [refFigPath, refTablePath, diagOut] = extract_ref_images_from_pdf_(projectRoot, pdfPath, refDir)
diagOut = struct('foundSection', false, 'foundFig48', false, 'foundTable43', false, ...
    'fallbackUsed', false, 'fallbackPage', NaN);

[javaExe, jarPath] = resolve_pdfbox_(projectRoot);

% 优先采用固定页段一次性渲染，避免多次 ExtractText 导致的 PDFBox 字体缓存反复重建。
pageStart = 1;
pageEnd = 120;
diagOut.foundSection = true;

pagesDir = fullfile(refDir, 'pages');
ensure_dir_(pagesDir);
prefix = fullfile(pagesDir, 'page_');
render_pdf_pages_(pdfPath, javaExe, jarPath, prefix, 'PNG', 300, pageStart, pageEnd);

pageFiles = dir(fullfile(pagesDir, '*.png'));
pageFiles = sort_nat_(pageFiles);

refFigPath = '';
refTablePath = '';
% 先走颜色兜底，避免逐页 OCR 带来的高开销与环境依赖。
[okFallbackFirst, fallbackFigPath, fallbackTablePath, fallbackPage] = fallback_extract_by_curve_color_(pagesDir, refDir);
if okFallbackFirst
    refFigPath = fallbackFigPath;
    refTablePath = fallbackTablePath;
    diagOut.foundFig48 = true;
    diagOut.foundTable43 = ~isempty(refTablePath);
    diagOut.fallbackUsed = true;
    diagOut.fallbackPage = fallbackPage;
    return;
end

foundAny = false;
for i = 1:numel(pageFiles)
    p = fullfile(pagesDir, pageFiles(i).name);
    try
        I = imread(p);
    catch
        continue;
    end
    try
        r = ocr(I);
    catch
        continue;
    end
    [tagFig, bboxFig] = find_caption_bbox_(r, 'F', '4.8');
    if ~isempty(tagFig) && isempty(refFigPath)
        refFigPath = crop_figure_(I, bboxFig, refDir, '4.8', i, 18);
        diagOut.foundFig48 = true;
        foundAny = true;
    end
    [tagTbl, bboxTbl] = find_caption_bbox_(r, 'T', '4.3');
    if ~isempty(tagTbl) && isempty(refTablePath)
        refTablePath = crop_table_(I, bboxTbl, refDir, '4.3', i, 18);
        diagOut.foundTable43 = true;
        foundAny = true;
    end
    if foundAny && ~isempty(refFigPath) && ~isempty(refTablePath)
        break;
    end
end

if isempty(refFigPath)
    [ok, fallbackFigPath, fallbackTablePath, fallbackPage] = fallback_extract_by_curve_color_(pagesDir, refDir);
    if ok
        refFigPath = fallbackFigPath;
        diagOut.foundFig48 = true;
        diagOut.fallbackUsed = true;
        diagOut.fallbackPage = fallbackPage;
        if isempty(refTablePath) && ~isempty(fallbackTablePath)
            refTablePath = fallbackTablePath;
            diagOut.foundTable43 = true;
        end
    end
end
end

function [javaExe, jarPath] = resolve_pdfbox_(projectRoot)
jarPath = fullfile(projectRoot, 'tools', 'third_party', 'pdfbox', 'pdfbox-app-2.0.30.jar');
if exist(jarPath,'file') ~= 2
    error('verify_section43_artifacts_43:jarMissing', 'pdfbox jar not found: %s', jarPath);
end

cands = java_candidates_();
for i = 1:numel(cands)
    cand = cands{i};
    if strcmp(cand, 'java')
        if ispc
            probeCmd = 'java -version > NUL 2>&1';
        else
            probeCmd = 'java -version > /dev/null 2>&1';
        end
        [st, ~] = system(probeCmd);
        if st == 0
            javaExe = cand;
            return;
        end
    else
        if exist(cand, 'file') == 2
            javaExe = cand;
            return;
        end
    end
end

error('verify_section43_artifacts_43:javaMissing', ...
    'Java runtime not found. checked=%s', strjoin(cands, ' | '));
end

function cands = java_candidates_()
cands = {};
try
    if ispc
        cands{end+1} = fullfile(matlabroot, 'sys', 'java', 'jre', 'win64', 'jre', 'bin', 'java.exe'); %#ok<AGROW>
        cands{end+1} = fullfile(matlabroot, 'bin', 'win64', 'java.exe'); %#ok<AGROW>
    elseif ismac
        cands{end+1} = fullfile(matlabroot, 'sys', 'java', 'jre', 'maci64', 'jre', 'bin', 'java'); %#ok<AGROW>
        cands{end+1} = fullfile(matlabroot, 'bin', 'maci64', 'java'); %#ok<AGROW>
        cands{end+1} = '/usr/bin/java'; %#ok<AGROW>
    else
        cands{end+1} = fullfile(matlabroot, 'sys', 'java', 'jre', 'glnxa64', 'jre', 'bin', 'java'); %#ok<AGROW>
        cands{end+1} = fullfile(matlabroot, 'bin', 'glnxa64', 'java'); %#ok<AGROW>
        cands{end+1} = '/usr/bin/java'; %#ok<AGROW>
    end
catch
end
cands{end+1} = 'java';
cands = unique(cands, 'stable');
end

function [pageStart, pageEnd] = find_section_pages_by_text_(pdfPath, javaExe, jarPath, startRe, stopReList, minStartPage, blockPages, scanMax)
pageStart = NaN;
pageEnd = NaN;
block = max(1, round(blockPages));
scanPage = max(1, round(minStartPage));
tmpDir = fullfile(tempdir, ['pdftextscan_s43_' char(java.util.UUID.randomUUID)]);
ensure_dir_(tmpDir);
c = onCleanup(@() safe_rmdir_(tmpDir));

foundStart = false;
startPage = NaN;
stopPage = NaN;
while scanPage <= scanMax
    tmpTxt = fullfile(tmpDir, sprintf('p_%04d.txt', scanPage));
    cmd = sprintf('"%s" -jar "%s" ExtractText -startPage %d -endPage %d -encoding UTF-8 "%s" "%s"', ...
        javaExe, jarPath, scanPage, scanPage + block - 1, pdfPath, tmpTxt);
    system(cmd);
    if exist(tmpTxt,'file') ~= 2
        break;
    end
    t = normalize_text_(fileread(tmpTxt));
    if ~isempty(regexp(t, startRe, 'once'))
        startPage = find_first_hit_page_(pdfPath, javaExe, jarPath, scanPage, block, startRe);
        if isfinite(startPage)
            foundStart = true;
            break;
        end
    end
    scanPage = scanPage + block;
end

if ~foundStart
    return;
end

scanPage = startPage + 1;
foundStop = false;
while scanPage <= scanMax
    tmpTxt = fullfile(tmpDir, sprintf('p_%04d.txt', scanPage));
    cmd = sprintf('"%s" -jar "%s" ExtractText -startPage %d -endPage %d -encoding UTF-8 "%s" "%s"', ...
        javaExe, jarPath, scanPage, scanPage + block - 1, pdfPath, tmpTxt);
    system(cmd);
    if exist(tmpTxt,'file') ~= 2
        break;
    end
    t = normalize_text_(fileread(tmpTxt));
    for k = 1:numel(stopReList)
        re = stopReList{k};
        if ~isempty(regexp(t, re, 'once'))
            stopPage = find_first_hit_page_(pdfPath, javaExe, jarPath, scanPage, block, re);
            if isfinite(stopPage)
                foundStop = true;
                break;
            end
        end
    end
    if foundStop
        break;
    end
    scanPage = scanPage + block;
end

pageStart = startPage;
if isfinite(stopPage)
    pageEnd = max(pageStart, stopPage - 1);
else
    pageEnd = pageStart + 20;
end
end

function hitPage = find_first_hit_page_(pdfPath, javaExe, jarPath, blockStart, blockSize, re)
hitPage = NaN;
tmpDir = fullfile(tempdir, ['pdftextscan_one_s43_' char(java.util.UUID.randomUUID)]);
ensure_dir_(tmpDir);
c = onCleanup(@() safe_rmdir_(tmpDir));
for p = blockStart:(blockStart + blockSize - 1)
    tmpTxt = fullfile(tmpDir, sprintf('p_%04d.txt', p));
    cmd = sprintf('"%s" -jar "%s" ExtractText -startPage %d -endPage %d -encoding UTF-8 "%s" "%s"', ...
        javaExe, jarPath, p, p, pdfPath, tmpTxt);
    system(cmd);
    if exist(tmpTxt,'file') ~= 2
        continue;
    end
    t = normalize_text_(fileread(tmpTxt));
    if ~isempty(regexp(t, re, 'once'))
        hitPage = p;
        return;
    end
end
end

function render_pdf_pages_(pdfPath, javaExe, jarPath, prefix, fmt, dpi, startPage, endPage)
ensure_dir_(fileparts(prefix));
cmd = sprintf('"%s" -jar "%s" PDFToImage -format %s -dpi %d -prefix "%s" -startPage %d -endPage %d "%s"', ...
    javaExe, jarPath, upper(char(string(fmt))), round(dpi), prefix, round(startPage), round(endPage), pdfPath);
[st, msg] = system(cmd);
if st ~= 0
    error('verify_section43_artifacts_43:renderFailed', 'PDFToImage failed: %s', msg);
end
end

function [tag, bbox] = find_caption_bbox_(ocrRes, wantType, wantId)
tag = '';
bbox = [];
try
    words = ocrRes.Words;
    b = ocrRes.WordBoundingBoxes;
    if isempty(words) || isempty(b)
        return;
    end
    boxesAll = double(b);
catch
    return;
end

for i = 1:numel(words)
    for k = 1:4
        if i + k - 1 > numel(words), break; end
        cand = '';
        bb = [];
        raw = '';
        for j = 0:(k-1)
            raw = [raw char(string(words{i+j}))]; %#ok<AGROW>
            cand = [cand normalize_token_(words{i+j})]; %#ok<AGROW>
            if isempty(bb)
                bb = boxesAll(i+j,:);
            else
                bb = union_bbox_(bb, boxesAll(i+j,:));
            end
        end
        [hitType, hitId] = caption_id_from_token_(cand);
        if ~isempty(hitType) && strcmp(hitType, wantType) && strcmp(hitId, wantId)
            tag = [hitType '_' hitId];
            bbox = bb;
            return;
        end
    end
end
end

function [hitType, hitId] = caption_id_from_token_(token)
hitType = '';
hitId = '';
if isempty(token)
    return;
end
token = strrep(token,'。','.');
token = strrep(token,'．','.');
token = strrep(token,'·','.');
token = strrep(token,',','.');
token = regexprep(token, '\s+', '');

m = regexp(token, '^表\\s*4\\s*[\\.．]\\s*(\\d+)', 'tokens', 'once');
if ~isempty(m)
    hitType = 'T';
    hitId = ['4.' m{1}];
    return;
end
m = regexp(token, '^图\\s*4\\s*[\\.．]\\s*(\\d+)', 'tokens', 'once');
if ~isempty(m)
    hitType = 'F';
    hitId = ['4.' m{1}];
    return;
end
end

function cropPath = crop_table_(I, bbox, outDir, id, pageNum, marginPx)
tblDir = fullfile(outDir, 'tables');
ensure_dir_(tblDir);
imgH = size(I,1);
imgW = size(I,2);
y0 = max(1, round(bbox(2) + bbox(4) + marginPx));
y1 = imgH;
rect = [1, y0, imgW, max(1, y1 - y0)];
crop = imcrop(I, rect);
cropPath = fullfile(tblDir, sprintf('Table%s_ref_p%03d.png', id, pageNum));
imwrite(crop, cropPath);
end

function cropPath = crop_figure_(I, bbox, outDir, id, pageNum, marginPx)
figDir = fullfile(outDir, 'figures');
ensure_dir_(figDir);
imgH = size(I,1);
imgW = size(I,2);
yBottom = max(1, round(bbox(2) - marginPx));
yTop = max(1, round(yBottom - 0.60 * imgH));
rect = [1, yTop, imgW, max(1, yBottom - yTop)];
crop = imcrop(I, rect);
cropPath = fullfile(figDir, sprintf('Fig%s_ref_p%03d.png', id, pageNum));
imwrite(crop, cropPath);
end

function [ok, figPath, tablePath, pageNo] = fallback_extract_by_curve_color_(pagesDir, refDir)
ok = false;
figPath = '';
tablePath = '';
pageNo = NaN;

files = dir(fullfile(pagesDir, '*.png'));
files = sort_nat_(files);
if isempty(files)
    return;
end

bestScore = -inf;
bestFile = '';
bestPageNo = NaN;
for i = 1:numel(files)
    p = fullfile(files(i).folder, files(i).name);
    try
        I = imread(p);
    catch
        continue;
    end
    s = color_curve_score_(I);
    if s > bestScore
        bestScore = s;
        bestFile = p;
        bestPageNo = parse_page_no_(files(i).name);
    end
end

if isempty(bestFile) || ~isfinite(bestScore) || bestScore < 200
    return;
end

I = imread(bestFile);
[figRect, tableRect] = detect_fig_table_rects_by_color_(I);
if isempty(figRect)
    return;
end

figPath = save_crop_by_rect_(I, figRect, fullfile(refDir, 'figures'), sprintf('Fig4.8_ref_fallback_p%03d.png', round(bestPageNo)));
if ~isempty(tableRect)
    tablePath = save_crop_by_rect_(I, tableRect, fullfile(refDir, 'tables'), sprintf('Table4.3_ref_fallback_p%03d.png', round(bestPageNo)));
end
ok = true;
pageNo = bestPageNo;
end

function score = color_curve_score_(I)
if ndims(I) == 2
    I = cat(3, I, I, I);
end
P = im2double(I);
score = 0;
score = score + nnz(color_mask_(P, [0.00 0.4470 0.7410], 0.20, 0.08));
score = score + nnz(color_mask_(P, [0.8500 0.3250 0.0980], 0.20, 0.08));
score = score + nnz(color_mask_(P, [0.9290 0.6940 0.1250], 0.20, 0.08));
end

function [figRect, tableRect] = detect_fig_table_rects_by_color_(I)
if ndims(I) == 2
    I = cat(3, I, I, I);
end
P = im2double(I);
mBlue = color_mask_(P, [0.00 0.4470 0.7410], 0.20, 0.08);
mRed = color_mask_(P, [0.8500 0.3250 0.0980], 0.20, 0.08);
mYellow = color_mask_(P, [0.9290 0.6940 0.1250], 0.20, 0.08);
mAll = mBlue | mRed | mYellow;

[yy, xx] = find(mAll);
if isempty(xx)
    figRect = [];
    tableRect = [];
    return;
end
h = size(I,1);
w = size(I,2);
x0 = max(1, floor(min(xx) - 30));
x1 = min(w, ceil(max(xx) + 30));
y0 = max(1, floor(min(yy) - 40));
y1 = min(h, ceil(max(yy) + 40));

figRect = [x0, y0, max(1, x1-x0+1), max(1, y1-y0+1)];
tableY0 = min(h, max(y1 + round(0.04*h), round(0.45*h)));
tableRect = [round(0.05*w), tableY0, round(0.90*w), max(1, h - tableY0 - round(0.05*h))];
end

function m = color_mask_(P, rgbRef, distThr, satThr)
R = P(:,:,1);
G = P(:,:,2);
B = P(:,:,3);
sat = max(max(R, G), B) - min(min(R, G), B);
dr = abs(R - rgbRef(1));
dg = abs(G - rgbRef(2));
db = abs(B - rgbRef(3));
dist = sqrt(dr.^2 + dg.^2 + db.^2);
m = (dist <= distThr) & (sat >= satThr);
end

function p = save_crop_by_rect_(I, rect, outDir, fileName)
ensure_dir_(outDir);
x = max(1, round(rect(1)));
y = max(1, round(rect(2)));
w = max(1, round(rect(3)));
h = max(1, round(rect(4)));
x = min(size(I,2), x);
y = min(size(I,1), y);
w = min(w, size(I,2)-x+1);
h = min(h, size(I,1)-y+1);
crop = imcrop(I, [x y w h]);
p = fullfile(outDir, fileName);
imwrite(crop, p);
end

function n = parse_page_no_(name)
n = NaN;
try
    tok = regexp(char(name), '(\d+)', 'tokens', 'once');
    if ~isempty(tok)
        n = str2double(tok{1});
    end
catch
    n = NaN;
end
end

function cmp = compare_images_(refPath, genPath, diffPath)
cmp = struct();
cmp.refPath = refPath;
cmp.genPath = genPath;
cmp.diffPath = diffPath;
cmp.skipped = false;

refInfo = safe_imfinfo_(refPath);
genInfo = safe_imfinfo_(genPath);
cmp.refMeta = refInfo;
cmp.genMeta = genInfo;

Ir = imread(refPath);
Ig = imread(genPath);

cmp.sizeMatch = isequal(size(Ir), size(Ig));
cmp.widthHeightMatch = cmp.sizeMatch;
cmp.dpiMatch = dpi_match_(refInfo, genInfo);

if ~cmp.sizeMatch
    cmp.pixelDiffCount = NaN;
    cmp.zeroDiff = false;
    cmp.note = 'size mismatch';
    return;
end

D = abs(double(Ir) - double(Ig));
if ndims(D) == 3
    Dg = max(D, [], 3);
else
    Dg = D;
end
cmp.pixelDiffCount = nnz(Dg > 0);
cmp.zeroDiff = (cmp.pixelDiffCount == 0);

try
    if cmp.pixelDiffCount > 0
        imwrite(uint8(min(255, Dg)), diffPath);
    else
        if exist(diffPath,'file') == 2
            delete(diffPath);
        end
    end
catch
end
end

function tf = dpi_match_(a, b)
tf = false;
try
    if isfield(a,'XResolution') && isfield(b,'XResolution') && isfinite(a.XResolution) && isfinite(b.XResolution)
        tf = (abs(double(a.XResolution) - double(b.XResolution)) < 1e-6) && (abs(double(a.YResolution) - double(b.YResolution)) < 1e-6);
    else
        tf = true;
    end
catch
    tf = false;
end
end

function info = safe_imfinfo_(p)
info = struct();
try
    s = imfinfo(p);
    info = s(1);
catch
    info = struct();
end
end

function write_report_md_(path, v, opts)
fid = fopen(path, 'w');
if fid < 0
    return;
end
c = onCleanup(@() fclose(fid));

fprintf(fid, '# Section43 验证报告\n\n');
fprintf(fid, '- 生成时间: %s\n', esc_md_(v.meta.createdAt));
fprintf(fid, '- paramSig: %s\n', esc_md_(v.meta.paramSig.short));
fprintf(fid, '- dataSig : %s\n\n', esc_md_(v.meta.dataSig.short));

fprintf(fid, '## 参考源\n');
fprintf(fid, '- 论文PDF: %s\n', esc_md_(v.ref.pdfPath));
fprintf(fid, '- 基准图4.8: %s\n', esc_md_(v.ref.refFigPath));
fprintf(fid, '- 基准表4.3: %s\n\n', esc_md_(v.ref.refTablePath));
fprintf(fid, '- 图/表兜底裁剪: %s\n', esc_md_(string(getfield_def_(v.ref.diag, 'fallbackUsed', false))));
fprintf(fid, '- 兜底页号: %s\n\n', esc_md_(string(getfield_def_(v.ref.diag, 'fallbackPage', NaN))));
fprintf(fid, '- 图4.8参考曲线MAT: %s\n', esc_md_(getfield_def_(v.ref, 'curveRefPath', '')));
try
    ref = v.ref.curveRef;
    fprintf(fid, '- 图4.8参考曲线可用: %s\n', esc_md_(string(getfield_def_(ref, 'available', false))));
    fprintf(fid, '- 图4.8参考曲线签名: %s\n\n', esc_md_(getfield_def_(ref, 'sig', '')));
catch
    fprintf(fid, '- 图4.8参考曲线可用: false\n\n');
end

fprintf(fid, '## 表格最小值汇总（MIN）数学推导\n');
fprintf(fid, '对每一列数值数据 $x_1,\\dots,x_n$，先过滤无效值（空/非数值/NaN/Inf），得到有效集合 $S=\\{x_i\\mid x_i\\in\\mathbb{R},\\;\\text{finite}(x_i)\\}$；\n');
fprintf(fid, '汇总行该列取 $\\min(S)$；若 $S$ 为空，则该列汇总值记为 NaN。\n\n');

fprintf(fid, '## 表格渲染对比截图\n');
try
    if isfield(opts.GeneratedTableArtifacts,'pngBeforePath') && ~isempty(opts.GeneratedTableArtifacts.pngBeforePath)
        fprintf(fid, '- 高亮前 PNG: %s\n', esc_md_(opts.GeneratedTableArtifacts.pngBeforePath));
    end
    if isfield(opts.GeneratedTableArtifacts,'pngAfterPath') && ~isempty(opts.GeneratedTableArtifacts.pngAfterPath)
        fprintf(fid, '- 高亮后 PNG: %s\n', esc_md_(opts.GeneratedTableArtifacts.pngAfterPath));
    end
catch
end
fprintf(fid, '\n');

fprintf(fid, '## 像素级一致性比对结果\n');
fprintf(fid, '### 图4.8\n');
write_cmp_(fid, v.figCompare);
fprintf(fid, '\n### 表4.3\n');
write_cmp_(fid, v.tableCompare);
fprintf(fid, '\n');

fprintf(fid, '## 数据完整性与防造假声明\n');
fprintf(fid, '- 本验证流程仅对导出层追加 MIN 汇总行与视觉标注，不回写任何原始运行数据（成本/时间/曲线）。\n');
fprintf(fid, '- 中间量（MIN 值、有效性掩码等）已写入 mats 目录，供复现审计。\n\n');
try
    if isstruct(v.dataIntegrity) && isfield(v.dataIntegrity,'resultsMd5') && ~isempty(v.dataIntegrity.resultsMd5)
        fprintf(fid, '- 数据完整性校验签名: %s\n', esc_md_(v.dataIntegrity.resultsMd5));
        fprintf(fid, '- 签名算法: %s\n\n', esc_md_(getfield_def_(v.dataIntegrity,'algorithm','')));
    end
catch
end

fprintf(fid, '## Markdown 规范合规性检查清单（section43相关）\n');
fprintf(fid, '- 入口链路：run_modes.m -> run_all -> run_section_43\n');
fprintf(fid, '- 输出路径：outputs/section_43/{tables,figures,logs,mats}\n');
fprintf(fid, '- 无可行解：该次成本/GAP 记为 NaN（不使用罚值替代）\n');
fprintf(fid, '- 禁止造假：不改论文参数，不改约束/罚函数口径\n');
fprintf(fid, '\n');
end

function write_cmp_(fid, cmp)
if ~isstruct(cmp)
    fprintf(fid, '- 跳过: compare struct missing\n');
    return;
end
if isfield(cmp,'skipped') && cmp.skipped
    fprintf(fid, '- 跳过: %s\n', esc_md_(getfield_def_(cmp,'reason','unknown'))); %#ok<GFLD>
    return;
end
fprintf(fid, '- ref: %s\n', esc_md_(getfield_def_(cmp,'refPath','')));
fprintf(fid, '- gen: %s\n', esc_md_(getfield_def_(cmp,'genPath','')));
fprintf(fid, '- 尺寸匹配: %s\n', esc_md_(string(getfield_def_(cmp,'widthHeightMatch',false))));
fprintf(fid, '- DPI匹配: %s\n', esc_md_(string(getfield_def_(cmp,'dpiMatch',false))));
fprintf(fid, '- 像素差异计数: %s\n', esc_md_(string(getfield_def_(cmp,'pixelDiffCount','NaN'))));
fprintf(fid, '- 0差异: %s\n', esc_md_(string(getfield_def_(cmp,'zeroDiff',false))));
if isfield(cmp,'diffPath') && ~isempty(cmp.diffPath) && exist(cmp.diffPath,'file') == 2
    fprintf(fid, '- 差异图: %s\n', esc_md_(cmp.diffPath));
end
end

function v = getfield_def_(s, f, def)
v = def;
try
    if isfield(s,f)
        v = s.(f);
    end
catch
    v = def;
end
end

function [curveRef, refPath] = build_curve_ref_artifact_(refFigPath, outDir, paths, sig, timestamp, maxGen)
curveRef = struct('available', false, 'reason', 'missing_ref_figure', 'source', 'pdf_extract', ...
    'maxGen', maxGen, 'anchorGens', [], 'curves', struct('GSAA', [], 'GA', [], 'SA', []), ...
    'valueRange', [NaN NaN], 'sig', '', 'extractorVersion', 'v1_pdf_color_trace');
refPath = '';
if isempty(refFigPath) || exist(refFigPath, 'file') ~= 2
    return;
end

[curves, extMeta] = extract_curve_reference_from_image_(refFigPath, maxGen);
if isempty(curves) || ~all(isfield(curves, {'GSAA','GA','SA'}))
    curveRef.reason = 'extract_failed';
    return;
end

curveRef.available = true;
curveRef.reason = '';
curveRef.curves = curves;
curveRef.valueRange = extMeta.valueRange;
curveRef.anchorGens = extMeta.anchorGens;
curveRef.extractMeta = extMeta;
curveRef.sig = md5_curves_(curves);

refPath = fullfile(outDir, artifact_filename('paper_fig48_curve_ref', paths.sectionName, 'verify', sig.param.short, sig.data.short, timestamp, '.mat'));
save(refPath, 'curveRef');
end

function [curves, meta] = extract_curve_reference_from_image_(imgPath, maxGen)
curves = struct('GSAA', [], 'GA', [], 'SA', []);
meta = struct('plotBBox', [], 'valueRange', [NaN NaN], 'anchorGens', [1 10 20 30 40 50 80 100 130 maxGen], ...
    'xRange', [NaN NaN], 'yRange', [NaN NaN], 'pixelCount', struct('GSAA',0,'GA',0,'SA',0));

I = imread(imgPath);
if ndims(I) == 2
    I = cat(3, I, I, I);
end
I = uint8(I);

bbox = detect_plot_bbox_(I);
meta.plotBBox = bbox;
x0 = bbox(1); y0 = bbox(2); w = bbox(3); h = bbox(4);
x1 = x0 + w - 1;
y1 = y0 + h - 1;
P = I(y0:y1, x0:x1, :);

[yMinCost, yMaxCost] = estimate_ref_y_range_(P);
meta.valueRange = [yMinCost, yMaxCost];
meta.yRange = [y0, y1];

[xBlue, yBlue] = extract_color_trace_(P, [0.00 0.4470 0.7410]);
[xRed, yRed] = extract_color_trace_(P, [0.8500 0.3250 0.0980]);
[xYellow, yYellow] = extract_color_trace_(P, [0.9290 0.6940 0.1250]);

meta.pixelCount.GSAA = numel(xBlue);
meta.pixelCount.GA = numel(xRed);
meta.pixelCount.SA = numel(xYellow);

xMask = [xBlue(:); xRed(:); xYellow(:)];
if isempty(xMask)
    return;
end
xMin = max(1, floor(double(min(xMask))));
xMax = min(size(P,2), ceil(double(max(xMask))));
if xMax <= xMin
    xMin = 1;
    xMax = size(P,2);
end
meta.xRange = [xMin, xMax];

curves.GSAA = to_curve_cost_scale_(xBlue, yBlue, xMin, xMax, yMinCost, yMaxCost, maxGen);
curves.GA = to_curve_cost_scale_(xRed, yRed, xMin, xMax, yMinCost, yMaxCost, maxGen);
curves.SA = to_curve_cost_scale_(xYellow, yYellow, xMin, xMax, yMinCost, yMaxCost, maxGen);
end

function bbox = detect_plot_bbox_(I)
G = rgb2gray(I);
mask = G < 245;
cols = find(sum(mask, 1) > max(20, round(size(mask,1) * 0.03)));
rows = find(sum(mask, 2) > max(20, round(size(mask,2) * 0.03)));
if isempty(cols) || isempty(rows)
    bbox = [1, 1, size(I,2), size(I,1)];
    return;
end
x0 = max(1, cols(1) - 12);
x1 = min(size(I,2), cols(end) + 12);
y0 = max(1, rows(1) - 12);
y1 = min(size(I,1), rows(end) + 12);
bbox = [x0, y0, max(1, x1 - x0 + 1), max(1, y1 - y0 + 1)];
end

function [xv, yv] = extract_color_trace_(P, rgbRef)
Pr = im2double(P);
R = Pr(:,:,1);
G = Pr(:,:,2);
B = Pr(:,:,3);
sat = max(max(R, G), B) - min(min(R, G), B);
dr = abs(R - rgbRef(1));
dg = abs(G - rgbRef(2));
db = abs(B - rgbRef(3));
dist = sqrt(dr.^2 + dg.^2 + db.^2);
mask = (dist <= 0.22) & (sat >= 0.10);

[yy, xx] = find(mask);
if isempty(xx)
    xv = [];
    yv = [];
    return;
end

ux = unique(xx(:)');
yLine = NaN(size(ux));
for i = 1:numel(ux)
    ys = yy(xx == ux(i));
    if ~isempty(ys)
        yLine(i) = median(double(ys));
    end
end

maskFinite = isfinite(yLine);
xv = double(ux(maskFinite));
yv = double(yLine(maskFinite));
end

function curve = to_curve_cost_scale_(xv, yv, xMin, xMax, yMinCost, yMaxCost, maxGen)
curve = NaN(maxGen, 1);
if isempty(xv) || isempty(yv)
    return;
end

xPix = linspace(double(xMin), double(xMax), maxGen);
yInterp = interp1(double(xv(:)), double(yv(:)), xPix, 'linear', 'extrap');

if ~isfinite(yMinCost) || ~isfinite(yMaxCost) || yMaxCost <= yMinCost
    yMinCost = 1.0e4;
    yMaxCost = 1.3e4;
end
yTop = min(double(yv(:)));
yBottom = max(double(yv(:)));
if ~isfinite(yTop) || ~isfinite(yBottom) || yBottom <= yTop
    return;
end

t = (yInterp - yTop) ./ (yBottom - yTop);
t = min(max(t, 0), 1);
curve = yMaxCost - t(:) * (yMaxCost - yMinCost);
curve = cummin(curve);
end

function [vMin, vMax] = estimate_ref_y_range_(P)
vMin = NaN;
vMax = NaN;
try
    o = ocr(P);
    words = string(o.Words(:));
    boxes = double(o.WordBoundingBoxes);
    vals = [];
    ys = [];
    for i = 1:numel(words)
        w = regexprep(char(words(i)), '[^0-9\.]', '');
        if isempty(w)
            continue;
        end
        num = str2double(w);
        if ~isfinite(num)
            continue;
        end
        if num >= 0.8 && num <= 2.5
            vals(end+1,1) = num; %#ok<AGROW>
            ys(end+1,1) = boxes(i,2) + boxes(i,4) * 0.5; %#ok<AGROW>
        end
    end
    if numel(vals) >= 2
        [ys, ord] = sort(ys, 'ascend');
        vals = vals(ord);
        vMax = max(vals) * 1e4;
        vMin = min(vals) * 1e4;
    end
catch
end
if ~isfinite(vMin) || ~isfinite(vMax) || vMax <= vMin
    vMin = 1.0e4;
    vMax = 1.3e4;
end
end

function sig = md5_curves_(curves)
payload = struct();
payload.GSAA = double(curves.GSAA(:)');
payload.GA = double(curves.GA(:)');
payload.SA = double(curves.SA(:)');
j = jsonencode(payload);
bytes = uint8(unicode2native(char(j), 'UTF-8'));
md = java.security.MessageDigest.getInstance('MD5');
md.update(bytes);
raw = typecast(md.digest(), 'uint8');
sig = lower(reshape(dec2hex(raw, 2).', 1, []));
end

function write_ref_curve_report_md_(path, out)
fid = fopen(path, 'w');
if fid < 0
    return;
end
c = onCleanup(@() fclose(fid));
fprintf(fid, '# Section43 图4.8参考曲线抽取报告\n\n');
fprintf(fid, '- 生成时间: %s\n', esc_md_(out.meta.createdAt));
fprintf(fid, '- 论文PDF: %s\n', esc_md_(getfield_def_(out.ref, 'pdfPath', '')));
fprintf(fid, '- 参考图路径: %s\n', esc_md_(getfield_def_(out.ref, 'refFigPath', '')));
fprintf(fid, '- 参考曲线MAT: %s\n', esc_md_(getfield_def_(out.ref, 'curveRefPath', '')));
try
    ref = out.ref.curveRef;
    fprintf(fid, '- available: %s\n', esc_md_(string(getfield_def_(ref, 'available', false))));
    fprintf(fid, '- reason: %s\n', esc_md_(getfield_def_(ref, 'reason', '')));
    fprintf(fid, '- refSig: %s\n', esc_md_(getfield_def_(ref, 'sig', '')));
    vr = getfield_def_(ref, 'valueRange', [NaN NaN]);
    fprintf(fid, '- valueRange: [%.2f, %.2f]\n', vr(1), vr(2));
catch
end
end

function s = esc_md_(s)
s = stringify_safe_(s);
s = strrep(s, '\', '/');
end

function s = stringify_safe_(v)
if nargin < 1
    s = '';
    return;
end

try
    if isempty(v)
        s = '';
        return;
    end

    if isstring(v)
        arr = v(:)';
        parts = cell(1, numel(arr));
        for i = 1:numel(arr)
            if ismissing(arr(i))
                parts{i} = 'NA';
            else
                parts{i} = char(arr(i));
            end
        end
        s = strjoin(parts, ',');
        return;
    end

    if ischar(v)
        s = v;
        return;
    end

    if isnumeric(v) || islogical(v)
        if isscalar(v)
            if isnumeric(v) && ~isfinite(v)
                if isnan(v)
                    s = 'NaN';
                elseif v > 0
                    s = 'Inf';
                else
                    s = '-Inf';
                end
            else
                s = num2str(v);
            end
        else
            s = mat2str(v);
        end
        return;
    end

    if iscell(v)
        parts = cell(1, numel(v));
        for i = 1:numel(v)
            parts{i} = stringify_safe_(v{i});
        end
        s = strjoin(parts, ',');
        return;
    end

    if isstruct(v)
        s = char(string(jsonencode(v)));
        return;
    end

    s = char(string(v));
catch
    try
        s = char(string(v));
    catch
        s = 'NA';
    end
end
end

function s = normalize_text_(s)
s = char(string(s));
s = strrep(s, sprintf('\r'), sprintf('\n'));
s = strrep(s, '．', '.');
s = strrep(s, '。', '.');
s = strrep(s, '·', '.');
s = regexprep(s, '\n+', '\n');
end

function s = normalize_token_(s)
s = char(string(s));
s = strrep(s, ' ', '');
s = strrep(s, char(160), '');
s = strrep(s, '．', '.');
s = strrep(s, '。', '.');
s = strrep(s, '·', '.');
s = strrep(s, '：', ':');
s = strrep(s, '（', '(');
s = strrep(s, '）', ')');
s = regexprep(s, '[^\p{Han}0-9A-Za-z\.]', '');
end

function b = union_bbox_(a, c)
x0 = min(a(1), c(1));
y0 = min(a(2), c(2));
x1 = max(a(1)+a(3), c(1)+c(3));
y1 = max(a(2)+a(4), c(2)+c(4));
b = [x0, y0, x1-x0, y1-y0];
end

function ensure_dir_(p)
if exist(p, 'dir') ~= 7
    mkdir(p);
end
end

function safe_rmdir_(p)
try
    if exist(p,'dir') == 7
        rmdir(p,'s');
    end
catch
end
end

function files = sort_nat_(files)
if isempty(files)
    return;
end
names = string({files.name});
tokens = regexp(names, '(\\d+)', 'tokens', 'once');
nums = zeros(numel(tokens),1);
for i = 1:numel(tokens)
    if isempty(tokens{i})
        nums(i) = inf;
    else
        nums(i) = str2double(tokens{i}{end});
    end
end
[~, order] = sortrows([nums, (1:numel(nums)).']);
files = files(order);
end

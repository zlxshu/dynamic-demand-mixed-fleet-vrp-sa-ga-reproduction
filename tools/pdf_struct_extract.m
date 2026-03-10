function out = pdf_struct_extract(pdfPath, outDir, cfg)
if nargin < 3 || isempty(cfg)
    cfg = struct();
end

if ~isfield(cfg,'dpiScan') || isempty(cfg.dpiScan), cfg.dpiScan = 120; end
if ~isfield(cfg,'dpiFinal') || isempty(cfg.dpiFinal), cfg.dpiFinal = 220; end
if ~isfield(cfg,'scanBlockPages') || isempty(cfg.scanBlockPages), cfg.scanBlockPages = 8; end
if ~isfield(cfg,'startHeadingRegex') || isempty(cfg.startHeadingRegex), cfg.startHeadingRegex = '5\s*[\.．]\s*4\s*[\.．]\s*1'; end
if ~isfield(cfg,'stopHeadingRegex') || isempty(cfg.stopHeadingRegex), cfg.stopHeadingRegex = '5\s*[\.．]\s*4\s*[\.．]\s*2'; end
if ~isfield(cfg,'minStartPage') || isempty(cfg.minStartPage), cfg.minStartPage = 25; end
if ~isfield(cfg,'maxSectionMarkersPerPage') || isempty(cfg.maxSectionMarkersPerPage), cfg.maxSectionMarkersPerPage = 8; end
if ~isfield(cfg,'pageStart') || isempty(cfg.pageStart), cfg.pageStart = []; end
if ~isfield(cfg,'pageEnd') || isempty(cfg.pageEnd), cfg.pageEnd = []; end
if ~isfield(cfg,'format') || isempty(cfg.format), cfg.format = 'bmp'; end
if ~isfield(cfg,'extractImages') || isempty(cfg.extractImages), cfg.extractImages = true; end
if ~isfield(cfg,'runOcr') || isempty(cfg.runOcr), cfg.runOcr = true; end
if ~isfield(cfg,'captionMarginPx') || isempty(cfg.captionMarginPx), cfg.captionMarginPx = 18; end
if ~isfield(cfg,'cleanOutput') || isempty(cfg.cleanOutput), cfg.cleanOutput = true; end

pdfPath = char(string(pdfPath));
outDir = char(string(outDir));

if exist(pdfPath, 'file') ~= 2
    error('pdf_struct_extract:pdfMissing', 'pdf not found: %s', pdfPath);
end
ensure_dir_(outDir);

toolsDir = fileparts(mfilename('fullpath'));
jarPath = fullfile(toolsDir, 'third_party', 'pdfbox', 'pdfbox-app-2.0.30.jar');
if exist(jarPath,'file') ~= 2
    error('pdf_struct_extract:jarMissing', 'pdfbox jar not found: %s', jarPath);
end

javaExe = fullfile(matlabroot, 'sys', 'java', 'jre', 'win64', 'jre', 'bin', 'java.exe');
if exist(javaExe,'file') ~= 2
    error('pdf_struct_extract:javaMissing', 'java.exe not found under matlabroot: %s', javaExe);
end

scanPageStart = cfg.pageStart;
scanPageEnd = cfg.pageEnd;
scanDiag = struct();
if isempty(scanPageStart) || isempty(scanPageEnd)
    [scanPageStart, scanPageEnd, scanDiag] = find_section_pages_by_text_(pdfPath, javaExe, jarPath, cfg);
end

pagesDir = fullfile(outDir, 'pages');
if cfg.cleanOutput
    safe_rmdir_(pagesDir);
    safe_rmdir_(fullfile(outDir,'tables'));
    safe_rmdir_(fullfile(outDir,'figures'));
    safe_rmdir_(fullfile(outDir,'embedded_images'));
    delete_if_exists_(fullfile(outDir,'captions.csv'));
    delete_if_exists_(fullfile(outDir,'index.mat'));
end
ensure_dir_(pagesDir);
pagesPrefix = fullfile(pagesDir, 'page_');
render_pdf_pages_(pdfPath, javaExe, jarPath, pagesPrefix, cfg.format, cfg.dpiFinal, scanPageStart, scanPageEnd);

imagesDir = fullfile(outDir, 'embedded_images');
if cfg.extractImages
    ensure_dir_(imagesDir);
    extract_images_(pdfPath, javaExe, jarPath, imagesDir);
end

meta = struct();
meta.pdfPath = pdfPath;
meta.section = struct('pageStart', scanPageStart, 'pageEnd', scanPageEnd, 'startHeadingRegex', cfg.startHeadingRegex, 'stopHeadingRegex', cfg.stopHeadingRegex, 'scan', scanDiag);
meta.render = struct('dpiFinal', cfg.dpiFinal, 'format', cfg.format);
meta.createdAt = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));

captions = [];
ocrPages = [];
if cfg.runOcr
    [captions, ocrPages] = detect_and_crop_captions_(pagesDir, outDir, cfg.captionMarginPx);
end

save(fullfile(outDir, 'index.mat'), 'meta', 'captions', 'ocrPages');
write_caption_csv_(fullfile(outDir, 'captions.csv'), captions);

out = struct();
out.meta = meta;
out.paths = struct('outDir', outDir, 'pagesDir', pagesDir, 'imagesDir', imagesDir);
out.captions = captions;
out.ocrPages = ocrPages;
end

function [pageStart, pageEnd, diagOut] = find_section_pages_by_text_(pdfPath, javaExe, jarPath, cfg)
diagOut = struct('method','pdfbox_extracttext','foundStart',false,'foundStop',false,'startPage',NaN,'stopPage',NaN,'scanBlockPages',cfg.scanBlockPages);

block = max(1, round(cfg.scanBlockPages));
startRe = cfg.startHeadingRegex;
stopRe = cfg.stopHeadingRegex;

foundStart = false;
foundStop = false;
startPage = NaN;
stopPage = NaN;

tmpDir = fullfile(tempdir, ['pdftextscan_' char(java.util.UUID.randomUUID)]);
ensure_dir_(tmpDir);
c = onCleanup(@() safe_rmdir_(tmpDir));

scanPage = max(1, round(cfg.minStartPage));
scanMax = 900;
while scanPage <= scanMax
    tmpTxt = fullfile(tmpDir, sprintf('p_%04d.txt', scanPage));
    cmd = sprintf('"%s" -jar "%s" ExtractText -startPage %d -endPage %d -encoding UTF-8 "%s" "%s"', ...
        javaExe, jarPath, scanPage, scanPage + block - 1, pdfPath, tmpTxt);
    system(cmd);
    if exist(tmpTxt,'file') ~= 2
        break;
    end
    t = fileread(tmpTxt);
    t = normalize_text_(t);
    if ~isempty(regexp(t, startRe, 'once'))
        startPage = find_first_hit_page_in_block_(pdfPath, javaExe, jarPath, scanPage, block, startRe, cfg);
        if isfinite(startPage)
            foundStart = true;
            break;
        end
    end
    scanPage = scanPage + block;
end

if foundStart
    scanPage = startPage + 1;
    while scanPage <= scanMax
        tmpTxt = fullfile(tmpDir, sprintf('p_%04d.txt', scanPage));
        cmd = sprintf('"%s" -jar "%s" ExtractText -startPage %d -endPage %d -encoding UTF-8 "%s" "%s"', ...
            javaExe, jarPath, scanPage, scanPage + block - 1, pdfPath, tmpTxt);
        system(cmd);
        if exist(tmpTxt,'file') ~= 2
            break;
        end
        t = fileread(tmpTxt);
        t = normalize_text_(t);
        if ~isempty(regexp(t, stopRe, 'once'))
            stopPage = find_first_hit_page_in_block_(pdfPath, javaExe, jarPath, scanPage, block, stopRe, cfg);
            if isfinite(stopPage)
                foundStop = true;
                break;
            end
        end
        scanPage = scanPage + block;
    end
end

diagOut.foundStart = foundStart;
diagOut.foundStop = foundStop;
diagOut.startPage = startPage;
diagOut.stopPage = stopPage;

if ~foundStart
    diagOut.method = 'fallback_ocr';
    [pageStart, pageEnd, diagOcr] = find_section_pages_by_ocr_(pdfPath, javaExe, jarPath, cfg);
    diagOut.fallback = diagOcr;
    return;
end

pageStart = startPage;
if foundStop
    pageEnd = max(pageStart, stopPage - 1);
else
    pageEnd = pageStart + 20;
end
end

function hitPage = find_first_hit_page_in_block_(pdfPath, javaExe, jarPath, blockStart, blockSize, re, cfg)
hitPage = NaN;
tmpDir = fullfile(tempdir, ['pdftextscan_one_' char(java.util.UUID.randomUUID)]);
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
    t = fileread(tmpTxt);
    t = normalize_text_(t);
    if ~isempty(regexp(t, re, 'once'))
        if ~is_toc_like_(t, cfg)
            hitPage = p;
            return;
        end
    end
end
end

function tf = is_toc_like_(t, cfg)
t = normalize_text_(t);
markers = regexp(t, '\d+\s*[\.．]\s*\d+\s*[\.．]\s*\d+', 'match');
tf = numel(markers) >= cfg.maxSectionMarkersPerPage;
end

function [pageStart, pageEnd, diagOut] = find_section_pages_by_ocr_(pdfPath, javaExe, jarPath, cfg)
diagOut = struct('foundStart',false,'foundStop',false,'startPage',NaN,'stopPage',NaN,'scanDpi',cfg.dpiScan,'scanBlockPages',cfg.scanBlockPages);
tmpDir = fullfile(tempdir, ['pdfscan_' char(java.util.UUID.randomUUID)]);
ensure_dir_(tmpDir);
c = onCleanup(@() safe_rmdir_(tmpDir));

pageStart = [];
pageEnd = [];
block = max(1, round(cfg.scanBlockPages));
dpi = max(72, round(cfg.dpiScan));
startRe = cfg.startHeadingRegex;
stopRe = cfg.stopHeadingRegex;

foundStart = false;
foundStop = false;
startPage = NaN;
stopPage = NaN;

scanPage = 1;
scanMax = 600;
while scanPage <= scanMax
    prefix = fullfile(tmpDir, sprintf('scan_%04d_', scanPage));
    render_pdf_pages_(pdfPath, javaExe, jarPath, prefix, 'png', dpi, scanPage, scanPage + block - 1);
    pngs = dir(fullfile(tmpDir, sprintf('scan_%04d_*.png', scanPage)));
    if isempty(pngs)
        break;
    end
    for i = 1:numel(pngs)
        p = fullfile(tmpDir, pngs(i).name);
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
        t = normalize_text_(r.Text);
        if ~foundStart && ~isempty(regexp(t, startRe, 'once'))
            foundStart = true;
            startPage = page_num_from_filename_(pngs(i).name, scanPage);
        end
        if foundStart && ~foundStop && ~isempty(regexp(t, stopRe, 'once'))
            foundStop = true;
            stopPage = page_num_from_filename_(pngs(i).name, scanPage);
            break;
        end
    end
    if foundStop
        break;
    end
    scanPage = scanPage + block;
end

diagOut.foundStart = foundStart;
diagOut.foundStop = foundStop;
diagOut.startPage = startPage;
diagOut.stopPage = stopPage;

if ~foundStart
    error('pdf_struct_extract:sectionNotFound', 'failed to locate section start by OCR using regex: %s', startRe);
end
pageStart = startPage;
if foundStop
    pageEnd = max(pageStart, stopPage - 1);
else
    pageEnd = pageStart + 20;
end
end

function n = page_num_from_filename_(name, fallbackStart)
n = fallbackStart;
tok = regexp(name, '_(\\d+)\\.', 'tokens', 'once');
if isempty(tok)
    tok = regexp(name, '_(\\d+)$', 'tokens', 'once');
end
if ~isempty(tok)
    v = str2double(tok{1});
    if isfinite(v)
        n = v;
    end
end
end

function render_pdf_pages_(pdfPath, javaExe, jarPath, prefix, fmt, dpi, startPage, endPage)
ensure_dir_(fileparts(prefix));
fmt = upper(char(string(fmt)));
cmd = sprintf('"%s" -jar "%s" PDFToImage -format %s -dpi %d -prefix "%s" -startPage %d -endPage %d "%s"', ...
    javaExe, jarPath, fmt, round(dpi), prefix, round(startPage), round(endPage), pdfPath);
[st, msg] = system(cmd);
if st ~= 0
    error('pdf_struct_extract:renderFailed', 'PDFToImage failed: %s', msg);
end
end

function extract_images_(pdfPath, javaExe, jarPath, outDir)
ensure_dir_(outDir);
prefix = fullfile(outDir, 'img');
cmd = sprintf('"%s" -jar "%s" ExtractImages -prefix "%s" "%s"', javaExe, jarPath, prefix, pdfPath);
system(cmd);
end

function [captions, ocrPages] = detect_and_crop_captions_(pagesDir, outDir, marginPx)
tblDir = fullfile(outDir, 'tables');
figDir = fullfile(outDir, 'figures');
ensure_dir_(tblDir);
ensure_dir_(figDir);

pageFiles = dir(fullfile(pagesDir, '*.png'));
pageFiles = [pageFiles; dir(fullfile(pagesDir, '*.jpg'))];
pageFiles = [pageFiles; dir(fullfile(pagesDir, '*.jpeg'))];
pageFiles = [pageFiles; dir(fullfile(pagesDir, '*.bmp'))];
pageFiles = sort_nat_(pageFiles);

captions = struct('type',{},'id',{},'page',{},'captionText',{},'bbox',{},'cropPath',{},'pagePath',{},'ocrSnippet',{});
ocrPages = struct('page',{},'pagePath',{},'text',{});

for i = 1:numel(pageFiles)
    pagePath = fullfile(pagesDir, pageFiles(i).name);
    I = imread(pagePath);
    r = ocr(I);
    t = normalize_text_(r.Text);

    ocrPages(end+1).page = i; %#ok<AGROW>
    ocrPages(end).pagePath = pagePath;
    ocrPages(end).text = t;

    [hits, hitBoxes, hitText] = find_caption_hits_(r);
    if isempty(hits)
        continue;
    end

    [~, ord] = sort(hitBoxes(:,2));
    hits = hits(ord);
    hitBoxes = hitBoxes(ord,:);
    hitText = hitText(ord);

    for j = 1:numel(hits)
        tag = hits{j};
        bbox = hitBoxes(j,:);
        ctype = 'unknown';
        if startsWith(tag,'T_'), ctype = 'table'; end
        if startsWith(tag,'F_'), ctype = 'figure'; end
        id = tag(3:end);
        cropPath = '';
        if strcmp(ctype,'table')
            cropPath = crop_table_(I, bbox, hitBoxes, j, tblDir, id, i, marginPx);
        elseif strcmp(ctype,'figure')
            cropPath = crop_figure_(I, bbox, figDir, id, i, marginPx);
        end
        captions(end+1).type = ctype; %#ok<AGROW>
        captions(end).id = id;
        captions(end).page = i;
        captions(end).captionText = hitText{j};
        captions(end).bbox = bbox;
        captions(end).cropPath = cropPath;
        captions(end).pagePath = pagePath;
        captions(end).ocrSnippet = snippet_around_(t, hitText{j});
    end
end
end

function cropPath = crop_table_(I, bbox, allBoxes, idx, outDir, id, pageNum, marginPx)
imgH = size(I,1);
imgW = size(I,2);
y0 = max(1, round(bbox(2) + bbox(4) + marginPx));
y1 = imgH;
if idx < size(allBoxes,1)
    y1 = min(y1, round(allBoxes(idx+1,2) - marginPx));
end
if y1 <= y0 + 10
    y0 = max(1, round(bbox(2)));
    y1 = imgH;
end
rect = [1, y0, imgW, max(1, y1 - y0)];
crop = imcrop(I, rect);
cropPath = fullfile(outDir, sprintf('Table%s_p%03d.png', id, pageNum));
imwrite(crop, cropPath);
end

function cropPath = crop_figure_(I, bbox, outDir, id, pageNum, marginPx)
imgH = size(I,1);
imgW = size(I,2);
yBottom = max(1, round(bbox(2) - marginPx));
yTop = max(1, round(yBottom - 0.60 * imgH));
rect = [1, yTop, imgW, max(1, yBottom - yTop)];
crop = imcrop(I, rect);
cropPath = fullfile(outDir, sprintf('Fig%s_p%03d.png', id, pageNum));
imwrite(crop, cropPath);
end

function [tags, boxes, texts] = find_caption_hits_(ocrRes)
words = {};
boxes = zeros(0,4);
texts = {};
tags = {};
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
    w = normalize_token_(words{i});
    if isempty(w)
        continue;
    end
    for k = 1:4
        if i + k - 1 > numel(words), break; end
        cand = '';
        b = [];
        raw = '';
        for j = 0:(k-1)
            raw = [raw char(string(words{i+j}))]; %#ok<AGROW>
            cand = [cand normalize_token_(words{i+j})]; %#ok<AGROW>
            if isempty(b)
                b = boxesAll(i+j,:);
            else
                b = union_bbox_(b, boxesAll(i+j,:));
            end
        end
        [hitType, hitId] = caption_id_from_token_(cand);
        if ~isempty(hitType)
            tag = [hitType '_' hitId];
            if ~any(strcmp(tags, tag))
                tags{end+1,1} = tag; %#ok<AGROW>
                boxes(end+1,:) = b; %#ok<AGROW>
                texts{end+1,1} = strtrim(raw); %#ok<AGROW>
            end
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
token = strrep(token,'·','.');
token = strrep(token,',','.');
token = regexprep(token, '\s+', '');

m = regexp(token, '^表\s*5\s*[\.．]\s*(\d+)', 'tokens', 'once');
if ~isempty(m)
    hitType = 'T';
    hitId = ['5.' m{1}];
    return;
end
m = regexp(token, '^图\s*5\s*[\.．]\s*(\d+)', 'tokens', 'once');
if ~isempty(m)
    hitType = 'F';
    hitId = ['5.' m{1}];
    return;
end
end

function b = union_bbox_(a, c)
x0 = min(a(1), c(1));
y0 = min(a(2), c(2));
x1 = max(a(1)+a(3), c(1)+c(3));
y1 = max(a(2)+a(4), c(2)+c(4));
b = [x0, y0, x1-x0, y1-y0];
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

function t = normalize_text_(t)
t = char(string(t));
t = strrep(t, sprintf('\r'), sprintf('\n'));
t = strrep(t, '．', '.');
t = strrep(t, '。', '.');
t = strrep(t, '·', '.');
t = regexprep(t, '\n+', '\n');
end

function s = snippet_around_(t, needle)
s = '';
if isempty(t) || isempty(needle)
    return;
end
p = strfind(t, needle);
if isempty(p)
    needle2 = normalize_token_(needle);
    t2 = normalize_token_(t);
    p2 = strfind(t2, needle2);
    if isempty(p2)
        return;
    end
    p = p2(1);
else
    p = p(1);
end
a = max(1, p - 80);
b = min(numel(t), p + 160);
s = strtrim(t(a:b));
end

function write_caption_csv_(path, captions)
fid = fopen(path, 'w');
if fid < 0
    return;
end
c = onCleanup(@() fclose(fid));
fprintf(fid, 'type,id,page,captionText,cropPath,pagePath\n');
for i = 1:numel(captions)
    r = captions(i);
    fprintf(fid, '%s,%s,%d,%s,%s,%s\n', ...
        esc_csv_(r.type), esc_csv_(r.id), round(r.page), esc_csv_(r.captionText), esc_csv_(r.cropPath), esc_csv_(r.pagePath));
end
end

function s = esc_csv_(s)
s = char(string(s));
s = strrep(s, '"', '""');
s = ['"' s '"'];
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

function delete_if_exists_(p)
try
    if exist(p,'file') == 2
        delete(p);
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


function hText = place_labels_no_overlap(ax, xy, labels, opts)
% 修改日志
% - v1 2026-02-02: 增加标注放置统计日志，用于排查缺失标签原因。
% - v2 2026-02-02: 记录越界标注数量，定位导出缺失原因。
% - v3 2026-02-02: 越界时自动扩展坐标轴范围保证可见。
if nargin < 4, opts = struct(); end
if isempty(ax) || ~ishandle(ax), ax = gca; end
if isempty(xy) || isempty(labels)
    hText = gobjects(0,1);
    return;
end

labels = string(labels(:));
xy = double(xy);
n = min(size(xy,1), numel(labels));
labels = labels(1:n);
xy = xy(1:n, :);

fontSize = 8;
if isfield(opts,'fontSize') && ~isempty(opts.fontSize)
    fontSize = opts.fontSize;
end
if isscalar(fontSize)
    fontSize = repmat(fontSize, n, 1);
else
    fontSize = double(fontSize(:));
    if numel(fontSize) < n
        fontSize(end+1:n,1) = fontSize(end);
    end
end

fontWeight = repmat("normal", n, 1);
if isfield(opts,'fontWeight') && ~isempty(opts.fontWeight)
    fw = opts.fontWeight;
    if ischar(fw) || isstring(fw)
        fw = repmat(string(fw), n, 1);
    else
        fw = string(fw(:));
        if numel(fw) < n
            fw(end+1:n,1) = fw(end);
        end
    end
    fontWeight = fw(1:n);
end

bg = 'none';
if isfield(opts,'backgroundColor')
    bg = opts.backgroundColor;
end
margin = 1;
if isfield(opts,'margin') && ~isempty(opts.margin)
    margin = opts.margin;
end
try
    margin = double(margin);
catch
    margin = 1;
end
if ~(isfinite(margin) && margin > 0)
    margin = 1;
end
margin = round(margin);

scale = 0.012;
if isfield(opts,'offsetScale') && ~isempty(opts.offsetScale)
    scale = double(opts.offsetScale);
end

segs = zeros(0,4);
if isfield(opts,'avoidSegments') && ~isempty(opts.avoidSegments)
    try
        segs = double(opts.avoidSegments);
        if size(segs,2) ~= 4
            segs = zeros(0,4);
        end
    catch
        segs = zeros(0,4);
    end
end

xlimv = xlim(ax);
ylimv = ylim(ax);
sx = xlimv(2) - xlimv(1);
sy = ylimv(2) - ylimv(1);
if ~(isfinite(sx) && sx > 0), sx = max(1, max(xy(:,1)) - min(xy(:,1))); end
if ~(isfinite(sy) && sy > 0), sy = max(1, max(xy(:,2)) - min(xy(:,2))); end
dx0 = sx * scale;
dy0 = sy * scale;

dirs = [1 0; 0 1; -1 0; 0 -1; 1 1; 1 -1; -1 1; -1 -1; 2 0; 0 2; -2 0; 0 -2; 0 0];
rad = [1 1.5 2.2 3.0 3.8 4.6];

pad = max(sx, sy) * 0.004;
if isfield(opts,'linePadding') && ~isempty(opts.linePadding)
    try pad = double(opts.linePadding); catch, end
end

hText = gobjects(n,1);
bboxes = zeros(0,4);
skippedNan = 0;
skippedEmpty = 0;
placedCount = 0;
fallbackCount = 0;
outOfBoundsCount = 0;
didExpand = false;
oldXlim = xlimv;
oldYlim = ylimv;

for i = 1:n
    x = xy(i,1);
    y = xy(i,2);
    if ~(isfinite(x) && isfinite(y))
        skippedNan = skippedNan + 1;
        continue;
    end
    if strlength(labels(i)) == 0
        skippedEmpty = skippedEmpty + 1;
        continue;
    end
    h = text(ax, x, y, char(labels(i)), ...
        'Units','data', ...
        'FontSize', fontSize(i), ...
        'FontWeight', char(fontWeight(i)), ...
        'Interpreter','none', ...
        'Clipping','on', ...
        'BackgroundColor', bg, ...
        'Margin', margin, ...
        'Visible','off');
    hText(i) = h;
    try drawnow('limitrate'); catch, end

    placed = false;
    for rr = 1:numel(rad)
        dx = dx0 * rad(rr);
        dy = dy0 * rad(rr);
        for di = 1:size(dirs,1)
            pos = [x + dx*dirs(di,1), y + dy*dirs(di,2), 0];
            set(h, 'Position', pos);
            ext = get(h, 'Extent');
            bb = [ext(1) ext(2) ext(3) ext(4)];
            if (isempty(bboxes) || ~any(overlap_any_(bb, bboxes))) && ~intersects_any_segment_(bb, segs, pad)
                bboxes(end+1,:) = bb; %#ok<AGROW>
                set(h, 'Visible','on');
                placed = true;
                placedCount = placedCount + 1;
                break;
            end
        end
        if placed
            break;
        end
    end
    if ~placed
        set(h, 'Visible','on');
        fallbackCount = fallbackCount + 1;
        try
            ext = get(h, 'Extent');
            bboxes(end+1,:) = [ext(1) ext(2) ext(3) ext(4)]; %#ok<AGROW>
        catch
        end
    end
    try
        ext = get(h, 'Extent');
        if (ext(1) < xlimv(1)) || (ext(1) + ext(3) > xlimv(2)) || ...
           (ext(2) < ylimv(1)) || (ext(2) + ext(4) > ylimv(2))
            outOfBoundsCount = outOfBoundsCount + 1;
        end
    catch
    end
end

% 若存在越界标注，扩展坐标轴范围以确保可见
try
    if outOfBoundsCount > 0 && ~isempty(bboxes)
        minx = min(bboxes(:,1));
        maxx = max(bboxes(:,1) + bboxes(:,3));
        miny = min(bboxes(:,2));
        maxy = max(bboxes(:,2) + bboxes(:,4));
        padX = (oldXlim(2) - oldXlim(1)) * 0.02;
        padY = (oldYlim(2) - oldYlim(1)) * 0.02;
        newXlim = [min(oldXlim(1), minx - padX), max(oldXlim(2), maxx + padX)];
        newYlim = [min(oldYlim(1), miny - padY), max(oldYlim(2), maxy + padY)];
        if any(isfinite(newXlim)) && any(isfinite(newYlim))
            xlim(ax, newXlim);
            ylim(ax, newYlim);
            didExpand = true;
        end
    end
catch
end
end

function tf = overlap_any_(bb, bboxes)
ax1 = bb(1); ay1 = bb(2); ax2 = bb(1)+bb(3); ay2 = bb(2)+bb(4);
bx1 = bboxes(:,1); by1 = bboxes(:,2); bx2 = bboxes(:,1)+bboxes(:,3); by2 = bboxes(:,2)+bboxes(:,4);
tf = ~(ax2 < bx1 | ax1 > bx2 | ay2 < by1 | ay1 > by2);
end

function tf = intersects_any_segment_(bb, segs, pad)
tf = false;
if isempty(segs)
    return;
end
rx1 = bb(1) - pad; ry1 = bb(2) - pad;
rx2 = bb(1) + bb(3) + pad; ry2 = bb(2) + bb(4) + pad;
sx1 = segs(:,1); sy1 = segs(:,2); sx2 = segs(:,3); sy2 = segs(:,4);
minx = min(sx1, sx2); maxx = max(sx1, sx2);
miny = min(sy1, sy2); maxy = max(sy1, sy2);
mask = ~(maxx < rx1 | minx > rx2 | maxy < ry1 | miny > ry2);
idx = find(mask);
if isempty(idx)
    return;
end
for ii = 1:numel(idx)
    j = idx(ii);
    ax1 = sx1(j); ay1 = sy1(j);
    ax2 = sx2(j); ay2 = sy2(j);
    if point_in_rect_(ax1, ay1, rx1, ry1, rx2, ry2) || point_in_rect_(ax2, ay2, rx1, ry1, rx2, ry2)
        tf = true;
        return;
    end
    if seg_intersect_(ax1, ay1, ax2, ay2, rx1, ry1, rx2, ry1) || ...
            seg_intersect_(ax1, ay1, ax2, ay2, rx2, ry1, rx2, ry2) || ...
            seg_intersect_(ax1, ay1, ax2, ay2, rx2, ry2, rx1, ry2) || ...
            seg_intersect_(ax1, ay1, ax2, ay2, rx1, ry2, rx1, ry1)
        tf = true;
        return;
    end
end
end

function tf = point_in_rect_(x, y, x1, y1, x2, y2)
tf = (x >= x1) && (x <= x2) && (y >= y1) && (y <= y2);
end

function tf = seg_intersect_(x1, y1, x2, y2, x3, y3, x4, y4)
o1 = orient_(x1, y1, x2, y2, x3, y3);
o2 = orient_(x1, y1, x2, y2, x4, y4);
o3 = orient_(x3, y3, x4, y4, x1, y1);
o4 = orient_(x3, y3, x4, y4, x2, y2);
if (o1 == 0 && on_seg_(x1, y1, x2, y2, x3, y3)) || ...
        (o2 == 0 && on_seg_(x1, y1, x2, y2, x4, y4)) || ...
        (o3 == 0 && on_seg_(x3, y3, x4, y4, x1, y1)) || ...
        (o4 == 0 && on_seg_(x3, y3, x4, y4, x2, y2))
    tf = true;
    return;
end
tf = (o1 ~= o2) && (o3 ~= o4);
end

function o = orient_(x1, y1, x2, y2, x3, y3)
v = (y2 - y1) * (x3 - x2) - (x2 - x1) * (y3 - y2);
if abs(v) < 1e-12
    o = 0;
elseif v > 0
    o = 1;
else
    o = 2;
end
end

function tf = on_seg_(x1, y1, x2, y2, x, y)
tf = x >= min(x1, x2) - 1e-12 && x <= max(x1, x2) + 1e-12 && ...
    y >= min(y1, y2) - 1e-12 && y <= max(y1, y2) + 1e-12;
end

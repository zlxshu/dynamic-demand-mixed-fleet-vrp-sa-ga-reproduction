function fig = plot_routes_with_labels(coord, n, E, detail, legendMode, titleText, G)
% =========================================================================
% [ģ��] plot_routes_with_labels
%  ����: ��ͼ:����5.2·�߻����ڵ���·��,����ע 0,1..n,R1..RE;����������������.
%  ���Ķ�Ӧ: ��5�� ͼʾ(��ͼ5.1/5.2���)
%  ˵��: ģ�黯�汾,���� G �������� global.
% =========================================================================
if nargin < 5 || isempty(legendMode)
    legendMode = 'nodes';
end
if nargin < 6
    titleText = '';
end
if nargin < 7
    G = struct();
    G.visual2opt = false;
end

fig = figure('Color','w', 'WindowStyle','normal', 'Resize','on', 'NumberTitle','off'); hold on; box on;

%% [opt23] ����ͼƬʱ����������������(���� exportgraphics ����/��ȾͼƬ)
try set(fig,'ToolBar','figure','MenuBar','figure'); catch, end

% �ڵ�
hDepot = plot(coord(1,1), coord(1,2), 'r^', 'MarkerFaceColor','r', 'MarkerSize',10, 'HandleVisibility','off');
hCust = plot(coord(2:n+1,1), coord(2:n+1,2), 'bo', 'MarkerFaceColor','b', 'MarkerSize',5, 'HandleVisibility','off');
hStation = plot(coord(n+2:n+E+1,1), coord(n+2:n+E+1,2), 'gs', 'MarkerFaceColor','g', 'MarkerSize',8, 'HandleVisibility','off');

% ���ֱ�ע(Ӳ��Ҫ��)
xy = coord(1:(n+E+1), :);
labels = strings(n+E+1, 1);
labels(1) = "0";
for i = 1:n
    labels(i+1) = string(i);
end
for r = 1:E
    labels(n+r+1) = "R" + string(r);
end
fw = repmat("normal", n+E+1, 1);
fw(1) = "bold";
fw(n+2:n+E+1) = "bold";
fs = 8*ones(n+E+1, 1);
fs(1) = 9;

colors = lines(numel(detail));
legHandles = gobjects(0,1);
legLabels = {};
segs = zeros(0,4);
pathCount = 0;
for k = 1:numel(detail)
    if isfield(detail(k),'distance') && detail(k).distance < 1e-9
        continue; % δʹ�ó���������
    end
    seq = detail(k).route;
    if isfield(G,'visual2opt') && G.visual2opt
        seqPlot = route_2opt_visual(seq, G); % ����ͼ����
    else
        seqPlot = seq;
    end
    xs = coord(seqPlot+1,1);
    ys = coord(seqPlot+1,2);
    if numel(xs) >= 2
        x1 = xs(1:end-1); y1 = ys(1:end-1);
        x2 = xs(2:end);   y2 = ys(2:end);
        segs = [segs; [x1(:) y1(:) x2(:) y2(:)]]; %#ok<AGROW>
    end
    hRoute = plot(xs, ys, '-', 'Color', colors(k,:), 'LineWidth', 1.5);
    if strcmpi(legendMode,'paths')
        pathCount = pathCount + 1;
        legHandles(end+1,1) = hRoute; %#ok<AGROW>
        legLabels{end+1,1} = sprintf('路径%d', pathCount); %#ok<AGROW>
    end
end

place_labels_no_overlap(gca, xy, labels, struct('fontSize', fs, 'fontWeight', fw, 'backgroundColor', 'none', 'margin', 1, 'avoidSegments', segs));

if strcmpi(legendMode,'nodes')
    legend([hDepot hCust hStation], {'配送中心','客户','充电站'}, 'Location','best', 'Interpreter','none');
elseif ~isempty(legHandles)
    legend(legHandles, legLabels, 'Location','best', 'Interpreter','none');
end
if nargin >= 6 && ~isempty(titleText)
    title(titleText, 'Interpreter','none');
else
    title('');
end
end

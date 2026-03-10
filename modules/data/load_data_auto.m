function [data, meta] = load_data_auto(varargin)
% 修改日志
% - v1 2026-01-21: 支持 PreferInternal=true；即使存在data 文件 也强制使用内置数据（对齐默认口径）。
% - v2 2026-01-21: 控制台支持 审查 message 中文化（不再依赖 opt27 字样）。
% - v3 2026-02-02: 优先文件名列表增加 论文示例静态节点数据.xlsx，使 5.3.x 与 5.4.x 数据源统一。
% - v4 2026-02-02: 废除内部数据回退机制，强制使用 xlsx 文件；找不到文件时直接报错。
% - v5 2026-02-02: 数据读取改为自适应范围（不再固定 B2:F999）。
% - v6 2026-02-02: 修复 load_data_auto.m 第107行中文编码导致的单引号缺失错误。
% - v7 2026-02-02: 记录列 NaN 统计，核对坐标列是否缺失。
% - v8 2026-02-02: 自适应列选择改为按 NaN 最少优先。
% - v9 2026-02-02: 若 A:E 的 RT 列全 NaN 且 F 列可用，强制改用 B:F。
% - v10 2026-02-02: 若 RT 列全 NaN 且包含时间窗字符串，则解析成 LT/RT。
% - v11 2026-02-02: 记录列结构与站点候选统计（用于核对 n/E 推断）。
% - v12 2026-02-02: E 推断优先用 demand=0 计数，避免低估站点数。
% load_data_auto - 统一数据加载入口（优先 data/，自动复制，同步更新，
%
% 目标逻辑（所有 section/脚本统一复用）：
%   1) 优先从 <projectRoot>/data/ 读取
%   2) 如果 data/ 为空或缺少文件：自动从候选源目录复制到 data/（若源文件更新则覆盖）
%   3) 如果仍找不到：直接报错（不再回退到内置数据）
%
% 输出:
%   data: 数值矩阵，默认口径为 [x y demand LT RT]
%   meta: 结构体，包含来源、路径、以及推测的 E/n 等信息
%
% 可选参数（Name-Value）：
%   'ProjectRoot'      : 手工指定项目根目录（默认由本文件位置推断）
%   'DataDirName'      : data 目录名（默认 'data'）
%   'FileNames'        : 优先文件名列表（默认含 论文示例静态节点数据.xlsx）
%   'SourceDirs'       : 自动复制的源目录列表（默认 {projectRoot, parentDir}）
%   'Range'            : Excel 读取范围（默认 '' 表示自适应整表）
%   'Sheet'            : Sheet 索引（默认 1）
%
% 说明：
% - 读取时优先 readmatrix，失败再 fallback xlsread
% - 自动推断 E：统计 demand=0 且 LT=0 且 RT=1440 的行数，E = count - 1（扣除 depot）

% ---------------- 参数解析 ----------------
p = inputParser();
p.addParameter('ProjectRoot', '', @(s) ischar(s) || isstring(s));
p.addParameter('DataDirName', 'data', @(s) ischar(s) || isstring(s));
p.addParameter('FileNames', {'论文示例静态节点数据.xlsx'}, @(c) iscell(c) || isstring(c));
p.addParameter('SourceDirs', {}, @(c) iscell(c) || isstring(c));
p.addParameter('Range', '', @(s) ischar(s) || isstring(s));
p.addParameter('Sheet', 1, @(x) isnumeric(x) && isscalar(x));
p.parse(varargin{:});
opt = p.Results;

% ---------------- 目录推断 ----------------
% 说明：
% - "data/" 目录默认指向 <projectRoot>/data（与 README 一致）
% - 所有复制动作由 MATLAB 完成，避免中文路径在外部 shell 中的编码问题
thisFile = mfilename('fullpath');
dataDirModule = fileparts(thisFile);        % .../modules/data
modulesDir = fileparts(dataDirModule);      % .../modules
projectRootAuto = fileparts(modulesDir);    % .../Qiu_By_Rayzo

if strlength(string(opt.ProjectRoot)) == 0
    projectRoot = projectRootAuto;
else
    projectRoot = char(opt.ProjectRoot);
end
parentDir = fileparts(projectRoot);         % .../程序

% 默认 dataDir 为 <projectRoot>/data；若显式指定 DataDirName，则使用该子目录
dataDir = fullfile(projectRoot, char(opt.DataDirName));
if ~exist(dataDir, 'dir'), mkdir(dataDir); end

fileNames = opt.FileNames;
if isstring(fileNames), fileNames = cellstr(fileNames); end

if isempty(opt.SourceDirs)
    sourceDirs = {projectRoot, parentDir};
else
    sourceDirs = opt.SourceDirs;
    if isstring(sourceDirs), sourceDirs = cellstr(sourceDirs); end
end

% ---------------- 自动同步复制（若源更新则覆盖） ----------------
sync_copy_data_files_(dataDir, sourceDirs, fileNames);

% ---------------- 选择数据文件（优先 <projectRoot>/data） ----------------
picked = '';
for i = 1:numel(fileNames)
    cand = fullfile(dataDir, fileNames{i});
    if exist(cand, 'file')
        picked = cand;
        break;
    end
end

meta = struct();
meta.projectRoot = projectRoot;
meta.dataDir = dataDir;
meta.dataDirModule = dataDirModule;
meta.pickedPath = picked;

if ~isempty(picked)
    data = read_data_file_(picked, opt.Sheet, opt.Range);
    meta.source = 'excel';
    meta.message = sprintf('使用表格数据: %s', picked);
else
    % 如果根目录 data/ 没有，则尝试 modules/data 作为后备读取源
    % 找不到文件时直接报错（不再回退到内部数据）
    error('load_data_auto:NotFound', '未找到数据文件（data/及源目录均无 %s）。请确保数据文件存在。', strjoin(fileNames, ', '));
end

% ---------------- 自动推断 E/n（尽量自配替换数据） ----------------
meta.totalRows = size(data,1);
meta.E = infer_E_(data);
meta.n = meta.totalRows - 1 - meta.E;
if meta.n < 0
    % 推断失败则不确定，回退到常用 E=5
    meta.E = 5;
    meta.n = meta.totalRows - 1 - meta.E;
    meta.E_infer = 'fallback_E5';
else
    meta.E_infer = 'heuristic_zeroDemand_fullTW';
end
end

% ========================= 内部函数 =========================
function sync_copy_data_files_(dataDir, sourceDirs, fileNames)
for i = 1:numel(fileNames)
    name = fileNames{i};
    srcPath = '';
    for d = 1:numel(sourceDirs)
        cand = fullfile(sourceDirs{d}, name);
        if exist(cand, 'file')
            srcPath = cand;
            break;
        end
    end
    if isempty(srcPath)
        continue;
    end

    dstPath = fullfile(dataDir, name);
    doCopy = false;
    if ~exist(dstPath, 'file')
        doCopy = true;
    else
        s = dir(srcPath);
        t = dir(dstPath);
        if ~isempty(s) && ~isempty(t) && s.datenum > t.datenum
            doCopy = true;
        end
    end

    if doCopy
        try
            copyfile(srcPath, dstPath);
        catch
            % 复制失败：忽略，后续会继续尝试读取 dataDir 里的其他文件或回退
        end
    end
end
end

function data = read_data_file_(filePath, sheet, range)
data = [];
raw = [];

% 优先 readmatrix（新 MATLAB）
if exist('readmatrix', 'file') == 2
    try
        if isempty(range)
            data = readmatrix(filePath, 'Sheet', sheet);
        else
            data = readmatrix(filePath, 'Sheet', sheet, 'Range', range);
        end
    catch
        data = [];
    end
end

% fallback xlsread（老 MATLAB / 兼容性）
if isempty(data)
    if isempty(range)
        data = xlsread(filePath, sheet);
    else
        data = xlsread(filePath, sheet, range);
    end
end

% 去掉全 NaN 行
maskKeep = ~all(isnan(data),2);
data = data(maskKeep,:);
if exist('readcell', 'file') == 2
    try
        if isempty(range)
            raw = readcell(filePath, 'Sheet', sheet);
        else
            raw = readcell(filePath, 'Sheet', sheet, 'Range', range);
        end
        if size(raw,1) >= numel(maskKeep)
            raw = raw(1:numel(maskKeep),:);
            raw = raw(maskKeep,:);
        else
            raw = [];
        end
    catch
        raw = [];
    end
end

% 自适应列选择：在 A:E 与 B:F 中选择 NaN 最少的组合
colsUsed = '';
if size(data,2) >= 6
    % 若 A:E 的第5列全 NaN 且 F 列可用，直接改用 B:F
    try
        colNanRaw = sum(isnan(data), 1);
        if numel(colNanRaw) >= 6 && colNanRaw(5) == size(data,1) && colNanRaw(6) < size(data,1)
            data = data(:,2:6);
            colsUsed = 'B:F';
        else
            dataA = data(:,1:5);
            dataB = data(:,2:6);
            scoreA = nan_score_(dataA);
            scoreB = nan_score_(dataB);
            if scoreB <= scoreA
                data = dataB;
                colsUsed = 'B:F';
            else
                data = dataA;
                colsUsed = 'A:E';
            end
        end
    catch
        dataA = data(:,1:5);
        dataB = data(:,2:6);
        scoreA = nan_score_(dataA);
        scoreB = nan_score_(dataB);
        if scoreB <= scoreA
            data = dataB;
            colsUsed = 'B:F';
        else
            data = dataA;
            colsUsed = 'A:E';
        end
    end
elseif size(data,2) >= 5
    data = data(:,1:5);
    colsUsed = 'A:E';
end

% 去掉全 NaN 行（列切片后再清理）
data = data(~all(isnan(data),2),:);

% 基本形状检查：至少 5 列
if size(data,2) < 5
    error('load_data_auto:BadShape', '读取到的数据列数不足（期望 =5），file=%s', filePath);
end

% 若 RT 列全 NaN 且存在时间窗字符串，则解析成 LT/RT
try
    if size(data,2) == 5 && all(isnan(data(:,5))) && ~isempty(raw) && size(raw,2) >= 5
        [lt, rt, okCnt] = parse_tw_column_(raw(:,5));
        if okCnt > 0
            x = data(:,2);
            y = data(:,3);
            dem = data(:,4);
            data = [x y dem lt rt];
        end
    end
catch
end
end

function E = infer_E_(data)
% data columns: [x y demand LT RT]
demand = data(:,3);
LT = data(:,4);
RT = data(:,5);
cntZD = nnz(demand == 0);
cntFullTW = nnz((LT == 0) & (RT == 1440));
if cntZD >= 2
    E = max(cntZD - 1, 0);
elseif cntFullTW >= 2
    E = max(cntFullTW - 1, 0);
else
    E = 5; % 常用默认
end
end

function s = nan_score_(d)
% NaN 统计：优先保证 x/y/RT 列可用
if isempty(d) || size(d,2) < 5
    s = inf;
    return;
end
nanCol = sum(isnan(d), 1);
% x,y,RT 列权重更高（列1,2,5）
s = nanCol(1) + nanCol(2) + nanCol(5) + 0.5 * (nanCol(3) + nanCol(4));
end

function [lt, rt, okCnt] = parse_tw_column_(col)
% 解析时间窗字符串: 支持 [HH:MM-HH:MM] / HH:MM-HH:MM
n = numel(col);
lt = NaN(n,1);
rt = NaN(n,1);
okCnt = 0;
for i = 1:n
    v = col{i};
    if isstring(v), v = char(v); end
    if ~ischar(v), continue; end
    s = strtrim(v);
    if isempty(s), continue; end
    s = strrep(s, '[', '');
    s = strrep(s, ']', '');
    s = strrep(s, '—', '-');
    s = strrep(s, '–', '-');
    s = strrep(s, '~', '-');
    tok = regexp(s, '(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})', 'tokens', 'once');
    if isempty(tok), continue; end
    h1 = str2double(tok{1}); m1 = str2double(tok{2});
    h2 = str2double(tok{3}); m2 = str2double(tok{4});
    if any(~isfinite([h1 m1 h2 m2])), continue; end
    lt(i) = h1*60 + m1;
    rt(i) = h2*60 + m2;
    okCnt = okCnt + 1;
end
end

% 内部数据函数已废除（v4 2026-02-02）
% 所有 section 必须使用 xlsx 文件，不再支持内部数据回退


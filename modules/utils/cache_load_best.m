function [payload, bestPath, bestMeta] = cache_load_best(cacheDir, key, currentParamSig, currentDataSig, varargin)
% 修改日志
% - v1 2026-01-21: 新增“签名隔离缓存”加载器 cache_load_best；修复 5.3.2 读旧缓存导致的跨参数污染。
% - v1 2026-01-21: 仅允许 param_signature 与 data_signature 完全匹配的缓存进入候选；不匹配自动忽略并打印审计日志。
% - v2 2026-01-21: 控制台提示中文化（签名不匹配/缺签名/forceRecompute 等）。
%
% 用法：
%   [payload, bestPath, bestMeta] = cache_load_best(paths.cache, key, sig.param.full, sig.data.full)
%   [payload, bestPath, bestMeta] = cache_load_best(..., 'ForceRecompute', true)

    p = inputParser();
    p.addParameter('ForceRecompute', false, @(x) islogical(x) && isscalar(x));
    p.parse(varargin{:});
    opt = p.Results;

    payload = [];
    bestPath = '';
    bestMeta = struct();

    if nargin < 1 || isempty(cacheDir) || exist(cacheDir, 'dir') ~= 7
        return;
    end
    if nargin < 2 || isempty(key)
        key = 'cache';
    end
    if nargin < 3
        currentParamSig = '';
    end
    if nargin < 4
        currentDataSig = '';
    end

    skipUse = opt.ForceRecompute;
    if skipUse
        fprintf('[缓存] forceRecompute=1：跳过缓存复用（仍会审计不匹配项），key=%s\n', key);
    end

    currentParamFull = sig_full_(currentParamSig);
    currentDataFull  = sig_full_(currentDataSig);
    currentParamShort = sig_short_(currentParamFull);
    currentDataShort  = sig_short_(currentDataFull);

    files = dir(fullfile(cacheDir, sprintf('%s__*.mat', key)));
    if isempty(files)
        % 兼容：老缓存命名（无签名）一律忽略，但打印提示（避免“误读”）
        legacy = dir(fullfile(cacheDir, sprintf('%s_*.mat', key)));
        for i = 1:min(numel(legacy), 50)
            fprintf('[缓存] 缺少签名 -> 已忽略: %s\n', fullfile(legacy(i).folder, legacy(i).name));
        end
        return;
    end

    bestScore = inf;
    bestDatenum = -inf;

    for i = 1:numel(files)
        pth = fullfile(files(i).folder, files(i).name);

        meta = struct();
        try
            m = load(pth, 'meta');
            if isfield(m,'meta')
                meta = m.meta;
            end
        catch
            continue;
        end

        if ~isstruct(meta) || ~isfield(meta,'paramSigFull') || ~isfield(meta,'dataSigFull')
            fprintf('[缓存] 缺少签名 -> 已忽略: %s\n', pth);
            continue;
        end

        fileParamFull = sig_full_(meta.paramSigFull);
        fileDataFull  = sig_full_(meta.dataSigFull);

        if ~strcmp(fileParamFull, currentParamFull) || ~strcmp(fileDataFull, currentDataFull)
            fprintf('[缓存] 签名不匹配 -> 已忽略: %s, 文件=%s/%s, 当前=%s/%s\n', ...
                pth, sig_short_(fileParamFull), sig_short_(fileDataFull), currentParamShort, currentDataShort);
            continue;
        end

        % 匹配：按 meta.cost/meta.bestCost 选最优；否则按最新
        score = inf;
        if isfield(meta,'cost') && isfinite(meta.cost)
            score = meta.cost;
        elseif isfield(meta,'bestCost') && isfinite(meta.bestCost)
            score = meta.bestCost;
        end

        if isfinite(score)
            if score + 1e-9 < bestScore
                bestScore = score;
                bestDatenum = files(i).datenum;
                bestPath = pth;
                bestMeta = meta;
            end
        else
            if bestScore == inf && files(i).datenum > bestDatenum
                bestDatenum = files(i).datenum;
                bestPath = pth;
                bestMeta = meta;
            end
        end
    end

    if isempty(bestPath)
        return;
    end

    if skipUse
        fprintf('[缓存] 签名匹配但 forceRecompute=1 -> 已忽略: %s\n', bestPath);
        payload = [];
        bestPath = '';
        bestMeta = struct();
        return;
    end

    try
        s = load(bestPath, 'payload', 'meta');
        if isfield(s,'payload')
            payload = s.payload;
        end
        if isfield(s,'meta')
            bestMeta = s.meta;
        end
        fprintf('[缓存] 签名匹配 -> 已加载: %s\n', bestPath);
    catch ME
        fprintf('[缓存] 读取失败 -> 已忽略: %s (%s)\n', bestPath, ME.message);
        payload = [];
        bestPath = '';
        bestMeta = struct();
    end
end

function full = sig_full_(sig)
if isstruct(sig) && isfield(sig,'full')
    full = char(string(sig.full));
else
    full = char(string(sig));
end
end

function short = sig_short_(full)
short = '';
try
    full = char(string(full));
    if strlength(string(full)) >= 8
        short = full(1:8);
    else
        short = full;
    end
catch
end
end


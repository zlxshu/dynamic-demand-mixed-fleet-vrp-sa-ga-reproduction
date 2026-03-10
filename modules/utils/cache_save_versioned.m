function [savedPath, bestPath] = cache_save_versioned(moduleName, cacheKey, varName, val, cost)
% CACHE_SAVE_VERSIONED - 保存时间戳缓存，并维护 best 指针文件
% 会写入：
%   CACHE/<moduleName>/<cacheKey>_yyyymmdd_HHMMSS.mat
% 并在更优时更新：
%   CACHE/<moduleName>/<cacheKey>_best.mat
rootDir = project_root_dir();
if nargin < 1 || isempty(moduleName), moduleName = 'unknown'; end
if nargin < 2 || isempty(cacheKey),  cacheKey  = 'cache'; end
if nargin < 3 || isempty(varName),   varName   = 'cache'; end
if nargin < 5, cost = inf; end

cacheDir = fullfile(rootDir, 'CACHE', moduleName);
ensure_dir(cacheDir);

ts = datestr(now, 'yyyymmdd_HHMMSS');
savedPath = fullfile(cacheDir, sprintf('%s_%s.mat', cacheKey, ts));

% 保存（变量名固定为 varName）
s = struct();
s.(varName) = val;
save(savedPath, '-struct', 's');

% 读取当前 best
bestPath = fullfile(cacheDir, [cacheKey '_best.mat']);
bestCost = inf;
if exist(bestPath, 'file') == 2
    try
        sBest = load(bestPath);
        if isfield(sBest, varName)
            bestCost = cache_guess_cost(sBest.(varName));
        end
    catch
    end
end

% 若本次更优，则更新 best（先备份旧 best）
if isfinite(cost) && (cost + 1e-9 < bestCost)
    if exist(bestPath, 'file') == 2
        try
            bak = fullfile(cacheDir, sprintf('%s_best_bak_%s.mat', cacheKey, ts));
            copyfile(bestPath, bak);
        catch
        end
    end
    try
        copyfile(savedPath, bestPath);
    catch
        save(bestPath, '-struct', 's');
    end
end
end

function c = cache_guess_cost(v)
% 与 cache_load_best 内部规则保持一致
c = inf;
try
    if isstruct(v) && isfield(v,'bestCost') && isfinite(v.bestCost)
        c = v.bestCost;
        return;
    end
    if isstruct(v) && isfield(v,'summary') && isstruct(v.summary) && isfield(v.summary,'totalCost') && isfinite(v.summary.totalCost)
        c = v.summary.totalCost;
        return;
    end
    if isstruct(v) && isfield(v,'detail') && isstruct(v.detail) && ~isempty(v.detail) && isfield(v.detail,'totalCost')
        c = sum([v.detail.totalCost]);
        return;
    end
catch
end
end


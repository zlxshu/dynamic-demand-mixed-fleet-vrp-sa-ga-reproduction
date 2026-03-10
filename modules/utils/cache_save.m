function savedPath = cache_save(cacheDir, key, payload, meta)
% 修改日志
% - v1 2026-01-21: 新增带签名缓存写入 cache_save(cacheDir,key,payload,meta)；文件名含 section/mode/signature/timestamp。

    if nargin < 1 || isempty(cacheDir)
        error('cache_save:missingCacheDir', 'cacheDir 不能为空');
    end
    if nargin < 2 || isempty(key)
        key = 'cache';
    end
    if nargin < 4 || isempty(meta)
        meta = struct();
    end
    if ~isstruct(meta)
        error('cache_save:invalidMeta', 'meta 必须是 struct');
    end

    ensure_dir(cacheDir);

    meta = fill_meta_defaults_(meta, key, cacheDir);

    fname = artifact_filename(key, meta.sectionName, meta.modeTag, meta.paramSigShort, meta.dataSigShort, meta.timestamp, '.mat');
    savedPath = fullfile(cacheDir, fname);

    s = struct();
    s.payload = payload;
    s.meta = meta;
    save(savedPath, '-struct', 's');
end

function meta = fill_meta_defaults_(meta, key, cacheDir)
if ~isfield(meta,'key'), meta.key = key; end
if ~isfield(meta,'timestamp') || isempty(meta.timestamp)
    meta.timestamp = datestr(now, 'yyyymmddTHHMMSS');
end
if ~isfield(meta,'sectionName') || isempty(meta.sectionName)
    % 兜底：从 cacheDir 猜 sectionName = .../outputs/<sectionName>/cache
    try
        [p1, leaf] = fileparts(cacheDir);
        if strcmpi(leaf, 'cache')
            [~, sec] = fileparts(p1);
            meta.sectionName = sec;
        else
            meta.sectionName = 'unknown_section';
        end
    catch
        meta.sectionName = 'unknown_section';
    end
end
if ~isfield(meta,'modeTag') || isempty(meta.modeTag)
    meta.modeTag = 'default';
end

% 签名字段兼容：支持 meta.paramSig/meta.dataSig 为 struct(full/short)
if ~isfield(meta,'paramSigShort')
    meta.paramSigShort = '';
    try
        meta.paramSigShort = meta.paramSig.short;
    catch
    end
end
if ~isfield(meta,'paramSigFull')
    meta.paramSigFull = '';
    try
        meta.paramSigFull = meta.paramSig.full;
    catch
    end
end
if ~isfield(meta,'dataSigShort')
    meta.dataSigShort = '';
    try
        meta.dataSigShort = meta.dataSig.short;
    catch
    end
end
if ~isfield(meta,'dataSigFull')
    meta.dataSigFull = '';
    try
        meta.dataSigFull = meta.dataSig.full;
    catch
    end
end
end



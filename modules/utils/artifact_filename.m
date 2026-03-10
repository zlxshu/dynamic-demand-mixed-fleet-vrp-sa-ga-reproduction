function fname = artifact_filename(artifactName, sectionName, modeTag, paramSigShort, dataSigShort, timestamp, ext)
% 修改日志
% - v1 2026-01-21: 新增统一文件命名规范：
%   <artifactName>__<sectionName>__<modeTag>__<paramSigShort>__<dataSigShort>__<timestamp>.ext

    if nargin < 1 || isempty(artifactName), artifactName = 'artifact'; end
    if nargin < 2 || isempty(sectionName), sectionName = 'unknown_section'; end
    if nargin < 3 || isempty(modeTag), modeTag = 'default'; end
    if nargin < 4 || isempty(paramSigShort), paramSigShort = 'nosig'; end
    if nargin < 5 || isempty(dataSigShort), dataSigShort = 'nodata'; end
    if nargin < 6 || isempty(timestamp), timestamp = datestr(now, 'yyyymmddTHHMMSS'); end
    if nargin < 7, ext = ''; end

    if isstring(artifactName), artifactName = char(artifactName); end
    if isstring(sectionName), sectionName = char(sectionName); end
    if isstring(modeTag), modeTag = char(modeTag); end
    if isstring(paramSigShort), paramSigShort = char(paramSigShort); end
    if isstring(dataSigShort), dataSigShort = char(dataSigShort); end
    if isstring(timestamp), timestamp = char(timestamp); end
    if isstring(ext), ext = char(ext); end

    artifactName = sanitize_(artifactName);
    sectionName = sanitize_(sectionName);
    modeTag = sanitize_(modeTag);
    paramSigShort = sanitize_(paramSigShort);
    dataSigShort = sanitize_(dataSigShort);
    timestamp = sanitize_(timestamp);

    if ~isempty(ext) && ext(1) ~= '.'
        ext = ['.' ext];
    end

    fname = sprintf('%s__%s__%s__%s__%s__%s%s', ...
        artifactName, sectionName, modeTag, paramSigShort, dataSigShort, timestamp, ext);
end

function s = sanitize_(s)
s = char(string(s));
s = regexprep(s, '\\s+', '_');
s = regexprep(s, '[\\\\/:\\*\\?\"<>\\|]+', '_');
s = regexprep(s, '__+', '__');
s = regexprep(s, '^_+|_+$', '');
if isempty(s)
    s = 'x';
end
end



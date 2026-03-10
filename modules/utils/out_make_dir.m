function outDir = out_make_dir(moduleName, suffix)
% OUT_MAKE_DIR - 在根目录 OUT/<moduleName>/ 下创建时间戳输出目录并返回路径
rootDir = project_root_dir();
if nargin < 1 || isempty(moduleName)
    moduleName = 'unknown';
end
if nargin < 2
    suffix = '';
end

baseDir = fullfile(rootDir, 'OUT', moduleName);
ensure_dir(baseDir);

ts = datestr(now, 'yyyymmdd_HHMMSS');
if isempty(suffix)
    folderName = ts;
else
    folderName = [ts '_' suffix];
end
outDir = fullfile(baseDir, folderName);
ensure_dir(outDir);
end


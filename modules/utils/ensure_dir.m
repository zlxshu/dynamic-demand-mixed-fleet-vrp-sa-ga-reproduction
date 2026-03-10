function ensure_dir(dirPath)
% ENSURE_DIR - 若目录不存在则创建
if nargin < 1 || isempty(dirPath)
    return;
end
if exist(dirPath, 'dir') ~= 7
    mkdir(dirPath);
end
end


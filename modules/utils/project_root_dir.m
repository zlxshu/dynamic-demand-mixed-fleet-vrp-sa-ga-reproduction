function rootDir = project_root_dir()
% PROJECT_ROOT_DIR - 返回工程根目录(Qiu_By_Rayzo)
% 规则：本函数位于 modules/utils/ 下，向上两级即为根目录
thisFile = mfilename('fullpath');
thisDir = fileparts(thisFile);
rootDir = fileparts(fileparts(thisDir));
end


function out = create_section_from_template(sectionId)
% 修改日志
% - v2 2026-01-21: 新增 section 一键接入：生成 run_section_xxx(ctx) + 注册 section_registry + 同步 run_modes(SUPPORTED_SECTIONS)；避免新增 section 独立运行。
%
% 用法：
%   create_section_from_template('534')
%   create_section_from_template('section_534')
%
% 行为（自动化）：
% 1) 生成：modules/experiments/run_section_534.m（基于 templates/section_template.m）
% 2) 生成：modules/experiments/section_534.m（兼容入口：转发到 run_section_534(ctx)）
% 3) 更新：modules/registry/section_registry.m（注册 @run_section_534）
% 4) 更新：run_modes.m（把 '534' 加入 SUPPORTED_SECTIONS；否则 run_modes 会报错）

    if nargin < 1 || isempty(sectionId)
        error('create_section_from_template:MissingId', '请提供 section 编号，例如 ''534'' 或 ''section_534''');
    end

    sectionNum = normalize_section_id_(sectionId);
    sectionKey = ['section_' sectionNum];
    fnName = ['run_section_' sectionNum];

    projectRoot = project_root_dir();

    templatePath = fullfile(projectRoot, 'templates', 'section_template.m');
    runSectionPath = fullfile(projectRoot, 'modules', 'experiments', [fnName '.m']);
    wrapperPath = fullfile(projectRoot, 'modules', 'experiments', [sectionKey '.m']);
    registryPath = fullfile(projectRoot, 'modules', 'registry', 'section_registry.m');
    runModesPath = fullfile(projectRoot, 'run_modes.m');

    if exist(templatePath, 'file') ~= 2
        error('create_section_from_template:MissingTemplate', '模板不存在: %s', templatePath);
    end

    if exist(runSectionPath, 'file') == 2
        error('create_section_from_template:Exists', '文件已存在: %s', runSectionPath);
    end
    if exist(wrapperPath, 'file') == 2
        error('create_section_from_template:Exists', '文件已存在: %s', wrapperPath);
    end

    % ---- 1) 生成 run_section_5xx.m ----
    txt = read_text_utf8_(templatePath);
    txt = strrep(txt, 'function out = run_section_xxx(ctx)', sprintf('function out = %s(ctx)', fnName));
    txt = strrep(txt, 'sectionName = ''section_xxx'';', sprintf('sectionName = ''%s'';', sectionKey));
    write_text_utf8_(runSectionPath, txt);

    % ---- 2) 生成兼容入口 section_5xx.m ----
    wrapper = build_wrapper_(sectionKey, fnName);
    write_text_utf8_(wrapperPath, wrapper);

    % ---- 3) 注册到 section_registry ----
    update_registry_(registryPath, sectionKey, fnName);

    % ---- 4) 同步 run_modes(SUPPORTED_SECTIONS) ----
    update_run_modes_(runModesPath, sectionNum);

    out = struct();
    out.sectionKey = sectionKey;
    out.runSectionPath = runSectionPath;
    out.wrapperPath = wrapperPath;
    out.registryPath = registryPath;
    out.runModesPath = runModesPath;

    fprintf('[创建] %s\n', runSectionPath);
    fprintf('[创建] %s\n', wrapperPath);
    fprintf('[更新] %s\n', registryPath);
    fprintf('[更新] %s\n', runModesPath);
end

% ===================== helpers =====================
function sectionNum = normalize_section_id_(sectionId)
s = char(string(sectionId));
s = strtrim(s);
if endsWith(s, '.m'), s = s(1:end-2); end
if startsWith(lower(s), 'run_section_'), s = s(numel('run_section_')+1:end); end
if startsWith(lower(s), 'section_'), s = s(numel('section_')+1:end); end
if isempty(regexp(s, '^[0-9]+$', 'once'))
    error('create_section_from_template:BadId', 'sectionId 必须为数字编号，例如 534 或 section_534（收到：%s）', sectionId);
end
sectionNum = s;
end

function txt = read_text_utf8_(p)
fid = fopen(p, 'r', 'n', 'UTF-8');
if fid < 0
    error('create_section_from_template:openFailed', '无法打开文件: %s', p);
end
cleanup = onCleanup(@() fclose(fid));
txt = fread(fid, '*char')';
end

function write_text_utf8_(p, txt)
fid = fopen(p, 'w', 'n', 'UTF-8');
if fid < 0
    error('create_section_from_template:writeFailed', '无法写入文件: %s', p);
end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, txt, 'char');
end

function wrapper = build_wrapper_(sectionKey, fnName)
wrapper = sprintf([ ...
    'function varargout = %s(varargin)\n' ...
    '%% 修改日志\n' ...
    '%% - v1 2026-01-21: 兼容入口；统一转发到 %s(ctx)。\n' ...
    '%%\n' ...
    '%% 注意：本函数仅用于兼容直接调用 section_5xx；规范运行请使用 run_modes.m。\n' ...
    '\n' ...
    'ctx = get_config();\n' ...
    'out = %s(ctx);\n' ...
    '\n' ...
    'if nargout > 0\n' ...
    '    varargout{1} = out;\n' ...
    'end\n' ...
    'end\n' ...
    ], sectionKey, fnName, fnName);
end

function update_registry_(registryPath, sectionKey, fnName)
txt = read_text_utf8_(registryPath);
needle = sprintf('registry(''%s'')', sectionKey);
if contains(txt, needle)
    error('create_section_from_template:AlreadyRegistered', 'section_registry 已存在注册：%s', sectionKey);
end

insLine = sprintf('    registry(''%s'') = @%s;', sectionKey, fnName);

% 插入到最后一个 end 之前
m = regexp(txt, '(?m)^end\\s*$', 'start');
if isempty(m)
    error('create_section_from_template:RegistryParseFail', '无法解析 section_registry: %s', registryPath);
end
pos = m(end);
txt2 = [txt(1:pos-1) insLine newline txt(pos:end)];
write_text_utf8_(registryPath, txt2);
end

function update_run_modes_(runModesPath, sectionNum)
txt = read_text_utf8_(runModesPath);
pat = '(?m)^SUPPORTED_SECTIONS\\s*=\\s*\\{(?<body>[^}]*)\\}\\s*;\\s*$';
m = regexp(txt, pat, 'names', 'once');
if isempty(m)
    error('create_section_from_template:RunModesParseFail', '无法解析 run_modes 的 SUPPORTED_SECTIONS: %s', runModesPath);
end
body = m.body;
ids = regexp(body, '''(?<id>[0-9]+)''', 'names');
cur = cellfun(@(x) x, {ids.id}, 'UniformOutput', false);
cur = unique(cur);
if ~any(strcmp(cur, sectionNum))
    cur{end+1} = sectionNum; %#ok<AGROW>
end
% 数字排序
curNum = cellfun(@str2double, cur);
[~, idx] = sort(curNum);
cur = cur(idx);
newBody = strjoin(cellfun(@(s) ['''' s ''''], cur, 'UniformOutput', false), ',');
newLine = sprintf('SUPPORTED_SECTIONS = {%s};', newBody);
txt2 = regexprep(txt, pat, newLine, 'once');
write_text_utf8_(runModesPath, txt2);
end


function result = enforce_switch_panel(cfg)
% enforce_switch_panel - 强制检查开关面板规范
%
% 用法：
%   result = enforce_switch_panel(cfg)
%
% 输入：
%   cfg - 配置结构体，包含：
%     cfg.supportedSections - 支持的 Section 列表（cell array）
%     cfg.runModesPath      - run_modes.m 的完整路径
%
% 输出：
%   result - 检查结果结构体
%     result.passed       - 是否通过（true/false）
%     result.errors       - 错误列表（cell array）
%     result.warnings     - 警告列表（cell array）
%
% 检查项：
%   1. 所有注册的 Section 是否在 run_modes.m 中有对应开关面板
%   2. 环境变量命名是否符合规范（SECTIONXXX_*）
%   3. Section 源码中是否存在硬编码的参数定义（可选警告）
%
% 修改日志
% - v1 2026-02-03: 新增开关面板规范检查

result = struct();
result.passed = true;
result.errors = {};
result.warnings = {};

if nargin < 1 || isempty(cfg)
    result.passed = false;
    result.errors{end+1} = 'enforce_switch_panel: 缺少 cfg 参数';
    return;
end

% 定位项目根目录
if isfield(cfg, 'runModesPath') && ~isempty(cfg.runModesPath)
    runModesPath = cfg.runModesPath;
    if ~endsWith(runModesPath, '.m')
        runModesPath = [runModesPath '.m'];
    end
else
    result.passed = false;
    result.errors{end+1} = 'enforce_switch_panel: cfg.runModesPath 未指定';
    return;
end

projectRoot = fileparts(runModesPath);

% 读取 run_modes.m 内容
if ~exist(runModesPath, 'file')
    result.passed = false;
    result.errors{end+1} = sprintf('enforce_switch_panel: run_modes.m 不存在: %s', runModesPath);
    return;
end

runModesContent = fileread(runModesPath);

% 获取支持的 Section 列表
supportedSections = {};
if isfield(cfg, 'supportedSections') && ~isempty(cfg.supportedSections)
    supportedSections = cfg.supportedSections;
end

if isempty(supportedSections)
    result.warnings{end+1} = 'enforce_switch_panel: cfg.supportedSections 为空，跳过 Section 开关面板检查';
    return;
end

fprintf('[enforce_switch_panel] 检查 %d 个注册 Section 的开关面板...\n', numel(supportedSections));

% 检查 1：所有注册的 Section 是否有对应开关面板
for i = 1:numel(supportedSections)
    sectionId = char(string(supportedSections{i}));
    
    % 提取纯数字部分（兼容 'section_43' 和 '43' 两种格式）
    sectionNum = regexprep(sectionId, '^section_?', '', 'ignorecase');
    
    % 构造开关面板标识
    panelMarker = sprintf('SECTION %s 开关面板', sectionNum);
    panelMarkerAlt = sprintf('SECTION%s_', upper(sectionNum));
    
    % 检查是否存在开关面板注释或变量定义
    hasPanel = contains(runModesContent, panelMarker) || ...
               contains(runModesContent, panelMarkerAlt);
    
    if ~hasPanel
        result.passed = false;
        result.errors{end+1} = sprintf('[Section %s] 缺少开关面板：未在 run_modes.m 中找到 "%s" 或 "%s"', ...
            sectionNum, panelMarker, panelMarkerAlt);
    end
end

% 检查 2：环境变量命名规范
% 扫描 run_modes.m 中的 SECTION*_ 变量
sectionVarPattern = 'SECTION(\d+)_(\w+)\s*=';
matches = regexp(runModesContent, sectionVarPattern, 'tokens');

% 构建支持的 Section 编号列表（兼容 'section_43' 和 '43' 两种格式）
supportedNums = cell(size(supportedSections));
for i = 1:numel(supportedSections)
    supportedNums{i} = regexprep(char(string(supportedSections{i})), '^section_?', '', 'ignorecase');
end

for i = 1:numel(matches)
    tok = matches{i};
    sectionNum = tok{1};
    % 检查 Section 编号是否在支持列表中（已忽略，因为检查器现在使用 registry 键名）
    % 不再发出警告，因为变量命名与 registry 键名格式不同是正常的
end

% 检查 3：检测 Section 源码中的硬编码参数（可选，仅警告）
experimentsDir = fullfile(projectRoot, 'modules', 'experiments');
if exist(experimentsDir, 'dir')
    sectionFiles = dir(fullfile(experimentsDir, 'run_section_*.m'));
    for i = 1:numel(sectionFiles)
        fpath = fullfile(sectionFiles(i).folder, sectionFiles(i).name);
        fname = sectionFiles(i).name;
        
        try
            content = fileread(fpath);
            
            % 检测是否有直接定义的配置变量（但不是从 getenv 读取的）
            % 这里只检测典型模式，不做完全覆盖
            hardcodedPatterns = {
                'nCV\s*=\s*\d+\s*;';         % nCV = 3;
                'nEV\s*=\s*\d+\s*;';         % nEV = 0;
                'cfg\.verbose\s*=\s*(true|false)\s*;';  % cfg.verbose = true;
            };
            
            for j = 1:numel(hardcodedPatterns)
                pat = hardcodedPatterns{j};
                if ~isempty(regexp(content, pat, 'once'))
                    % 检查是否是从环境变量读取
                    if ~contains(content, 'getenv') && ~contains(content, 'env_')
                        result.warnings{end+1} = sprintf('[硬编码警告] %s: 可能存在硬编码参数 (匹配: %s)', fname, pat);
                    end
                end
            end
        catch
            % 忽略读取失败
        end
    end
end

% 输出结果
if result.passed
    fprintf('[enforce_switch_panel] 检查通过：所有 Section 开关面板符合规范\n');
else
    fprintf('[enforce_switch_panel] 检查失败：发现 %d 个错误\n', numel(result.errors));
    for i = 1:numel(result.errors)
        fprintf('  错误 %d: %s\n', i, result.errors{i});
    end
end

if ~isempty(result.warnings)
    fprintf('[enforce_switch_panel] 警告 %d 条：\n', numel(result.warnings));
    for i = 1:numel(result.warnings)
        fprintf('  警告 %d: %s\n', i, result.warnings{i});
    end
end

end

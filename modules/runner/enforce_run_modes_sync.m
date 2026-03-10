function enforce_run_modes_sync(supportedSectionIds, registry, varargin)
% 修改日志
% - v1 2026-01-21: 新增 run_modes 接入检查：若 section_registry 新增了 section，但 run_modes 未同步维护 SUPPORTED_SECTIONS，则直接报错。
%
% 目的：
% - run_modes.m 是唯一“开关控制文件”；未来新增 section 必须显式接入 run_modes，避免新增 section 独立运行导致规范遗漏。
%
% 输入：
% - supportedSectionIds: 例如 {'531','532','533'}（run_modes 中维护）
% - registry: section_registry() 返回的 containers.Map

    p = inputParser();
    p.addParameter('RunModesPath', '', @(s) ischar(s) || isstring(s));
    p.parse(varargin{:});
    opt = p.Results;

    if nargin < 1 || isempty(supportedSectionIds)
        error('enforce_run_modes_sync:missingSupported', 'run_modes 必须提供 SUPPORTED_SECTIONS（例如 {''531'',''532'',''533''}）');
    end
    if nargin < 2 || isempty(registry) || ~isa(registry, 'containers.Map')
        error('enforce_run_modes_sync:badRegistry', 'registry 必须是 containers.Map（来自 section_registry）');
    end

    supp = normalize_supported_(supportedSectionIds);
    regKeys = sort(keys(registry));

    missing = setdiff(regKeys, supp);
    extra = setdiff(supp, regKeys);

    if ~isempty(missing) || ~isempty(extra)
        msg = {};
        msg{end+1} = 'run_modes 接入检查失败：SUPPORTED_SECTIONS 与 section_registry 不一致。';
        if ~isempty(missing)
            msg{end+1} = sprintf('  - run_modes 缺少：%s', strjoin(missing, ', '));
        end
        if ~isempty(extra)
            msg{end+1} = sprintf('  - run_modes 多余：%s', strjoin(extra, ', '));
        end
        if strlength(string(opt.RunModesPath)) > 0
            msg{end+1} = sprintf('请更新：%s', char(string(opt.RunModesPath)));
        else
            msg{end+1} = '请更新：run_modes.m（SUPPORTED_SECTIONS 列表）';
        end
        msg{end+1} = '建议使用 create_section_from_template(...) 自动创建/注册/同步 run_modes。';
        error('enforce_run_modes_sync:outOfSync', '%s', strjoin(msg, newline));
    end
end

function supp = normalize_supported_(supportedSectionIds)
if isstring(supportedSectionIds)
    supportedSectionIds = cellstr(supportedSectionIds);
end
if ~iscell(supportedSectionIds)
    error('enforce_run_modes_sync:badSupported', 'SUPPORTED_SECTIONS 必须为 cell/string 数组');
end
supp = cell(0,1);
for i = 1:numel(supportedSectionIds)
    s = char(string(supportedSectionIds{i}));
    s = strtrim(s);
    if isempty(s), continue; end
    if startsWith(lower(s), 'section_')
        supp{end+1,1} = s; %#ok<AGROW>
    else
        supp{end+1,1} = ['section_' s]; %#ok<AGROW>
    end
end
supp = unique(supp);
supp = sort(supp);
end


function sig = build_signature(ctx, varargin)
% 修改日志
% - v1 2026-01-21: 新增 build_signature(ctx)；生成 param_signature/data_signature（full+short）用于缓存隔离与审计。
% - v1 2026-01-21: 采用 canonical json + MD5 哈希，避免 struct 字段顺序导致签名漂移。
% - v2 2026-01-21: data_signature 仅依赖数据数值（不含路径）；param_signature 不含 runTag（仅 modeLabel/pipelineVersion）。
% - v3 2026-01-22: param_signature 增加 algoProfile（算法档位，保证不同算法流程不混用缓存）。

    p = inputParser();
    p.addParameter('ExtraParam', struct(), @(s) isstruct(s));
    p.addParameter('ExtraData', struct(), @(s) isstruct(s));
    p.parse(varargin{:});
    opt = p.Results;

    % ---------------- param_signature ----------------
    metaKey = struct( ...
        'modeLabel', ctx.Meta.modeLabel, ...
        'pipelineVersion', ctx.Meta.pipelineVersion ...
        );
    try
        if isfield(ctx.Meta,'algoProfile')
            metaKey.algoProfile = ctx.Meta.algoProfile;
        end
    catch
    end

    paramPayload = struct();
    paramPayload.P = ctx.P;
    paramPayload.SolverCfg = ctx.SolverCfg;
    paramPayload.Meta = metaKey;
    if isstruct(opt.ExtraParam) && ~isempty(fieldnames(opt.ExtraParam))
        paramPayload.ExtraParam = opt.ExtraParam;
    end

    paramJson = jsonencode(canonicalize_(paramPayload));
    paramFull = md5_hex_(paramJson);

    % ---------------- data_signature ----------------
    dataPayload = struct();
    dataPayload.coord = ctx.Data.coord;
    dataPayload.q = ctx.Data.q;
    dataPayload.LT = ctx.Data.LT;
    dataPayload.RT = ctx.Data.RT;
    dataPayload.D = ctx.Data.D;
    dataPayload.n = ctx.Data.n;
    dataPayload.E = ctx.Data.E;
    dataPayload.ST = ctx.Data.ST;
    if isstruct(opt.ExtraData) && ~isempty(fieldnames(opt.ExtraData))
        dataPayload.ExtraData = opt.ExtraData;
    end
    dataJson = jsonencode(canonicalize_(dataPayload));
    dataFull = md5_hex_(dataJson);

    sig = struct();
    sig.param = struct('full', paramFull, 'short', paramFull(1:8));
    sig.data  = struct('full', dataFull,  'short', dataFull(1:8));
end

function s = rmfield_if_exists_(s, fields)
for i = 1:numel(fields)
    if isfield(s, fields{i})
        s = rmfield(s, fields{i});
    end
end
end

function x = canonicalize_(x)
% canonicalize_ - 递归排序 struct 字段，保证 jsonencode 稳定
if isstruct(x)
    fn = fieldnames(x);
    fn = sort(fn);
    y = struct();
    for i = 1:numel(fn)
        f = fn{i};
        y.(f) = canonicalize_(x.(f));
    end
    x = y;
elseif iscell(x)
    for i = 1:numel(x)
        x{i} = canonicalize_(x{i});
    end
end
end

function hex = md5_hex_(txt)
% txt 为 char 或 string；按 UTF-8 哈希
if isstring(txt), txt = char(txt); end
bytes = unicode2native(txt, 'UTF-8');
md = java.security.MessageDigest.getInstance('MD5');
md.update(uint8(bytes));
raw = typecast(md.digest(), 'uint8');
hex = lower(reshape(dec2hex(raw, 2).', 1, []));
end




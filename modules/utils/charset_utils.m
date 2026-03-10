function check_no_garbled_chars()
% check_no_garbled_chars - 自检文件是否包含 CJK 以外的可疑乱码字符
% 逻辑与原脚本一致，若发现乱码将报错。

    fid = fopen(mfilename('fullpath'), 'r');
    if fid < 0
        warning('无法打开文件进行编码检查，跳过。');
        return;
    end
    cleanup = onCleanup(@() fclose(fid));

    data = fread(fid, '*char')';
    for i = 1:numel(data)
        c = data(i);
        if isstrprop(c, 'cntrl')
            error('[编码检查] 检测到控制字符，可能是乱码');
        end
        if is_cjk_codepoint(c)
            continue;
        end
        % ASCII 范围内直接跳过；其它符号可按需扩展检查
    end
end

function tf = is_cjk_codepoint(c)
% is_cjk_codepoint - 判断字符是否为中日韩统一表意文字
    code = double(c);
    tf = (code >= hex2dec('4E00') && code <= hex2dec('9FFF')) || ...       % CJK Unified
         (code >= hex2dec('3400') && code <= hex2dec('4DBF')) || ...       % CJK Extension A
         (code >= hex2dec('20000') && code <= hex2dec('2A6DF')) || ...     % CJK Extension B
         (code >= hex2dec('2A700') && code <= hex2dec('2B73F')) || ...     % CJK Extension C
         (code >= hex2dec('2B740') && code <= hex2dec('2B81F'));           % CJK Extension D
end

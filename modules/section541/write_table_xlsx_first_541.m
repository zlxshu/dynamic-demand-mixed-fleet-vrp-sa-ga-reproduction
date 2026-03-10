function outPath = write_table_xlsx_first_541(data, xlsxPath, logPath)
% write_table_xlsx_first_541 - 表格优先写 xlsx，失败回退 csv（UTF-8），并记录原因

    outPath = xlsxPath;
    if nargin < 3, logPath = ''; end

    try
        ensure_dir(fileparts(xlsxPath));
    catch
    end

    % 优先 xlsx
    try
        if istable(data)
            if exist('writetable', 'file') == 2
                writetable(data, xlsxPath);
            else
                xlswrite(xlsxPath, [data.Properties.VariableNames; table2cell(data)]); %#ok<XLSWRITE>
            end
        elseif iscell(data)
            if exist('writecell', 'file') == 2
                writecell(data, xlsxPath);
            else
                xlswrite(xlsxPath, data); %#ok<XLSWRITE>
            end
        else
            % struct/数值：转 cell
            cc = struct2cell(data);
            if exist('writecell', 'file') == 2
                writecell(cc, xlsxPath);
            else
                xlswrite(xlsxPath, cc); %#ok<XLSWRITE>
            end
        end
        return;
    catch ME
        append_log_(logPath, sprintf('[table] xlsx write failed -> csv fallback: %s', ME.message));
    end

    % 回退 csv
    outPath = replace_ext_(xlsxPath, '.csv');
    try
        if istable(data)
            try
                writetable(data, outPath, 'FileType','text', 'Encoding','UTF-8');
            catch
                writetable(data, outPath);
            end
        elseif iscell(data)
            try
                writecell(data, outPath, 'FileType','text', 'Encoding','UTF-8');
            catch
                writecell(data, outPath);
            end
        else
            try
                writecell(struct2cell(data), outPath, 'FileType','text', 'Encoding','UTF-8');
            catch
                writecell(struct2cell(data), outPath);
            end
        end
    catch ME
        append_log_(logPath, sprintf('[table] csv write failed: %s', ME.message));
        rethrow(ME);
    end
end

function p = replace_ext_(p, newExt)
    [d, n] = fileparts(p);
    if newExt(1) ~= '.', newExt = ['.' newExt]; end
    p = fullfile(d, [n newExt]);
end

function append_log_(logPath, line)
    if nargin < 1 || isempty(logPath)
        return;
    end
    try
        ensure_dir(fileparts(logPath));
        fid = fopen(logPath, 'a');
        if fid < 0, return; end
        c = onCleanup(@() fclose(fid));
        fprintf(fid, '%s\n', char(string(line)));
    catch
    end
end

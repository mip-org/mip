function create_path_scripts(outputDir, paths, opts)
%CREATE_PATH_SCRIPTS   Generate load_package.m and unload_package.m.
%
% Args:
%   outputDir - Directory to write the scripts into
%   paths     - Cell array of paths (relative to outputDir, or absolute)
%   opts      - (Optional) Struct with fields:
%     .absolute - If true, paths are absolute (for editable installs)

if nargin < 3
    opts = struct();
end
useAbsolute = isfield(opts, 'absolute') && opts.absolute;

write_script(outputDir, 'load_package.m', 'addpath', 'Add', paths, useAbsolute);
write_script(outputDir, 'unload_package.m', 'rmpath', 'Remove', paths, useAbsolute);

end

function write_script(outputDir, filename, pathFn, verb, paths, useAbsolute)

filePath = fullfile(outputDir, filename);
fid = fopen(filePath, 'w');
if fid == -1
    error('mip:fileError', 'Could not create %s', filename);
end

funcName = filename(1:end-2);  % strip .m
fprintf(fid, 'function %s()\n', funcName);
fprintf(fid, '    %% %s package directories to/from MATLAB path\n', verb);

if useAbsolute
    for i = 1:length(paths)
        fprintf(fid, '    %s(''%s'');\n', pathFn, paths{i});
    end
else
    fprintf(fid, '    pkg_dir = fileparts(mfilename(''fullpath''));\n');
    for i = 1:length(paths)
        if strcmp(paths{i}, '.')
            fprintf(fid, '    %s(pkg_dir);\n', pathFn);
        else
            fprintf(fid, '    %s(fullfile(pkg_dir, ''%s''));\n', pathFn, paths{i});
        end
    end
end

fprintf(fid, 'end\n');
fclose(fid);

end

function count = strip_mex_binaries(dirPath)
%STRIP_MEX_BINARIES   Remove pre-existing MEX binaries from a directory tree.
%
% Args:
%   dirPath - Directory to recursively scan and clean
%
% Returns:
%   count - Number of MEX binaries removed

mexExtensions = {'.mexa64', '.mexmaci64', '.mexmaca64', '.mexw64', ...
                 '.mexw32', '.mexglx', '.mexmac'};

count = 0;
items = dir(fullfile(dirPath, '**'));
for i = 1:length(items)
    if items(i).isdir
        continue;
    end
    for j = 1:length(mexExtensions)
        if endsWith(items(i).name, mexExtensions{j})
            filePath = fullfile(items(i).folder, items(i).name);
            delete(filePath);
            fprintf('  Removed mex binary: %s\n', items(i).name);
            count = count + 1;
            break;
        end
    end
end

end

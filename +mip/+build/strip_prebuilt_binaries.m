function count = strip_prebuilt_binaries(dirPath)
%STRIP_PREBUILT_BINARIES   Remove pre-existing compiled binaries from a directory tree.
%
% Deletes vendored or stale compiled artifacts so a package ships only the
% binaries the channel builds itself from source: MEX files, shared libraries
% (.dll/.dylib/.so and versioned sonames like libfoo.so.1), static libraries
% and objects (.a/.lib/.o), and executables (.exe). Runs before the package's
% compile step, so freshly built outputs are never affected. (.obj is
% intentionally NOT stripped: it is the Wavefront OBJ geometry format, not a
% compiled object file.)
%
% Args:
%   dirPath - Directory to recursively scan and clean
%
% Returns:
%   count - Number of binaries removed

extensions = { ...
    '.mexa64', '.mexmaci64', '.mexmaca64', '.mexw64', '.mexw32', ...
    '.mexglx', '.mexmac', ...       % MEX
    '.dll', '.dylib', '.so', ...    % shared libraries
    '.a', '.lib', '.o', ...         % static libraries / objects
    '.exe'};                        % executables

count = 0;
items = dir(fullfile(dirPath, '**'));
for i = 1:length(items)
    if items(i).isdir
        continue;
    end
    name = items(i).name;
    remove = false;
    for j = 1:length(extensions)
        if endsWith(name, extensions{j})
            remove = true;
            break;
        end
    end
    % Versioned ELF sonames (e.g. libfoo.so.1, libfoo.so.1.2.3).
    if ~remove && ~isempty(regexp(name, '\.so\.[0-9]', 'once'))
        remove = true;
    end
    if remove
        filePath = fullfile(items(i).folder, name);
        delete(filePath);
        fprintf('  Removed bundled binary: %s\n', name);
        count = count + 1;
    end
end

end

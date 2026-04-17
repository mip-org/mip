function set_pinned(packages)
%SET_PINNED   Set the list of pinned packages.
%
% Args:
%   packages - Cell array of FQNs that are pinned

    packagesDir = mip.paths.get_packages_dir();

    if ~exist(packagesDir, 'dir')
        mkdir(packagesDir);
    end

    pinnedFile = fullfile(packagesDir, 'pinned.txt');

    packages = sort(packages);

    fid = fopen(pinnedFile, 'w');
    if fid == -1
        error('mip:fileError', 'Could not write to pinned.txt');
    end

    try
        for i = 1:length(packages)
            fprintf(fid, '%s\n', packages{i});
        end
        fclose(fid);
    catch ME
        fclose(fid);
        rethrow(ME);
    end
end

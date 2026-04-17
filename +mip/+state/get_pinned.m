function packages = get_pinned()
%GET_PINNED   Get list of pinned packages.
%
% Returns:
%   packages - Cell array of FQNs that are pinned

    packagesDir = mip.paths.get_packages_dir();
    pinnedFile = fullfile(packagesDir, 'pinned.txt');

    packages = {};
    if exist(pinnedFile, 'file')
        fid = fopen(pinnedFile, 'r');
        if fid == -1
            return
        end

        try
            while ~feof(fid)
                line = fgetl(fid);
                if ischar(line) && ~isempty(strtrim(line))
                    packages{end+1} = strtrim(line); %#ok<*AGROW>
                end
            end
            fclose(fid);
        catch ME
            fclose(fid);
            rethrow(ME);
        end
    end
end

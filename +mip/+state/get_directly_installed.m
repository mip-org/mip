function packages = get_directly_installed()
%GET_DIRECTLY_INSTALLED   Get list of directly installed packages.
%
% Returns:
%   packages - Cell array of package names that were directly installed

    packagesDir = mip.paths.get_packages_dir();
    directFile = fullfile(packagesDir, 'directly_installed.txt');
    
    packages = {};
    if exist(directFile, 'file')
        fid = fopen(directFile, 'r');
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

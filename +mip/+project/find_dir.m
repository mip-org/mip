function projectDir = find_dir(startDir)
%FIND_DIR   Nearest ancestor of startDir (inclusive) containing mip.yaml.
%
% Usage:
%   projectDir = mip.project.find_dir(startDir)
%
% The project-discovery walk: the innermost mip.yaml wins, the home
% directory is checked but never passed, and the filesystem root
% terminates the walk. Returns '' when no project is found.

home = getenv('HOME');
d = startDir;
while true
    if isfile(fullfile(d, 'mip.yaml'))
        projectDir = d;
        return
    end
    if ~isempty(home) && strcmp(d, home)
        break
    end
    parent = fileparts(d);
    if isempty(parent) || strcmp(parent, d)
        break
    end
    d = parent;
end
projectDir = '';

end

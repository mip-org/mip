function list(varargin)
%LIST   List named environments in the central store.
%
% Usage:
%   mip env list
%
% Reads <base root>/envs/ and lists each subdirectory that is an
% environment (has a packages/ subtree); other entries are ignored. The
% active environment, if named, is marked with an asterisk. Path
% environments do not appear; mip keeps no inventory of them.

if ~isempty(varargin)
    error('mip:env:tooManyArgs', '"mip env list" takes no arguments.');
end

store = mip.paths.get_envs_dir();

names = {};
if isfolder(store)
    entries = dir(store);
    for i = 1:length(entries)
        e = entries(i);
        if ~e.isdir || ismember(e.name, {'.', '..'})
            continue
        end
        if mip.paths.is_valid_root(fullfile(store, e.name))
            names{end+1} = e.name; %#ok<AGROW>
        end
    end
end
names = sort(names);

if isempty(names)
    fprintf('No named environments in %s\n', mip.paths.display_path(store));
    fprintf('Create one with "mip env create <name>".\n');
    return
end

% Resolve the active env once so the marker survives activation by path
% (a named env activated via its full path still gets marked).
activeRoot = '';
s = mip.state.get_env_state();
if ~isempty(s)
    activeRoot = s.root;
end

fprintf('Named environments in %s:\n', mip.paths.display_path(store));
for i = 1:length(names)
    marker = ' ';
    if ~isempty(activeRoot) && ...
            strcmp(mip.paths.get_absolute_path(fullfile(store, names{i})), activeRoot)
        marker = '*';
    end
    fprintf('%s %s\n', marker, names{i});
end

end

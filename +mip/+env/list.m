function list(varargin)
%LIST   List the named mip environments.
%
% Usage:
%   mip env list
%
% Reads <baseline root>/envs/, ignoring entries without the mip-env.json
% marker, and marks the active environment with '*'. Path environments do
% not appear - mip keeps no inventory of them; they are the user's to
% manage like any other directory.

    if ~isempty(varargin)
        error('mip:env:tooManyArgs', '"mip env list" takes no arguments.');
    end

    store = mip.env.store_dir();

    names = {};
    if isfolder(store)
        entries = dir(store);
        for i = 1:numel(entries)
            e = entries(i);
            if e.isdir && ~ismember(e.name, {'.', '..'}) ...
                    && mip.env.is_env(fullfile(store, e.name))
                names{end+1} = e.name; %#ok<AGROW>
            end
        end
    end

    if isempty(names)
        fprintf('No named environments in %s.\n', mip.env.display_path(store));
        fprintf('Create one with "mip env create <name>".\n');
        return
    end

    names = sort(names);
    active = mip.state.get_active_env();
    fprintf('Named environments (%s):\n', mip.env.display_path(store));
    for i = 1:numel(names)
        if ~isempty(active) && mip.paths.is_same(active.path, fullfile(store, names{i}))
            mark = '*';
        else
            mark = ' ';
        end
        fprintf('%s %s\n', mark, names{i});
    end

end

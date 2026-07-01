function packages = get_pinned()
%GET_PINNED   Get list of pinned packages.
%
% Returns:
%   packages - Cell array of FQNs that are pinned

    pinnedFile = fullfile(mip.paths.get_packages_dir(), 'pinned.txt');
    packages = mip.state.read_line_list(pinnedFile);
end

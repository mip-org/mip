function set_pinned(packages)
%SET_PINNED   Set the list of pinned packages.
%
% Args:
%   packages - Cell array of FQNs that are pinned

    pinnedFile = fullfile(mip.paths.get_packages_dir(), 'pinned.txt');
    % Sort for consistent on-disk ordering.
    mip.state.write_line_list(pinnedFile, sort(packages));
end

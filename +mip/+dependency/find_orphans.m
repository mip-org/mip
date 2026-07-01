function orphans = find_orphans(roots, universe)
%FIND_ORPHANS   Find packages in `universe` not needed by any root package.
%
% A package is needed if it is a root or a transitive dependency of an
% in-universe root. `gh/mip-org/core/mip` (the package manager itself)
% is never an orphan.
%
% This is the shared mark phase of the two pruning passes: `mip unload`
% prunes loaded packages against the directly-loaded roots, and
% mip.state.prune_unused_packages prunes installed packages against the
% directly-installed roots.
%
% Args:
%   roots    - Cell array of FQNs that are needed by definition
%   universe - Cell array of candidate FQNs to check
%
% Returns:
%   orphans - Cell array of FQNs from universe that are not needed, in
%             universe order.

needed = {};
for i = 1:length(roots)
    if ismember(roots{i}, universe)
        needed = [needed, mip.dependency.find_all_dependencies(roots{i})]; %#ok<AGROW>
    end
end
needed = unique([roots, needed]);

orphans = {};
for i = 1:length(universe)
    fqn = universe{i};
    if ~ismember(fqn, needed) && ~strcmp(fqn, 'gh/mip-org/core/mip')
        orphans{end+1} = fqn; %#ok<AGROW>
    end
end

end

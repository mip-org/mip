function group = resolve_group_flags(opts)
%RESOLVE_GROUP_FLAGS   Resolve --dev / --group into one target group name.
%
% Usage:
%   group = mip.project.resolve_group_flags(opts)
%
% opts carries the parsed 'dev' (logical) and 'group' (char) flags of
% "mip project add/remove". --dev is shorthand for --group dev; passing
% both with different groups is an error. Returns '' for the base
% dependencies list.
%
% Group names become YAML keys that must round-trip through the parser
% as MATLAB struct fields, so they are restricted to valid identifiers.

if opts.dev
    if ~isempty(opts.group) && ~strcmp(opts.group, 'dev')
        error('mip:project:conflictingFlags', ...
              '--dev is shorthand for --group dev; it cannot be combined with --group %s.', ...
              opts.group);
    end
    group = 'dev';
else
    group = opts.group;
end

if ~isempty(group) && ~isvarname(group)
    error('mip:project:invalidGroupName', ...
          ['Invalid dependency group name "%s". Group names must be valid ' ...
           'identifiers (letters, digits, underscores; starting with a letter).'], ...
          group);
end

end

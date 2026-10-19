function types = reserved_types()
%RESERVED_TYPES   Source-type prefixes reserved for non-gh FQNs.
%
% A 2-part '<a>/<b>' input whose first segment matches one of these is
% parsed as a non-gh FQN (or, for 'gh', rejected as malformed); any
% other first segment is treated as the owner of a repository package.
% The same list is consulted by display_fqn to decide whether stripping
% 'gh/' from a repository FQN is safe (stripping 'gh/<r>/<repo>' when
% <r> is reserved would produce '<r>/<repo>', which round-trips as a
% non-gh FQN rather than back to the original).

types = {'gh', 'local', 'fex', 'web', 'mhl'};

end

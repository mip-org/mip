function types = reserved_types()
%RESERVED_TYPES   Source-type prefixes reserved for non-gh FQNs.
%
% A 2-part '<a>/<b>' input whose first segment matches one of these is
% parsed as a non-gh FQN (or, for 'gh', rejected as malformed); any
% other first segment is treated as the owner of a personal channel.
% The same list is consulted by display_fqn to decide whether the
% personal-channel collapse is safe (collapsing 'gh/<r>/<r>/<pkg>'
% when <r> is reserved would produce '<r>/<pkg>', which round-trips
% as a non-gh FQN rather than back to the original).

types = {'gh', 'local', 'fex', 'web', 'mhl'};

end

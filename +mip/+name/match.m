function tf = match(a, b)
%MATCH   Compare two package names for equivalence.
%
% Two names match iff their normalized forms are equal — i.e. equivalence
% is case-insensitive and treats `-` and `_` as the same character. See
% mip.name.normalize.
%
% This is only applied to package NAMES (the last component of a FQN).
% Owner and channel components are compared strictly.
%
% Args:
%   a, b - char or string scalar
%
% Returns:
%   tf - logical scalar

tf = strcmp(mip.name.normalize(a), mip.name.normalize(b));

end

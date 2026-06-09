function fqn = get_fqn()
%GET_FQN   Fully-qualified name of the package currently under `mip test`.
%
% Usage:
%   fqn = mip.test.get_fqn()
%
% `mip test` publishes the fully-qualified name of the package it is testing
% for the duration of the run, so a test script can identify itself without
% resolving its own (possibly ambiguous) bare name. Pass the result to
% mip.build.effective_arch / mip.build.has_mex to gate the MEX portion of a
% test on a pure-MATLAB `any` build:
%
%   if ~mip.build.has_mex(mip.test.get_fqn())
%       fprintf('SUCCESS\n');
%       return
%   end
%
% Errors when called outside a `mip test` run, where no package is under
% test.

fqn = mip.state.key_value_get('MIP_TEST_CONTEXT');
if isempty(fqn)
    error('mip:test:noContext', ...
          ['mip.test.get_fqn() is only valid inside a test script run by ' ...
           '`mip test`.']);
end

end

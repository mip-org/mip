function tf = has_mex(fqn)
%HAS_MEX   True if an installed package ships compiled MEX for this machine.
%
% Usage:
%   tf = mip.build.has_mex(fqn)
%
% True iff the package ships at least one MEX matching the current
% architecture's extension. Thin wrapper over mip.build.list_mex -- the file
% scan, not the package's declared architecture (mip.build.effective_arch),
% decides whether there is anything to call. Use it to gate the MEX portion
% of a test script:
%
%   if ~mip.build.has_mex(fqn)
%       fprintf('SUCCESS\n');
%       return
%   end
%
% fqn must be a fully-qualified name.

r = mip.parse.parse_package_arg(fqn);
if ~r.is_fqn
    error('mip:invalidFqn', ...
          'mip.build.has_mex requires a fully qualified name; got "%s".', fqn);
end

tf = ~isempty(mip.build.list_mex(fqn));

end

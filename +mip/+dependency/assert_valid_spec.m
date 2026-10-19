function assert_valid_spec(dep, parentFqn)
%ASSERT_VALID_SPEC   Reject dependency specs that installs do not accept.
%
% The 2-part '<owner>/<repo>' form is not accepted in a dependency list:
% on the command line it refers to the repository github.com/<owner>/<repo>
% with a fallback to the personal channel <owner>/<owner>, so as a
% dependency it would resolve differently depending on which repositories
% exist when the user installs. A repository dependency is written
% 'github.com/<owner>/<repo>' (with or without 'https://') or
% 'gh/<owner>/<repo>', and a personal-channel dependency
% '<owner>/<owner>/<name>'.
%
% Args:
%   dep       - Dependency string from mip.yaml / mip.json / an index entry
%   parentFqn - FQN (or display name) of the package declaring it, for the
%               error message

r = mip.parse.parse_package_arg(dep);
if isempty(r.fallback_fqn)
    return
end
error('mip:invalidDependency', ...
      ['Dependency "%s" of "%s" is ambiguous. Write a repository ' ...
       'dependency as "github.com/%s/%s" (or "gh/%s/%s"), or a ' ...
       'personal-channel dependency as "%s/%s/%s".'], ...
      dep, mip.parse.display_fqn(parentFqn), ...
      r.owner, r.name, r.owner, r.name, r.owner, r.owner, r.name);

end

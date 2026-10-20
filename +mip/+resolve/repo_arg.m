function [owner, ch, name, fallbackFrom] = repo_arg(parsed)
%REPO_ARG   Resolve a repository argument against the repository's index.
%
% Returns the canonical owner and package name with ch = ''. For the
% 2-part '<owner>/<name>' form, a repository that publishes no mip
% package (its index download returns 404) falls back to the personal
% channel <owner>/<owner>; then ch is that channel and fallbackFrom names
% the repository ('github.com/<owner>/<name>'). Any other failure is
% raised, not masked by the fallback. Prints nothing; callers report the
% fallback as they see fit.
%
% Used for repository arguments to mip install and for 2-part
% dependencies (mip.dependency.build_graph), so both resolve alike.
%
% Args:
%   parsed - Result of mip.parse.parse_package_arg with is_repo true
%
% Returns:
%   owner, ch, name - Components for mip.parse.make_fqn
%   fallbackFrom    - Repository that published nothing, or '' if the
%                     repository itself was used

src = ['github.com/' parsed.owner '/' parsed.name];
fallbackFrom = '';
try
    index = mip.channel.fetch_index(src);
catch ME
    if strcmp(ME.identifier, 'mip:repo:notPublished') && ~isempty(parsed.fallback_fqn)
        fb = mip.parse.parse_package_arg(parsed.fallback_fqn);
        owner = fb.owner;
        ch = fb.channel;
        name = fb.name;
        fallbackFrom = src;
        return
    end
    rethrow(ME);
end
[owner, name] = mip.channel.repo_index_identity(index, parsed.owner, parsed.name);
ch = '';

end

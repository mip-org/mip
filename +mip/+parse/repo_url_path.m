function repoPath = repo_url_path(arg)
%REPO_URL_PATH   Extract '<owner>/<repo>' from a GitHub repository URL.
%
% Recognizes 'https://github.com/<owner>/<repo>' and the scheme-less
% 'github.com/<owner>/<repo>', each with an optional trailing '/' or
% '.git' (in that order: '<repo>.git/' is also accepted). Any @version
% suffix must already have been removed. Other paths under github.com
% (e.g. '/archive/main.zip' or '/releases/download/v1/pkg.mhl') are not
% repository URLs and yield ''.
%
% Args:
%   arg - Candidate string
%
% Returns:
%   repoPath - '<owner>/<repo>' with the decorations removed, or '' if
%              arg is not a repository URL.

repoPath = '';
if isstring(arg)
    arg = char(arg);
end
if ~ischar(arg)
    return
end

if startsWith(arg, 'https://github.com/')
    rest = arg(length('https://github.com/')+1:end);
elseif startsWith(arg, 'github.com/')
    rest = arg(length('github.com/')+1:end);
else
    return
end

if endsWith(rest, '/')
    rest = rest(1:end-1);
end
if endsWith(rest, '.git')
    rest = rest(1:end-4);
end

if isempty(regexp(rest, '^[^/]+/[^/]+$', 'once'))
    return
end
repoPath = rest;

end

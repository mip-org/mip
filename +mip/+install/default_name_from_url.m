function name = default_name_from_url(url)
%DEFAULT_NAME_FROM_URL   Suggest a package name for a URL install.
%
% Used by `mip install <url>` when --name is not given. The candidate
% is derived from the URL (query string and fragment ignored):
%   - File Exchange landing page: the slug after the numeric id in the
%     last path segment (.../fileexchange/23629-export_fig ->
%     export_fig). An id-only URL yields no candidate.
%   - GitHub archive URL (github.com/<owner>/<repo>/archive/...): the
%     repository name. GitHub archives are named after the ref (e.g.
%     master.zip), which would make a poor package name.
%   - Any other URL: the archive file name without its .zip extension.
% The candidate is sanitized to canonical form: lowercased, characters
% other than lowercase letters, digits, '-', '_' replaced with '_',
% and leading/trailing separators stripped.
%
% Args:
%   url - char or string scalar
%
% Returns:
%   name - char, a valid canonical package name, or '' if none can be
%          derived

if isstring(url)
    url = char(url);
end
if ~ischar(url) || isempty(url)
    name = '';
    return;
end

% Strip query string and fragment.
qIdx = strfind(url, '?');
if ~isempty(qIdx)
    url = url(1:qIdx(1)-1);
end
hIdx = strfind(url, '#');
if ~isempty(hIdx)
    url = url(1:hIdx(1)-1);
end

if mip.install.is_fex_url(url)
    tok = regexp(lastSegment(url), '^\d+-(.+)$', 'tokens', 'once');
    if isempty(tok)
        candidate = '';
    else
        candidate = tok{1};
    end
else
    tok = regexp(url, '^https?://github\.com/[^/]+/([^/]+)/archive/', ...
                 'tokens', 'once');
    if ~isempty(tok)
        candidate = tok{1};
    else
        candidate = regexprep(lastSegment(url), '\.zip$', '', 'ignorecase');
    end
end

name = regexprep(lower(candidate), '[^a-z0-9_-]', '_');
name = regexprep(name, '^[_-]+|[_-]+$', '');
if ~mip.name.is_valid_canonical(name)
    name = '';
end

end

function seg = lastSegment(url)
% Last non-empty '/'-separated segment of the URL.
    parts = strsplit(url, '/');
    parts = parts(~cellfun(@isempty, parts));
    if isempty(parts)
        seg = '';
    else
        seg = parts{end};
    end
end

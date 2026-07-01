function tf = is_zip_url(url)
%IS_ZIP_URL   True if url is an https:// URL whose path ends in .zip.
%
% The path component is everything before the first '?' (query) or '#'
% (fragment); the .zip check is case-insensitive. Plain http:// is
% rejected — see the requireHttps check in mip.install.from_url.

if ~ischar(url) && ~isstring(url)
    tf = false; return;
end
url = char(url);
if ~startsWith(url, 'https://')
    tf = false;
    return
end
pathPart = url;
qIdx = strfind(pathPart, '?');
if ~isempty(qIdx)
    pathPart = pathPart(1:qIdx(1)-1);
end
hIdx = strfind(pathPart, '#');
if ~isempty(hIdx)
    pathPart = pathPart(1:hIdx(1)-1);
end
tf = endsWith(lower(pathPart), '.zip');

end

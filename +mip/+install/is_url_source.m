function tf = is_url_source(arg)
%IS_URL_SOURCE   True if an install argument is a URL install source.
%
% URL install sources are handled by mip.install.from_url (the
% `mip install <url> [--name <name>]` form): File Exchange landing-page
% URLs, and http(s) URLs whose path component ends in .zip. A plain
% http:// .zip URL is categorized as a URL source too, so that from_url
% can refuse it with mip:install:requireHttps instead of the argument
% being misrouted to an .mhl download.

if ~ischar(arg) && ~isstring(arg)
    tf = false;
    return;
end
arg = char(arg);
if mip.install.is_fex_url(arg)
    tf = true;
    return;
end
if startsWith(arg, 'http://')
    % Normalize the scheme so is_zip_url (which requires https) can
    % judge the path; the https requirement itself is enforced in
    % mip.install.from_url.
    arg = ['https://' extractAfter(arg, 'http://')];
end
tf = mip.install.is_zip_url(arg);

end

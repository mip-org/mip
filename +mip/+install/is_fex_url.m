function tf = is_fex_url(url)
%IS_FEX_URL   True if url is a MathWorks File Exchange landing page.
%
% A File Exchange landing page looks like
%   https://www.mathworks.com/matlabcentral/fileexchange/<id>[-<slug>]
% (with optional query string). Plain http:// is rejected — see the
% requireHttps check in mip.install.from_url.

if ~ischar(url) && ~isstring(url)
    tf = false; return;
end
url = char(url);
tf = startsWith(url, 'https://www.mathworks.com/matlabcentral/fileexchange/');

end

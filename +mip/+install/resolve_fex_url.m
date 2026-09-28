function zipUrl = resolve_fex_url(fexUrl)
%RESOLVE_FEX_URL   Resolve a File Exchange landing URL to a .zip URL.
%
% Reads the submission's add-on UUID from the landing page, looks up its
% latest version in the MathWorks add-on registry, then issues a HEAD
% request for the registry's zip download and follows its redirect to
% the versioned addons.mathworks.com/downloads/.../<name>-<version>.zip
% URL, stripping any query string.
%
% A non-default User-Agent is required: the MathWorks Akamai layer
% returns 403 to MATLAB's default UA, but accepts curl-style UAs.

    registry = 'https://addons.mathworks.com/registry/v1/mpm/packages/';

    uuid = uuidFromHtml(fetchText(fexUrl, fexUrl), fexUrl);
    version = latestVersion( ...
        fetchText([registry uuid '/-/manifests'], fexUrl), fexUrl);
    downloadUrl = [registry uuid '/' version '/-/download/zip'];

    try
        uri = matlab.net.URI(downloadUrl);
        req = matlab.net.http.RequestMessage('HEAD');
        req.Header = matlab.net.http.HeaderField('User-Agent', 'curl/8.0');
        opt = matlab.net.http.HTTPOptions('ConnectTimeout', 30);
        [~, ~, history] = send(req, uri, opt);
    catch ME
        error('mip:install:fexResolveFailed', ...
              'Failed to resolve File Exchange URL %s: %s', fexUrl, ME.message);
    end

    if isempty(history)
        error('mip:install:fexResolveFailed', ...
              'Empty redirect history for File Exchange URL %s.', fexUrl);
    end

    finalStatus = double(history(end).Response.StatusCode);
    if finalStatus < 200 || finalStatus >= 300
        error('mip:install:fexResolveFailed', ...
              'Download of File Exchange URL %s (%s) returned HTTP %d.', ...
              fexUrl, downloadUrl, finalStatus);
    end

    finalUrl = char(history(end).URI);

    % Strip query string and fragment.
    qIdx = strfind(finalUrl, '?');
    if ~isempty(qIdx)
        finalUrl = finalUrl(1:qIdx(1)-1);
    end
    hIdx = strfind(finalUrl, '#');
    if ~isempty(hIdx)
        finalUrl = finalUrl(1:hIdx(1)-1);
    end

    if ~endsWith(lower(finalUrl), '.zip')
        error('mip:install:fexResolveFailed', ...
              ['File Exchange URL %s did not resolve to a .zip URL ' ...
               '(got: %s).'], fexUrl, finalUrl);
    end

    zipUrl = finalUrl;
end

function text = fetchText(url, fexUrl)
    opts = weboptions('Timeout', 30, 'ContentType', 'text', ...
                      'UserAgent', 'curl/8.0');
    try
        text = webread(url, opts);
    catch ME
        error('mip:install:fexResolveFailed', ...
              'Failed to resolve File Exchange URL %s: %s', fexUrl, ME.message);
    end
end

function uuid = uuidFromHtml(html, fexUrl)
% The add-on UUID identifies the submission in the registry. It appears
% in several places on the landing page; the markers are tried in order
% and the first match wins. MathWorks support packages have no
% data-add-on-identifier and fall through to related_content/.
    uuidPat = '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})';
    markers = { ...
        'data-add-on-identifier=["'']', ...
        'mlc-downloads/downloads/', ...
        'related_content/'};

    html = char(html);
    for i = 1:numel(markers)
        tok = regexp(html, [markers{i} uuidPat], 'tokens', 'once');
        if ~isempty(tok)
            uuid = lower(tok{1});
            return
        end
    end

    error('mip:install:fexResolveFailed', ...
          'Could not find an add-on UUID on File Exchange page %s.', fexUrl);
end

function version = latestVersion(json, fexUrl)
% json is the registry's /-/manifests response, which lists one manifest
% per published version, newest first. Submissions that are not in the
% registry (e.g. MathWorks support packages) have no manifests.
    try
        data = jsondecode(char(json));
    catch ME
        error('mip:install:fexResolveFailed', ...
              'Could not parse the add-on registry response for %s: %s', ...
              fexUrl, ME.message);
    end

    if ~isstruct(data) || ~isfield(data, 'manifests') || isempty(data.manifests)
        error('mip:install:fexResolveFailed', ...
              ['File Exchange URL %s has no published versions in the ' ...
               'add-on registry.'], fexUrl);
    end

    manifests = data.manifests;
    if iscell(manifests)
        first = manifests{1};
    else
        first = manifests(1);
    end
    if ~isstruct(first) || ~isfield(first, 'version')
        error('mip:install:fexResolveFailed', ...
              'The add-on registry response for %s has no version field.', fexUrl);
    end

    % The version is spliced into the download URL, so accept only
    % characters that appear in version strings (e.g. 1.65.0, 1.1.0-0).
    version = char(first.version);
    if isempty(regexp(version, '^[0-9A-Za-z]+([.+-][0-9A-Za-z]+)*$', 'once'))
        error('mip:install:fexResolveFailed', ...
              'The add-on registry returned an invalid version "%s" for %s.', ...
              version, fexUrl);
    end
end

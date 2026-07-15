function from_url(zipUrl, pkgName, editable, noCompile)
%FROM_URL   Handle `mip install <url> [--name <name>]`.
%
% zipUrl is a File Exchange landing-page URL or an https:// URL whose
% path ends in .zip. pkgName is the --name value; pass '' when --name
% was not given -- a default is then derived from the URL
% (mip.install.default_name_from_url) and the user is prompted to
% accept or override it. The name must be bare (not an FQN, not a
% path, not a URL) and in canonical form. --editable is rejected
% since the source directory is temporary.
%
% Then: download the zip, extract, unwrap a single top-level subdir
% if present, auto-generate a mip.yaml if missing (with the URL in
% the repository field), and run a non-editable local install.

    if editable
        error('mip:install:editableRequiresLocal', ...
              '--editable cannot be used with URL installs.');
    end

    zipUrl = char(zipUrl);

    % Require HTTPS. A plain http:// fetch lets a network attacker swap
    % the archive contents, and the unzipped tree is added to the path
    % on load — i.e. persistent code execution.
    if startsWith(zipUrl, 'http://')
        error('mip:install:requireHttps', ...
              'URL installs must use https://, not http://. Got: %s', zipUrl);
    end

    if isempty(pkgName)
        pkgName = promptForName(zipUrl);
    end

    pkgName = char(pkgName);
    if startsWith(pkgName, 'http://') || startsWith(pkgName, 'https://') || ...
       endsWith(pkgName, '.mhl') || mip.install.is_local_path(pkgName) || ...
       contains(pkgName, '/')
        error('mip:install:invalidName', ...
              ['The package name for a URL install must be a bare name ' ...
               '(not a URL, path, or FQN). Got: %s'], pkgName);
    end

    parsed = mip.parse.parse_package_arg(pkgName);  % validates name chars
    pkgName = parsed.name;

    % The name defines the canonical install directory and FQN, so
    % require canonical form (lowercase, no leading/trailing separators).
    if ~mip.name.is_valid_canonical(pkgName)
        error('mip:install:invalidName', ...
              ['"%s" is not a valid canonical package name. Canonical names ' ...
               'must consist of lowercase letters, digits, hyphens, and ' ...
               'underscores, and must start and end with a letter or digit.'], ...
              pkgName);
    end

    % If the URL is a File Exchange landing page, resolve it to the
    % underlying .zip download URL. The resolved URL (with query string
    % stripped) is what gets baked into the generated mip.yaml.
    isFex = mip.install.is_fex_url(zipUrl);
    if isFex
        fprintf('Resolving File Exchange URL %s...\n', zipUrl);
        zipUrl = resolveFileExchangeUrl(zipUrl);
        fprintf('Resolved to %s\n', zipUrl);
    end

    if ~mip.install.is_zip_url(zipUrl)
        error('mip:install:urlMustBeZip', ...
              ['A URL install must point to a .zip archive or a File ' ...
               'Exchange page. Got: %s'], zipUrl);
    end

    tempDir = tempname;
    mkdir(tempDir);
    cleanupTemp = onCleanup(@() rmTempDir(tempDir));

    fprintf('Downloading %s...\n', zipUrl);
    zipPath = fullfile(tempDir, 'package.zip');
    try
        websave(zipPath, zipUrl, weboptions('Timeout', 300));
    catch ME
        error('mip:install:zipDownloadFailed', ...
              'Failed to download %s: %s', zipUrl, ME.message);
    end

    extractRoot = fullfile(tempDir, 'extracted');
    mkdir(extractRoot);
    fprintf('Extracting...\n');
    try
        unzip(zipPath, extractRoot);
    catch ME
        error('mip:install:zipExtractFailed', ...
              'Failed to extract %s: %s', zipUrl, ME.message);
    end

    % If the zip extracted to a single top-level directory (e.g. GitHub
    % archive zips produce a `<repo>-<branch>/` wrapper), descend into
    % it. Otherwise use the extraction root directly.
    sourceDir = unwrapSingleSubdir(extractRoot);

    if ~isfile(fullfile(sourceDir, 'mip.yaml'))
        fprintf('No mip.yaml found in archive; auto-generating...\n');
        mip.init(sourceDir, '--name', pkgName, '--repository', zipUrl);
        fprintf('\n');
    end

    if isFex
        sourceType = 'fex';
    else
        sourceType = 'web';
    end
    mip.install.from_local(sourceDir, false, noCompile, sourceType);

    % Clear source_path in the installed mip.json. `from_local` records
    % the extracted source dir, but that temp dir is deleted when this
    % function returns, so the stored path would be stale. An empty
    % source_path signals "no source available to reinstall from";
    % `mip update` skips such packages.
    clearSourcePath(pkgName, sourceType);
end

function name = promptForName(zipUrl)
% Ask the user for the package name, offering a default derived from
% the URL. Honors MIP_CONFIRM as a non-interactive override (matching
% install.m's confirmAutoInit): y/yes accepts the derived default, any
% other non-empty value declines.
    defaultName = mip.install.default_name_from_url(zipUrl);
    confirm = getenv('MIP_CONFIRM');
    if ~isempty(confirm)
        if strcmpi(confirm, 'y') || strcmpi(confirm, 'yes')
            name = defaultName;
        else
            name = '';
        end
    elseif isempty(defaultName)
        name = strtrim(input('Package name: ', 's'));
    else
        name = strtrim(input(sprintf('Package name [%s]: ', defaultName), 's'));
        if isempty(name)
            name = defaultName;
        end
    end
    if isempty(name)
        error('mip:install:noName', ...
              ['A package name is required to install from a URL. ' ...
               'Pass one with --name:\n  mip install %s --name <name>'], ...
              zipUrl);
    end
end

function clearSourcePath(pkgName, sourceType)
    mipJsonPath = fullfile(mip.paths.get_package_dir([sourceType '/' pkgName]), 'mip.json');
    if ~isfile(mipJsonPath)
        return
    end
    mipData = jsondecode(fileread(mipJsonPath));
    mipData.source_path = '';
    fid = fopen(mipJsonPath, 'w');
    if fid == -1
        error('mip:fileError', 'Could not write to mip.json at %s', mipJsonPath);
    end
    cleaner = onCleanup(@() fclose(fid));
    fwrite(fid, jsonencode(mipData));
end

function zipUrl = resolveFileExchangeUrl(fexUrl)
% Resolve a File Exchange landing URL to the underlying .zip download URL.
% Appends ?download=true (or &download=true if a query string is already
% present), issues a HEAD request, follows the 302 redirect to the UUID-
% based mlc-downloads URL, and strips the resulting URL's query string.
%
% A non-default User-Agent is required: the MathWorks Akamai layer
% returns 403 to MATLAB's default UA, but accepts curl-style UAs.

    if contains(fexUrl, '?')
        landingUrl = [fexUrl '&download=true'];
    else
        landingUrl = [fexUrl '?download=true'];
    end

    try
        uri = matlab.net.URI(landingUrl);
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
              'File Exchange URL %s returned HTTP %d.', fexUrl, finalStatus);
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

function dir2 = unwrapSingleSubdir(d)
% If d contains exactly one entry and it is a directory, return that
% subdirectory. Otherwise return d unchanged.
    entries = dir(d);
    entries = entries(~ismember({entries.name}, {'.', '..'}));
    if isscalar(entries) && entries(1).isdir
        dir2 = fullfile(d, entries(1).name);
    else
        dir2 = d;
    end
end

function rmTempDir(d)
    if exist(d, 'dir')
        rmdir(d, 's');
    end
end

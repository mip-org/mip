function install(varargin)
%INSTALL   Install one or more mip packages.
%
% Usage:
%   mip install <package>
%   mip install <package1> <package2> ...
%   mip install --channel <owner>/<channel> <package>
%   mip install --channel <owner> <package>                        - Shorthand for --channel <owner>/<owner>
%   mip install <owner>/<channel>/<package>
%   mip install <owner>/<package>                                  - Shorthand for <owner>/<owner>/<package>
%   mip install /path/to/package.mhl                               - Install under mhl/<name>
%   mip install https://example.com/package.mhl                    - Install under mhl/<name>
%   mip install --channel <owner>/<channel> /path/to/package.mhl   - Install under gh/<owner>/<channel>/<name>
%   mip install /path/to/local/package                             - Install from local directory
%   mip install . --editable                                       - Editable install (like pip -e)
%   mip install -e /path/to/package                                - Editable install (short form)
%   mip install -e . --no-compile                                  - Editable install, skip compilation
%   mip install mypkg --url https://example.com/pkg.zip            - Install from a remote .zip URL
%
% Options:
%   --channel <name>    Install from a specific channel (default: mip-org/core)
%                       Format: '<owner>/<channel>' (e.g. 'mip-org/core'). A bare
%                       single name '<owner>' is shorthand for '<owner>/<owner>'
%                       — the user's personal channel repo at
%                       github.com/<owner>/mip-<owner>.
%   --editable, -e      Install in editable mode (local packages only)
%   --no-compile        Skip compilation (editable installs only)
%   --url <zip-url>     Install from a remote .zip archive. The positional
%                       argument is used as the package name. At most one
%                       --url per call; incompatible with --editable.
%                       File Exchange landing URLs (https://www.mathworks
%                       .com/matlabcentral/fileexchange/...) are also
%                       accepted and auto-resolved to their .zip download.
%
% Local packages:
%   To install a local directory, the path must start with '~', '.', '/',
%   or a Windows drive letter (e.g. 'C:\path\mypkg', 'C:/path/mypkg').
%   The directory must contain a mip.yaml file. In editable mode, changes
%   to the source directory are reflected immediately without reinstalling.
%   '@' in local paths is treated as a literal character, not a version
%   separator (e.g. './@MyClass', './pkg@dev' are valid local paths).
%
%   Bare names like 'chebfun' are always resolved against channels, even
%   if a directory of the same name exists in the current folder. Use
%   './chebfun' to force a local install.
%
% Packages can be specified by bare name or fully qualified name
% (<owner>/<channel>/<package>). Fully qualified names override the --channel
% flag.

    if nargin < 1
        error('mip:install:noPackage', 'At least one package name is required for install command.');
    end

    % Reclaim any package dirs left in the trash by an earlier removal that
    % could only move them aside (a binary was still loaded at the time).
    mip.paths.purge_trash();

    % Check for --editable / -e, --no-compile, and --url flags
    editable = false;
    noCompile = false;
    zipUrl = '';
    urlSeen = false;
    filteredArgs = {};
    i = 1;
    while i <= length(varargin)
        arg = varargin{i};
        if ischar(arg) && (strcmp(arg, '--editable') || strcmp(arg, '-e'))
            editable = true;
            i = i + 1;
        elseif ischar(arg) && strcmp(arg, '--no-compile')
            noCompile = true;
            i = i + 1;
        elseif ischar(arg) && strcmp(arg, '--url')
            if urlSeen
                error('mip:install:multipleUrls', ...
                      '--url may be specified at most once per install call.');
            end
            if i + 1 > length(varargin)
                error('mip:install:missingUrlValue', '--url requires a value.');
            end
            zipUrl = varargin{i + 1};
            urlSeen = true;
            i = i + 2;
        else
            filteredArgs{end+1} = arg; %#ok<AGROW>
            i = i + 1;
        end
    end

    if noCompile && ~editable
        error('mip:install:noCompileRequiresEditable', ...
              '--no-compile can only be used with --editable local installs.');
    end

    [channel, args] = mip.parse.parse_channel_flag(filteredArgs);

    if urlSeen
        installFromUrlFlag(args, zipUrl, editable, noCompile);
        return;
    end

    if isempty(args)
        error('mip:install:noPackage', 'At least one package name is required for install command.');
    end

    % Categorize each argument by how it should be installed:
    %   - mhl source   (.mhl file or http(s) URL)
    %   - local path   (starts with ~, ., /, or a Windows drive letter)
    %   - repo package (bare name or <owner>/<channel>/<package> FQN)
    mhlSources = {};
    localPaths = {};
    repoPackages = {};
    for i = 1:length(args)
        pkg = char(args{i});
        if endsWith(pkg, '.mhl') || startsWith(pkg, 'http://') || startsWith(pkg, 'https://')
            if isFileExchangeUrl(pkg)
                error('mip:install:fexRequiresName', ...
                      ['To install a package from the File Exchange, you must specify a package name using the syntax\n' ...
                       '   mip install <name> --url <url>']);
            end
            mhlSources{end+1} = pkg; %#ok<AGROW>
        elseif isLocalPathArg(pkg)
            localPaths{end+1} = pkg; %#ok<AGROW>
        else
            try
                parsed = mip.parse.parse_package_arg(pkg);
            catch
                error('mip:install:invalidPackageSpec', ...
                      ['Invalid package specifier "%s".\n' ...
                       'Use "<package>" for a bare name or "<owner>/<channel>/<package>" for a fully qualified name.\n' ...
                       'To install a local package, prefix the path with "./":\n' ...
                       '  mip install ./%s'], pkg, pkg);
            end
            if parsed.is_fqn && ~strcmp(parsed.type, 'gh')
                error('mip:install:invalidPackageSpec', ...
                      ['Invalid package specifier "%s".\n' ...
                       'Only GitHub channel packages can be installed from a repository.\n' ...
                       'To install a local package, prefix the path with "./":\n' ...
                       '  mip install ./%s'], pkg, pkg);
            end
            repoPackages{end+1} = pkg; %#ok<AGROW>
        end
    end

    if editable && isempty(localPaths)
        error('mip:install:editableRequiresLocal', ...
              '--editable can only be used with local directory packages.');
    end

    % Process local directory installs first
    for i = 1:length(localPaths)
        localPath = localPaths{i};
        if ~isfolder(localPath)
            error('mip:install:notADirectory', ...
                  '"%s" is not a directory.', localPath);
        end
        if ~isfile(fullfile(localPath, 'mip.yaml'))
            if confirmAutoInit(localPath)
                mip.init(localPath);
                fprintf('\n');
            else
                error('mip:install:abortedNoMipYaml', ...
                      ['Directory "%s" does not contain a mip.yaml file ' ...
                       'and the user declined to auto-generate one. ' ...
                       'Install aborted.'], localPath);
            end
        end
        mip.build.install_local(localPath, editable, noCompile, 'local');
    end

    % If only local installs were requested, we're done
    if isempty(repoPackages) && isempty(mhlSources)
        return;
    end

    packagesDir = mip.paths.get_packages_dir();
    if ~exist(packagesDir, 'dir')
        mkdir(packagesDir);
    end

    % Handle repository packages
    installedFqns = {};

    if ~isempty(repoPackages)
        try
            installedFqns = [installedFqns, mip.ops.install_from_channels(repoPackages, channel)];
        catch ME
            hint = buildLocalDirHint(repoPackages);
            if ~isempty(hint)
                throw(MException(ME.identifier, '%s\n\n%s', ME.message, hint));
            end
            rethrow(ME);
        end
    end

    % Handle .mhl file installations
    for i = 1:length(mhlSources)
        fqn = installFromMhl(mhlSources{i}, packagesDir, channel);
        if ~isempty(fqn)
            installedFqns = [installedFqns, {fqn}]; %#ok<AGROW>
        end
    end

    % Summary
    if isempty(installedFqns) && isempty(mhlSources)
        fprintf('\nAll packages already installed.\n');
    elseif ~isempty(installedFqns)
        fprintf('\nSuccessfully installed %d package(s).\n', length(installedFqns));
        % mip itself is always loaded, so it never gets a "mip load" hint.
        loadable = installedFqns(~strcmp(installedFqns, 'gh/mip-org/core/mip'));
        if ~isempty(loadable)
            fprintf('\nTo use installed packages, run:\n');
            for i = 1:length(loadable)
                fprintf('  mip load %s\n', mip.resolve.get_shortest_name(loadable{i}));
            end
        end
    end
end

function installedFqn = installFromMhl(mhlSource, ~, channel)
% Install a package from a local .mhl file or URL.
%
% When no --channel is given, the package lands under the 'mhl/' source
% type (e.g. 'mhl/chebfun'), so a .mhl from an arbitrary path or URL
% cannot masquerade as a member of the default core channel. Passing
% --channel <owner>/<channel> opts in to gh-channel placement.

    installedFqn = '';
    tempDir = tempname;
    mkdir(tempDir);
    cleanupTemp = onCleanup(@() rmTempDir(tempDir));

    useGhChannel = ~isempty(channel);
    if useGhChannel
        [channelOwner, channelName] = mip.parse.parse_channel_spec(channel);
    end

    try
        mhlPath = mip.channel.download_mhl(mhlSource, tempDir);
        extractDir = fullfile(tempDir, 'extracted');
        mip.channel.extract_mhl(mhlPath, extractDir);

        pkgInfo = mip.config.read_package_json(extractDir);
        packageName = pkgInfo.name;
        if useGhChannel
            fqn = mip.parse.make_fqn(channelOwner, channelName, packageName);
        else
            fqn = mip.parse.make_mhl_fqn(packageName);
        end

        existingName = mip.resolve.installed_dir(fqn);
        if ~isempty(existingName) && ~strcmp(existingName, packageName)
            if useGhChannel
                existingFqn = mip.parse.make_fqn(channelOwner, channelName, existingName);
            else
                existingFqn = mip.parse.make_mhl_fqn(existingName);
            end
            error('mip:install:equivalentAlreadyInstalled', ...
                  ['Cannot install "%s": an equivalent package "%s" is already installed. ' ...
                   'Package names are equivalent when they match after lowercasing and ' ...
                   'treating "-" and "_" as the same character. Uninstall "%s" first.'], ...
                  mip.parse.display_fqn(fqn), mip.parse.display_fqn(existingFqn), ...
                  mip.parse.display_fqn(existingFqn));
        end

        pkgDir = mip.paths.get_package_dir(fqn);
        if exist(pkgDir, 'dir')
            fprintf('Package "%s" is already installed\n', mip.parse.display_fqn(fqn));
            mip.state.add_directly_installed(fqn);
            return
        end

        if ~isempty(pkgInfo.dependencies)
            fprintf('\nPackage "%s" has dependencies: %s\n', ...
                    mip.parse.display_fqn(fqn), strjoin(pkgInfo.dependencies, ', '));
            fprintf('Installing dependencies from remote repository...\n');
            mip.ops.install_from_channels(pkgInfo.dependencies, channel, false);
        end

        fprintf('\nInstalling "%s"...\n', mip.parse.display_fqn(fqn));
        parentDir = fileparts(pkgDir);
        if ~exist(parentDir, 'dir')
            mkdir(parentDir);
        end
        movefile(extractDir, pkgDir);
        fprintf('Successfully installed "%s"\n', mip.parse.display_fqn(fqn));
        mip.state.add_directly_installed(fqn);
        installedFqn = fqn;

    catch ME
        fprintf('\nInstall failed; rolling back any orphaned dependencies...\n');
        try
            mip.state.prune_unused_packages();
        catch pruneErr
            warning('mip:rollbackFailed', ...
                    'Rollback prune failed: %s', pruneErr.message);
        end
        rethrow(ME);
    end
end

function rmTempDir(d)
    if exist(d, 'dir')
        rmdir(d, 's');
    end
end

function tf = confirmAutoInit(localPath)
% Ask the user whether to auto-generate a mip.yaml in localPath.
% Honors MIP_CONFIRM as a non-interactive override (matching uninstall.m).
% Returns true on "y"/"yes", false otherwise.
    fprintf('\nDirectory "%s" does not contain a mip.yaml file.\n', localPath);
    fprintf('mip can auto-generate one for you (equivalent to running `mip init`).\n');
    confirm = getenv('MIP_CONFIRM');
    if isempty(confirm)
        confirm = input('Auto-generate mip.yaml? (y/n): ', 's');
    end
    tf = strcmpi(confirm, 'y') || strcmpi(confirm, 'yes');
end

function installFromUrlFlag(args, zipUrl, editable, noCompile)
% Handle `mip install <name> --url <zipUrl>`.
%
% Validation: exactly one positional arg, which must be a bare name
% (not an FQN, not a path, not itself a URL). The URL must point at
% a .zip (path component, ignoring query/fragment, ends in .zip).
% --editable is rejected since the source directory is temporary.
%
% Then: download the zip, extract, unwrap a single top-level subdir
% if present, auto-generate a mip.yaml if missing (with the URL in
% the repository field), and run a non-editable local install.

    if editable
        error('mip:install:editableRequiresLocal', ...
              '--editable cannot be used with --url installs.');
    end

    if isempty(args)
        error('mip:install:urlRequiresName', ...
              ['--url requires a positional package name.\n' ...
               'Example: mip install mypkg --url %s'], zipUrl);
    end
    if length(args) > 1
        error('mip:install:urlTakesSingleName', ...
              '--url takes exactly one positional package name; got %d.', ...
              length(args));
    end

    pkgName = char(args{1});
    if startsWith(pkgName, 'http://') || startsWith(pkgName, 'https://') || ...
       endsWith(pkgName, '.mhl') || isLocalPathArg(pkgName) || ...
       contains(pkgName, '/')
        error('mip:install:urlTakesSingleName', ...
              ['With --url, the positional argument must be a bare package ' ...
               'name (not a URL, path, or FQN). Got: %s'], pkgName);
    end

    parsed = mip.parse.parse_package_arg(pkgName);  % validates name chars
    pkgName = parsed.name;

    % With --url, the positional arg defines the canonical name that gets
    % used as the install directory and FQN, so require canonical form
    % (lowercase, no leading/trailing separators).
    if ~mip.name.is_valid_canonical(pkgName)
        error('mip:install:invalidName', ...
              ['"%s" is not a valid canonical package name. Canonical names ' ...
               'must consist of lowercase letters, digits, hyphens, and ' ...
               'underscores, and must start and end with a letter or digit.'], ...
              pkgName);
    end

    % Require HTTPS. A plain http:// fetch lets a network attacker swap
    % the archive contents, and the unzipped tree is added to the path
    % on load — i.e. persistent code execution.
    if startsWith(zipUrl, 'http://')
        error('mip:install:requireHttps', ...
              '--url must use https://, not http://. Got: %s', zipUrl);
    end

    % If the URL is a File Exchange landing page, resolve it to the
    % underlying .zip download URL. The resolved URL (with query string
    % stripped) is what gets baked into the generated mip.yaml.
    isFex = isFileExchangeUrl(zipUrl);
    if isFex
        fprintf('Resolving File Exchange URL %s...\n', zipUrl);
        zipUrl = resolveFileExchangeUrl(zipUrl);
        fprintf('Resolved to %s\n', zipUrl);
    end

    if ~isZipUrl(zipUrl)
        error('mip:install:urlMustBeZip', ...
              ['--url value must point to a .zip archive or a File Exchange ' ...
               'page. Got: %s'], zipUrl);
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
    mip.build.install_local(sourceDir, false, noCompile, sourceType);

    % Clear source_path in the installed mip.json. `install_local` records
    % the extracted source dir, but that temp dir is deleted when this
    % function returns, so the stored path would be stale. An empty
    % source_path signals "no source available to reinstall from";
    % `mip update` skips such packages.
    clearSourcePath(pkgName, sourceType);
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

function tf = isFileExchangeUrl(url)
% A MathWorks File Exchange landing page looks like
%   https://www.mathworks.com/matlabcentral/fileexchange/<id>[-<slug>]
% (with optional query string). Plain http:// is rejected — see the
% requireHttps check in installFromUrlFlag.
    if ~ischar(url) && ~isstring(url)
        tf = false; return;
    end
    url = char(url);
    tf = startsWith(url, 'https://www.mathworks.com/matlabcentral/fileexchange/');
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

function tf = isZipUrl(url)
% Return true if url is an https:// URL whose path component ends in .zip
% (case-insensitive). The path component is everything before the first
% '?' (query) or '#' (fragment). Plain http:// is rejected — see the
% requireHttps check in installFromUrlFlag.
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

function tf = isLocalPathArg(pkg)
% Return true if pkg should be treated as a local directory path.
    if isempty(pkg)
        tf = false;
        return
    end
    tf = startsWith(pkg, '~') || startsWith(pkg, '.') || startsWith(pkg, '/') || ...
         (length(pkg) >= 3 && isstrprop(pkg(1), 'alpha') && pkg(2) == ':' && ...
          (pkg(3) == '\' || pkg(3) == '/'));
end

function hint = buildLocalDirHint(repoPackages)
% If any of the repo-style args also exists as a relative directory in
% the current folder, build a hint suggesting the './' form.
% Also checks the base name after stripping any @version suffix, since
% local paths treat '@' as a literal character (not a version separator).
    lines = {};
    for i = 1:length(repoPackages)
        dirName = matchLocalDir(repoPackages{i});
        if ~isempty(dirName)
            lines{end+1} = sprintf( ... %#ok<AGROW>
                ['Note: a local directory "%s" exists in the current folder.\n' ...
                 'To install it as a local package instead, run:\n' ...
                 '  mip install ./%s'], dirName, dirName);
        end
    end
    hint = strjoin(lines, sprintf('\n\n'));
end

function dirName = matchLocalDir(pkg)
% Check if pkg matches a local directory, either as-is or after stripping
% a trailing @version suffix.
    dirName = '';
    if isfolder(pkg)
        dirName = pkg;
    else
        atIdx = strfind(pkg, '@');
        if ~isempty(atIdx)
            baseName = pkg(1:atIdx(end)-1);
            if isfolder(baseName)
                dirName = baseName;
            end
        end
    end
end

function v = read_version(sourceDir)
%READ_VERSION   Resolve the version of the copy of mip rooted at sourceDir.
%
% sourceDir is a mip source root: the directory containing the +mip
% package and mip.yaml. For an installed mip the on-disk layout is
%
%   <root>/packages/gh/<owner>/<channel>/mip/   <- mip.json (install metadata)
%     mip/                                      <- sourceDir
%
% so the version resolved at install/build time — which may be a branch
% name like "main" supplied by the channel build, and is not present in
% the source's mip.yaml — is recorded in the mip.json one level above
% sourceDir. When running from a plain source checkout there is no such
% mip.json; fall back to the checkout's mip.yaml. A blank version
% (mip.yaml's version field is optional) is reported as 'unspecified',
% matching how installed packages record it.

v = '';

% Installed layout: mip.json in the parent directory. Only trust it when
% its "name" matches the sourceDir directory name — the installed layout
% names the source subdir after the package, whereas a source checkout
% may sit inside an unrelated directory that happens to contain a
% mip.json.
installDir = fileparts(sourceDir);
[~, sourceDirName] = fileparts(sourceDir);
if ~isempty(installDir) && exist(fullfile(installDir, 'mip.json'), 'file')
    pkgInfo = mip.config.read_package_json(installDir);
    if strcmp(pkgInfo.name, sourceDirName)
        v = pkgInfo.version;
    end
end

% Source checkout: read mip.yaml.
if isempty(v)
    mipYamlPath = fullfile(sourceDir, 'mip.yaml');
    if ~exist(mipYamlPath, 'file')
        error('mip:version:noMetadata', ...
              ['Could not determine the mip version: no mip.json above ' ...
               '%s and no mip.yaml in it. Is mip installed correctly?'], ...
              sourceDir);
    end
    mipConfig = mip.config.read_mip_yaml(sourceDir);
    v = mipConfig.version;
end

if isnumeric(v)
    v = num2str(v);
end
if isempty(v)
    v = 'unspecified';
end

end

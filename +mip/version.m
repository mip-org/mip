function v = version()
%VERSION   Return the mip package manager version string.
%
% Usage:
%   mip version
%
% Returns the version string for mip.

% Reads mip.json (the metadata file written at install/build time, which
% records the resolved version) when present. Falls back to mip.yaml when
% running mip directly from a source checkout, which has no mip.json.

thisDir = fileparts(mfilename('fullpath'));  % +mip directory
pkgRoot = fileparts(thisDir);  % package root (contains mip.json or mip.yaml)

mipJsonPath = fullfile(pkgRoot, 'mip.json');
if exist(mipJsonPath, 'file')
    pkgInfo = mip.config.read_package_json(pkgRoot);
    v = pkgInfo.version;
else
    mipYamlPath = fullfile(pkgRoot, 'mip.yaml');
    if ~exist(mipYamlPath, 'file')
        error('mip:version:noMetadata', ...
              'Neither mip.json nor mip.yaml found at %s. Is mip installed correctly?', pkgRoot);
    end
    mipConfig = mip.config.read_mip_yaml(pkgRoot);
    v = mipConfig.version;
end

if isnumeric(v)
    v = num2str(v);
end

end

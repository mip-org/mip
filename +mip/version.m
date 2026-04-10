function v = version()
%VERSION   Return the mip package manager version string.

thisDir = fileparts(mfilename('fullpath'));  % +mip directory
pkgRoot = fileparts(thisDir);  % package root (contains mip.yaml)
mipYamlPath = fullfile(pkgRoot, 'mip.yaml');
if ~exist(mipYamlPath, 'file')
    error('mip:version:noMipYaml', ...
          'mip.yaml not found at %s. Is mip installed correctly?', pkgRoot);
end
mipConfig = mip.config.read_mip_yaml(pkgRoot);
v = mipConfig.version;
if isnumeric(v)
    v = num2str(v);
end

end

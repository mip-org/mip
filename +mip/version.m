function v = version()
%VERSION   Return the mip package manager version string.

thisDir = fileparts(mfilename('fullpath'));  % +mip directory
pkgRoot = fileparts(thisDir);  % package root
mipJsonPath = fullfile(pkgRoot, 'mip.json');
if exist(mipJsonPath, 'file')
    pkgInfo = mip.utils.read_package_json(pkgRoot);
    v = pkgInfo.version;
    if isnumeric(v)
        v = num2str(v);
    end
else
    v = 'dev';
end

end

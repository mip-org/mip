function names = list_mex(fqn)
%LIST_MEX   Base names of the compiled MEX an installed package ships.
%
% Usage:
%   names = mip.build.list_mex(fqn)
%
% Returns a cell array of the unique base names (no extension) of MEX
% binaries matching the current architecture's extension (mexext) found in
% the package's own source directory -- the MEX it ships for this machine.
% Empty when the package ships none (e.g. a pure-MATLAB build).
%
% This is the shared "what MEX does this package ship" primitive:
% mip.build.has_mex is ~isempty(mip.build.list_mex(fqn)), and a channel test
% runner can diff this list against what `inmem` shows was loaded to enforce
% that the test exercised every shipped MEX. Only the package's own source
% dir is scanned -- MEX from dependencies are not counted.
%
% fqn must be a fully-qualified name.

r = mip.parse.parse_package_arg(fqn);
if ~r.is_fqn
    error('mip:invalidFqn', ...
          'mip.build.list_mex requires a fully qualified name; got "%s".', fqn);
end

pkgDir  = mip.paths.get_package_dir(fqn);
pkgInfo = mip.config.read_package_json(pkgDir);
srcDir  = mip.paths.get_source_dir(pkgDir, pkgInfo);

info  = dir(fullfile(srcDir, '**', ['*.' mexext]));
names = unique(erase({info.name}, ['.' mexext]));

end

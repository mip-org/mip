function srcDir = get_source_dir(pkgDir, pkgInfo)
%GET_SOURCE_DIR   Determine the source directory for an installed package.
%
% For editable installs, returns the original source_path (changes are
% reflected immediately). For all other installs, returns pkgDir/<name>/
% (the standard installed layout).
%
% Non-editable local installs also have source_path set (for update
% tracking), but their working directory is the installed copy.
%
% Args:
%   pkgDir  - Installed package directory
%   pkgInfo - Struct from read_package_json
%
% Returns:
%   srcDir - Path to the source directory

isEditable = isfield(pkgInfo, 'editable') && pkgInfo.editable;

if isEditable && isfield(pkgInfo, 'source_path') && ~isempty(pkgInfo.source_path) ...
        && isfolder(pkgInfo.source_path)
    srcDir = pkgInfo.source_path;
else
    srcDir = fullfile(pkgDir, pkgInfo.name);
end

end

function assert_safe_relative(rel, context)
%ASSERT_SAFE_RELATIVE   Error unless rel is a safe in-tree relative path.
%
% Validates that a path string, intended to be resolved relative to some
% base directory, cannot escape that base. Rejects:
%   - non-string input
%   - null bytes
%   - absolute paths (leading "/" or "\")
%   - Windows drive letters (e.g. "C:\foo")
%   - ".." components that resolve outside the base
%
% Benign in-tree ".." like "foo/../bar" is allowed.
%
% Mirrors the entry-name check in mip.channel.assert_mhl_safe so that
% paths declared in mip.json (paths, extra_paths) and paths supplied via
% --addpath / --rmpath cannot point outside the package source directory.
%
% Args:
%   rel     - The relative path to validate.
%   context - Short description used in error messages, e.g.
%             'mip.json paths[2]' or '--addpath'.
%
% Errors:
%   mip:unsafePath - rel would escape its base directory.

if ~(ischar(rel) || (isstring(rel) && isscalar(rel)))
    error('mip:unsafePath', '%s: path must be a string', context);
end
rel = char(rel);
if any(rel == 0)
    error('mip:unsafePath', '%s: path contains a null byte', context);
end
normalized = strrep(rel, '\', '/');
if startsWith(normalized, '/')
    error('mip:unsafePath', ...
          '%s: must be a relative path, got absolute: %s', context, rel);
end
if ~isempty(regexp(normalized, '^[A-Za-z]:', 'once'))
    error('mip:unsafePath', ...
          '%s: must be a relative path, got drive letter: %s', context, rel);
end
parts = strsplit(normalized, '/');
depth = 0;
for k = 1:numel(parts)
    p = parts{k};
    if isempty(p) || strcmp(p, '.')
        continue
    end
    if strcmp(p, '..')
        if depth == 0
            error('mip:unsafePath', ...
                  '%s: path escapes the package source directory: %s', ...
                  context, rel);
        end
        depth = depth - 1;
    else
        depth = depth + 1;
    end
end
end

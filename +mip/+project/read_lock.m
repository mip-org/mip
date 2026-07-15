function lock = read_lock(lockPath)
%READ_LOCK   Read and normalize a mip.lock file.
%
% Usage:
%   lock = mip.project.read_lock(lockPath)
%
% Returns the lock struct in the shape mip.project.write_lock accepts:
% top-level fields lock_version, mip_version, spec_sha256, and packages
% as a row cell array of entry structs with cellstr dependencies/groups
% and logical direct/base flags.
%
% Errors mip:project:lockNotFound when the file does not exist and
% mip:project:lockInvalid when it cannot be parsed or has an unsupported
% format version.

if ~isfile(lockPath)
    error('mip:project:lockNotFound', ...
          ['No mip.lock at %s.\n' ...
           'Create one with:\n  mip project lock'], lockPath);
end

try
    raw = jsondecode(fileread(lockPath));
catch ME
    error('mip:project:lockInvalid', ...
          'Could not parse %s: %s', lockPath, ME.message);
end

if ~isstruct(raw) || ~isfield(raw, 'lock_version')
    error('mip:project:lockInvalid', ...
          '%s is not a mip lock file (missing lock_version).', lockPath);
end
if ~isequal(raw.lock_version, 1)
    error('mip:project:lockInvalid', ...
          ['%s has lock format version %s, which this mip does not ' ...
           'support. Update mip or re-run "mip project lock".'], ...
          lockPath, num2str(raw.lock_version));
end

lock = struct();
lock.lock_version = 1;
lock.mip_version = char_or(raw, 'mip_version', '');
lock.spec_sha256 = char_or(raw, 'spec_sha256', '');

% jsondecode yields a struct array when every entry has the same fields
% (the shape write_lock produces), a cell array otherwise, and [] for an
% empty lock. Normalize to a row cell array of entry structs.
entries = {};
if isfield(raw, 'packages') && ~isempty(raw.packages)
    if isstruct(raw.packages)
        entries = num2cell(reshape(raw.packages, 1, []));
    elseif iscell(raw.packages)
        entries = reshape(raw.packages, 1, []);
    else
        error('mip:project:lockInvalid', ...
              '%s has an invalid "packages" field.', lockPath);
    end
end

lock.packages = cell(1, numel(entries));
for i = 1:numel(entries)
    e = entries{i};
    if ~isstruct(e) || ~isfield(e, 'fqn')
        error('mip:project:lockInvalid', ...
              '%s: package entry %d is invalid.', lockPath, i);
    end
    p = struct();
    p.fqn = char_or(e, 'fqn', '');
    p.name = char_or(e, 'name', '');
    p.version = char_or(e, 'version', '');
    p.architecture = char_or(e, 'architecture', '');
    p.mhl_url = char_or(e, 'mhl_url', '');
    p.mhl_sha256 = char_or(e, 'mhl_sha256', '');
    p.commit_hash = char_or(e, 'commit_hash', '');
    p.source_hash = char_or(e, 'source_hash', '');
    p.dependencies = cellstr_or(e, 'dependencies');
    p.direct = logical_or(e, 'direct', false);
    p.base = logical_or(e, 'base', false);
    p.groups = cellstr_or(e, 'groups');
    lock.packages{i} = p;
end

end

function v = char_or(s, field, default)
    if isfield(s, field) && ~isempty(s.(field))
        v = char(s.(field));
    else
        v = default;
    end
end

function v = cellstr_or(s, field)
    if ~isfield(s, field) || isempty(s.(field))
        v = {};
        return
    end
    v = s.(field);
    if ischar(v)
        v = {v};
    elseif isstring(v)
        v = cellstr(v);
    end
    v = reshape(v, 1, []);
    for i = 1:numel(v)
        v{i} = char(v{i});
    end
end

function v = logical_or(s, field, default)
    if isfield(s, field) && ~isempty(s.(field))
        v = logical(s.(field));
    else
        v = default;
    end
end

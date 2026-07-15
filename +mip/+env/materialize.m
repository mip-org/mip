function created = materialize(envPath)
%MATERIALIZE   Ensure a mip environment exists at a path.
%
% Usage:
%   created = mip.env.materialize(envPath)
%
% Creates the environment when it does not exist: an empty packages/
% subtree and the mip-env.json marker (format version, creation time,
% creating mip version). An existing environment is left untouched.
% Prints nothing; callers own the messaging.
%
% Creation is strict, as in "mip env create": an existing non-empty
% directory that is not an environment is an error - mip will not adopt
% arbitrary directories.
%
% Returns:
%   created - true when the environment was newly created

if mip.env.is_env(envPath)
    created = false;
    return
end

if isfolder(envPath) && ~dir_is_empty(envPath)
    error('mip:env:directoryNotEmpty', ...
          ['Directory "%s" already exists and is not empty. ' ...
           'mip will not adopt an arbitrary directory as an environment.'], ...
          envPath);
end

packagesDir = fullfile(envPath, 'packages');
if ~isfolder(packagesDir)
    mkdir(packagesDir);
end

marker = struct( ...
    'format_version', 1, ...
    'created', char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss')), ...
    'mip_version', mip.version());
markerPath = fullfile(envPath, 'mip-env.json');
fid = fopen(markerPath, 'w');
if fid == -1
    error('mip:fileError', 'Could not write to %s', markerPath);
end
fwrite(fid, jsonencode(marker));
fclose(fid);

created = true;

end

function tf = dir_is_empty(d)
    entries = dir(d);
    entries = entries(~ismember({entries.name}, {'.', '..'}));
    tf = isempty(entries);
end

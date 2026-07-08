function lockData = read_lock(projectDir)
%READ_LOCK   Read and normalize mipenv.lock.
%
% Args:
%   projectDir - Project directory (from mip.env.project_dir).
%
% Returns:
%   lockData - Struct with the same shape produced by mip.env.resolve_lock.
%              .packages is always a cell array of entry structs (jsondecode
%              collapses a JSON array of uniform objects into a struct array,
%              so it is converted back to a cell array here).

lockFile = mip.env.lock_path(projectDir);
if ~exist(lockFile, 'file')
    error('mip:env:noLock', ...
          ['No mipenv.lock found in "%s".\n' ...
           'Run "mip env lock" (or "mip env sync") first.'], projectDir);
end

text = fileread(lockFile);
try
    lockData = jsondecode(text);
catch ME
    error('mip:env:lockParseFailed', ...
          'Failed to parse %s: %s', lockFile, ME.message);
end

if ~isfield(lockData, 'packages') || isempty(lockData.packages)
    lockData.packages = {};
elseif isstruct(lockData.packages)
    lockData.packages = num2cell(lockData.packages);
elseif ~iscell(lockData.packages)
    lockData.packages = {lockData.packages};
end

end

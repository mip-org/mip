function resolved = resolve_build_config(mipConfig, buildEntry)
%RESOLVE_BUILD_CONFIG   Merge build-level overrides with top-level defaults.
%
% Top-level keys in mipConfig serve as defaults. Fields in buildEntry
% override them. The 'architectures' key is not included in the result.
%
% Args:
%   mipConfig  - Struct from read_mip_yaml
%   buildEntry - A single build entry struct from the builds array
%
% Returns:
%   resolved - Struct with merged configuration

resolved = struct();

% Top-level defaults
mergeFields = {'addpaths', 'compile_script', 'test_script', 'build_on'};
for i = 1:length(mergeFields)
    key = mergeFields{i};
    if isfield(mipConfig, key)
        resolved.(key) = mipConfig.(key);
    end
end

% Build-level overrides
if ~isempty(buildEntry) && isstruct(buildEntry)
    fields = fieldnames(buildEntry);
    for i = 1:length(fields)
        key = fields{i};
        if strcmp(key, 'architectures')
            continue;
        end
        resolved.(key) = buildEntry.(key);
    end
end

% Ensure addpaths defaults to empty cell
if ~isfield(resolved, 'addpaths')
    resolved.addpaths = {};
end

end

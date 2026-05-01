function [buildEntry, effectiveArch] = match_build(mipConfig, architecture)
%MATCH_BUILD   Find the best matching build entry for an architecture.
%
% Uses a two-pass scan: first checks all builds for an exact architecture
% match, then falls back to the first build that lists 'any'. This ensures
% an exact match is always preferred regardless of declaration order.
%
% Args:
%   mipConfig    - Struct from read_mip_yaml (must have .builds field)
%   architecture - (Optional) Architecture string. Default: mip.build.arch()
%
% Returns:
%   buildEntry    - The matched build struct from the builds array
%   effectiveArch - The effective architecture string ('any' or specific)

if nargin < 2 || isempty(architecture)
    architecture = mip.build.arch();
end

builds = mipConfig.builds;
if isempty(builds)
    error('mip:noBuild', 'No builds defined in mip.yaml');
end

% Normalize to cell array
if ~iscell(builds)
    builds = num2cell(builds);
end

% Pass 1: exact architecture match
effectiveArch = architecture;
buildEntry = findFirstMatchingBuild(builds, effectiveArch);
if ~isempty(buildEntry)
    return
end

% Pass 2: fall back to first 'any' build
effectiveArch = 'any';
buildEntry = findFirstMatchingBuild(builds, effectiveArch);
if ~isempty(buildEntry)
    return
end

error('mip:noMatchingBuild', ...
      'No build in mip.yaml matches architecture "%s"', architecture);

end

function buildEntry = findFirstMatchingBuild(builds, arch)
    buildEntry = [];
    for i = 1:length(builds)
        b = builds{i};
        archs = b.architectures;
        if ~iscell(archs)
            archs = {archs};
        end
        if ismember(arch, archs)
            buildEntry = b;
            return
        end
    end
end

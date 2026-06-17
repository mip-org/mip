function archs = compatible_archs(currentArch)
%COMPATIBLE_ARCHS   Ordered list of architectures the host can install.
%
% Usage:
%   archs = mip.build.compatible_archs()
%   archs = mip.build.compatible_archs(currentArch)
%
% Returns a cell array of architecture tags whose published builds this machine
% can install and run, ordered most-preferred first. Selection code (e.g.
% mip.resolve.select_best_variant) walks the list in order and takes the first
% variant the channel actually publishes. The list always ends with the base
% architecture and 'any'.
%
% For x86-64 hosts (linux_x86_64, windows_x86_64) the highest CPU-supported
% microarchitecture (SIMD) level comes first, then each lower level, then the
% base arch, then 'any'. For example a v3-capable Linux host yields:
%
%   {'linux_x86_64_v3', 'linux_x86_64_v2', 'linux_x86_64', 'any'}
%
% so the AVX2 build wins when published, otherwise the host falls back to a
% lower level and finally the portable baseline. Listing a level the channel
% does not publish (e.g. windows_x86_64_v2) is harmless — it simply never
% matches. For numbl_* hosts, numbl_wasm remains a fallback. Other hosts get
% {currentArch, 'any'}.

if nargin < 1 || isempty(currentArch)
    currentArch = mip.build.arch();
end

archs = {};

% x86-64 microarchitecture levels: prepend each level the CPU supports, highest
% first, down to v2 (v1 is the base arch, appended below).
if strcmp(currentArch, 'linux_x86_64') || strcmp(currentArch, 'windows_x86_64')
    level = mip.build.detect_cpu_level();
    for n = level:-1:2
        archs{end+1} = sprintf('%s_v%d', currentArch, n); %#ok<AGROW>
    end
end

archs{end+1} = currentArch;

% numbl_* hosts can run the portable wasm build as a fallback.
if startsWith(currentArch, 'numbl_') && ~strcmp(currentArch, 'numbl_wasm')
    archs{end+1} = 'numbl_wasm';
end

archs{end+1} = 'any';

end

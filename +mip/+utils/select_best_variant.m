function bestVariant = select_best_variant(variants, currentArch)
%SELECT_BEST_VARIANT   Select the best package variant for an architecture.
%
% Args:
%   variants - Cell array of package info structs (different arch variants)
%   currentArch - Architecture string (e.g., 'linux_x86_64')
%
% Returns:
%   bestVariant - The best matching variant struct, or [] if none compatible
%
% When multiple variants match the same architecture but differ in cpu_level,
% selects the highest cpu_level that does not exceed the host capability.
% Variants with cpu_level are preferred over those without (non-SIMD).

if isempty(variants)
    bestVariant = [];
    return
end

% For numbl_* architectures, numbl_wasm is a valid fallback
canFallbackToWasm = startsWith(currentArch, 'numbl_') && ~strcmp(currentArch, 'numbl_wasm');

% Filter to compatible variants (exact match, numbl_wasm fallback, or 'any')
compatible = {};
for i = 1:length(variants)
    v = variants{i};
    if isfield(v, 'architecture')
        arch = v.architecture;
    else
        continue
    end

    if strcmp(arch, currentArch) || strcmp(arch, 'any') || (canFallbackToWasm && strcmp(arch, 'numbl_wasm'))
        compatible = [compatible, {v}]; %#ok<AGROW>
    end
end

if isempty(compatible)
    bestVariant = [];
    return
end

% Separate into priority tiers: exact match > numbl_wasm > 'any'
exactMatch = {};
wasmFallback = {};
anyMatch = {};
for i = 1:length(compatible)
    a = compatible{i}.architecture;
    if strcmp(a, currentArch)
        exactMatch = [exactMatch, {compatible{i}}]; %#ok<AGROW>
    elseif strcmp(a, 'numbl_wasm')
        wasmFallback = [wasmFallback, {compatible{i}}]; %#ok<AGROW>
    else
        anyMatch = [anyMatch, {compatible{i}}]; %#ok<AGROW>
    end
end

% Pick from the highest-priority non-empty tier
if ~isempty(exactMatch)
    bestVariant = select_best_cpu_variant(exactMatch);
elseif ~isempty(wasmFallback)
    bestVariant = wasmFallback{1};
else
    bestVariant = anyMatch{1};
end

end


function best = select_best_cpu_variant(variants)
%SELECT_BEST_CPU_VARIANT  Among same-architecture variants, pick best cpu_level.
%
%   If any variants have a cpu_level field, detect the host level and pick
%   the highest variant <= host.  If none have cpu_level, return the first.

CPU_LEVELS = {'x86_64_v1', 'x86_64_v2', 'x86_64_v3', 'x86_64_v4'};

% Split into SIMD and non-SIMD variants
simdVariants = {};
nonSimdVariants = {};
for i = 1:length(variants)
    if isfield(variants{i}, 'cpu_level') && ~isempty(variants{i}.cpu_level)
        simdVariants = [simdVariants, {variants{i}}]; %#ok<AGROW>
    else
        nonSimdVariants = [nonSimdVariants, {variants{i}}]; %#ok<AGROW>
    end
end

if isempty(simdVariants)
    best = nonSimdVariants{1};
    return
end

% Detect host CPU level
hostLevel = mip.utils.detect_cpu_level();
if isempty(hostLevel)
    hostLevel = 'x86_64_v1';
end
fprintf('Detected host CPU level: %s\n', hostLevel);
hostRank = find(strcmp(CPU_LEVELS, hostLevel), 1);
if isempty(hostRank)
    hostRank = 1;
end

% Find the best SIMD variant: highest cpu_level <= hostRank
bestRank = 0;
best = [];
for i = 1:length(simdVariants)
    lvl = simdVariants{i}.cpu_level;
    rank = find(strcmp(CPU_LEVELS, lvl), 1);
    if isempty(rank)
        continue
    end
    if rank <= hostRank && rank > bestRank
        bestRank = rank;
        best = simdVariants{i};
    end
end

% Fallback to non-SIMD if no SIMD variant fits
if isempty(best)
    if ~isempty(nonSimdVariants)
        best = nonSimdVariants{1};
        fprintf('No matching SIMD variant; using non-SIMD build\n');
    else
        % Last resort: pick lowest SIMD variant (v1)
        best = simdVariants{1};
        fprintf('No matching SIMD variant; falling back to %s\n', best.cpu_level);
    end
else
    fprintf('Selected SIMD variant: %s\n', best.cpu_level);
end

end

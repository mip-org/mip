function bestVariant = select_best_variant(variants, currentArch)
%SELECT_BEST_VARIANT   Select the best package variant for an architecture.
%
% Args:
%   variants - Cell array of package info structs (different arch variants)
%   currentArch - Architecture string (e.g., 'linux_x86_64')
%
% Returns:
%   bestVariant - The best matching variant struct, or [] if none compatible

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

% Prefer exact match > numbl_wasm fallback > 'any'
for i = 1:length(compatible)
    if strcmp(compatible{i}.architecture, currentArch)
        bestVariant = compatible{i};
        return
    end
end
for i = 1:length(compatible)
    if strcmp(compatible{i}.architecture, 'numbl_wasm')
        bestVariant = compatible{i};
        return
    end
end
bestVariant = compatible{1};

end

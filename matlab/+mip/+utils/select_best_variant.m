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

% Filter to compatible variants (exact match or 'any')
compatible = {};
for i = 1:length(variants)
    v = variants{i};
    if isfield(v, 'architecture')
        arch = v.architecture;
    else
        continue
    end

    if strcmp(arch, currentArch) || strcmp(arch, 'any')
        compatible = [compatible, {v}]; %#ok<AGROW>
    end
end

if isempty(compatible)
    bestVariant = [];
    return
end

% Prefer exact architecture matches over 'any'
for i = 1:length(compatible)
    if strcmp(compatible{i}.architecture, currentArch)
        bestVariant = compatible{i};
        return
    end
end
bestVariant = compatible{1};

end

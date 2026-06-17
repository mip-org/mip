function bestVariant = select_best_variant(variants, archPrefs)
%SELECT_BEST_VARIANT   Select the best package variant for the host.
%
% Args:
%   variants  - Cell array of package info structs (different arch variants).
%   archPrefs - Ordered cell array of acceptable architecture tags, most
%               preferred first (from mip.build.compatible_archs). A single
%               architecture string is also accepted for convenience and is
%               expanded to the historical exact > numbl_wasm > 'any' order.
%
% Returns:
%   bestVariant - The variant whose architecture appears earliest in archPrefs,
%                 or [] if none of the variants matches.

if isempty(variants)
    bestVariant = [];
    return
end

if ~iscell(archPrefs)
    archPrefs = legacy_prefs(archPrefs);
end

% Walk the preference list; the first architecture with a matching variant wins.
bestVariant = [];
for p = 1:numel(archPrefs)
    want = archPrefs{p};
    for i = 1:numel(variants)
        v = variants{i};
        if isfield(v, 'architecture') && strcmp(v.architecture, want)
            bestVariant = v;
            return
        end
    end
end

end


function prefs = legacy_prefs(currentArch)
%LEGACY_PREFS  Expand a single architecture string into a preference list
% matching the historical exact > numbl_wasm > 'any' selection order.
prefs = {currentArch};
if startsWith(currentArch, 'numbl_') && ~strcmp(currentArch, 'numbl_wasm')
    prefs{end+1} = 'numbl_wasm';
end
prefs{end+1} = 'any';
end

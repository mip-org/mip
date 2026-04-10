function direct = is_directly_loaded(package)
%IS_DIRECTLY_LOADED   Check if a package is directly loaded.

MIP_DIRECTLY_LOADED_PACKAGES = mip.state.key_value_get('MIP_DIRECTLY_LOADED_PACKAGES');
direct = ismember(package, MIP_DIRECTLY_LOADED_PACKAGES);

end

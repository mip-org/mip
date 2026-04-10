function loaded = is_loaded(package)
%IS_LOADED   Check if a package is loaded, directly or indirectly.

MIP_LOADED_PACKAGES = mip.state.key_value_get('MIP_LOADED_PACKAGES');
loaded = ismember(package, MIP_LOADED_PACKAGES);

end

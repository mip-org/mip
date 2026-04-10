function sticky = is_sticky(package)
%IS_STICKY   Check if a package is sticky.

MIP_STICKY_PACKAGES = mip.state.key_value_get('MIP_STICKY_PACKAGES');
sticky = ismember(package, MIP_STICKY_PACKAGES);

end

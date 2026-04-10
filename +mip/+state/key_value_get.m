function value = key_value_get(key)
%KEY_VALUE_GET   Read the value for a given key from persistent storage.
%
% The persistent storage used by this function is unaffected by the "clear all"
% command.

value = getappdata(0, key);

if isempty(value)
    value = {};
end

end

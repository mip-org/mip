function key_value_set(key, value)
%KEY_VALUE_SET   Write the value for a given key to persistent storage.
%
% The persistent storage used by this function is unaffected by the "clear all"
% command.

setappdata(0, key, value);

end

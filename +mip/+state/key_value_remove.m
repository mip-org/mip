function key_value_remove(key, value)
%KEY_VALUE_REMOVE   Remove a value from a given key's persistent storage.
%
% The persistent storage used by this function is unaffected by the "clear all"
% command.

values = mip.state.key_value_get(key);
values(ismember(values, value)) = [];
mip.state.key_value_set(key, values);

end

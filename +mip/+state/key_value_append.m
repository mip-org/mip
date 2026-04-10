function key_value_append(key, value)
%KEY_VALUE_APPEND   Append a value to a given key's persistent storage.
%
% The persistent storage used by this function is unaffected by the "clear all"
% command.

values = mip.state.key_value_get(key);
if ~ismember(value, values)
    values{end+1} = value;
end
mip.state.key_value_set(key, values);

end

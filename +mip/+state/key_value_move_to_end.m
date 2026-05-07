function key_value_move_to_end(key, value)
%KEY_VALUE_MOVE_TO_END   Move a value to the end of a key's list.
%
% If the value is not present, it is appended. If it is present, it is
% removed and re-appended so it ends up at the end of the list.

values = mip.state.key_value_get(key);
values(ismember(values, value)) = [];
values{end+1} = value;
mip.state.key_value_set(key, values);

end

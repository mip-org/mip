function channel = normalize_channel_spec(channel)
%NORMALIZE_CHANNEL_SPEC   Validate and expand a channel argument.
%
% Accepts a channel spec in '<owner>/<channel>' form, or a bare '<owner>'
% which is expanded to '<owner>/<owner>' (shorthand for the user's
% personal channel repo).
%
% Args:
%   channel - char or string scalar
%
% Returns:
%   channel - char row vector in '<owner>/<channel>' form
%
% Errors:
%   mip:invalidChannel - empty, wrong type, or wrong format

if isstring(channel)
    channel = char(channel);
end
if ~ischar(channel) || isempty(channel)
    error('mip:invalidChannel', 'Channel must be a non-empty string.');
end
if ~contains(channel, '/')
    channel = [channel '/' channel];
end
parts = strsplit(channel, '/');
if length(parts) ~= 2 || any(cellfun('isempty', parts))
    error('mip:invalidChannel', ...
          'Invalid channel format "%s". Use "<owner>/<channel>".', channel);
end

end

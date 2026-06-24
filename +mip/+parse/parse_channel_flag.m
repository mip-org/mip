function [channel, remainingArgs] = parse_channel_flag(args)
%PARSE_CHANNEL_FLAG   Extract --channel flag from argument list.
%
% Args:
%   args - Cell array of arguments (typically varargin)
%
% Returns:
%   channel       - Channel string in '<owner>/<channel>' form, or '' if not
%                   specified. A bare single name '<owner>' is expanded to
%                   '<owner>/<owner>' as shorthand for a user's personal channel
%                   repo (github.com/<owner>/mip-<owner>). The same personal-
%                   channel shorthand is also accepted for positional FQN
%                   arguments — see mip.parse.parse_package_arg.
%   remainingArgs - Cell array with --channel and its value removed

channel = '';
remainingArgs = {};

i = 1;
while i <= length(args)
    arg = args{i};
    if ischar(arg) || isstring(arg)
        arg = char(arg);
        if strcmp(arg, '--channel')
            if i + 1 > length(args)
                error('mip:missingChannelValue', '--channel requires a channel name argument');
            end
            channel = char(args{i + 1});
            if ~isempty(channel) && ~contains(channel, '/')
                channel = [channel '/' channel];
            end
            i = i + 2;
            continue;
        end
    end
    remainingArgs = [remainingArgs, args(i)]; %#ok<AGROW>
    i = i + 1;
end

end

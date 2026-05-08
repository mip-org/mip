function channel(varargin)
%CHANNEL   Manage channel subscriptions for bare-name install resolution.
%
% Usage:
%   mip channel add <channel>      - Subscribe at highest priority
%   mip channel append <channel>   - Subscribe at lowest priority
%   mip channel remove <channel>   - Unsubscribe from a channel
%   mip channel list               - List channels in priority order
%
% <channel> is in '<owner>/<channel>' form, or a bare '<owner>' which is
% shorthand for '<owner>/<owner>'.
%
% When a bare-name install is invoked without --channel, mip-org/core is
% consulted first, then each subscribed channel in priority order (most
% recently added first). The first channel that publishes the package
% wins. Re-running 'add' on an already-subscribed channel moves it to
% the top of the priority list; re-running 'append' moves it to the
% bottom.
%
% Subscriptions are persisted at <root>/packages/channels.txt.

if isempty(varargin)
    error('mip:noSubcommand', ...
          'channel command requires a subcommand: add, append, remove, list.');
end
sub = lower(char(varargin{1}));
switch sub
    case 'add'
        if length(varargin) < 2
            error('mip:noChannel', ...
                  '"mip channel add" requires a channel argument.');
        end
        if length(varargin) > 2
            error('mip:tooManyArgs', ...
                  '"mip channel add" takes a single channel argument.');
        end
        mip.state.add_channel(varargin{2});

    case 'append'
        if length(varargin) < 2
            error('mip:noChannel', ...
                  '"mip channel append" requires a channel argument.');
        end
        if length(varargin) > 2
            error('mip:tooManyArgs', ...
                  '"mip channel append" takes a single channel argument.');
        end
        mip.state.append_channel(varargin{2});

    case {'remove', 'rm'}
        if length(varargin) < 2
            error('mip:noChannel', ...
                  '"mip channel remove" requires a channel argument.');
        end
        if length(varargin) > 2
            error('mip:tooManyArgs', ...
                  '"mip channel remove" takes a single channel argument.');
        end
        mip.state.remove_channel(varargin{2});

    case 'list'
        if length(varargin) > 1
            error('mip:tooManyArgs', ...
                  '"mip channel list" takes no arguments.');
        end
        % mip-org/core is always listed first. It is the implicit default
        % channel: not stored in channels.txt, cannot be removed, and
        % consulted before any subscribed channel during bare-name resolution.
        channels = [{'mip-org/core'}, mip.state.get_channels()];
        fprintf('Channels (in priority order):\n');
        for i = 1:length(channels)
            fprintf('  %s\n', channels{i});
        end

    otherwise
        error('mip:unknownSubcommand', ...
              'Unknown "mip channel" subcommand "%s". Use add, append, remove, or list.', sub);
end

end

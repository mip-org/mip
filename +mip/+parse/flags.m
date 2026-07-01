function [opts, positionals] = flags(args, spec, aliases)
%FLAGS   Parse command-line style flags from an argument list.
%
% Shared flag parser for the mip commands. The spec is a struct of
% defaults; each field's type determines the flag's arity:
%
%   false  - boolean flag:         --force sets opts.force = true
%   ''     - single-value flag:    --url <v> sets opts.url = v;
%            a repeat raises mip:repeatedFlag
%   {}     - repeatable flag:      each --with <v> appends v to opts.with
%
% Field names map to flag names with underscores as hyphens
% (no_compile -> --no-compile). Note the struct() cell gotcha for
% repeatable defaults: write struct('with', {{}}).
%
% A '--' argument that is not in the spec raises mip:unknownFlag. A flag
% in final position with no value raises mip:missingFlagValue. The value
% following a value flag is consumed verbatim, even if it starts with
% '--'.
%
% Args:
%   args    - Cell array of arguments (typically varargin)
%   aliases - (Optional) Struct mapping single-letter short options to
%             spec field names, e.g. struct('e', 'editable') accepts -e.
%
% Returns:
%   opts        - spec with parsed values filled in (string values
%                 converted to char)
%   positionals - Cell array of non-flag arguments in order (string
%                 scalars converted to char)

if nargin < 3
    aliases = struct();
end

opts = spec;
positionals = {};

% Map '--flag-name' -> spec field name
flagMap = containers.Map('KeyType', 'char', 'ValueType', 'char');
specFields = fieldnames(spec);
for k = 1:numel(specFields)
    flagMap(['--' strrep(specFields{k}, '_', '-')]) = specFields{k};
end

seen = struct();

i = 1;
while i <= numel(args)
    arg = args{i};
    if isstring(arg) && isscalar(arg)
        arg = char(arg);
    end

    fieldName = '';
    if ischar(arg) && strncmp(arg, '--', 2)
        if ~flagMap.isKey(arg)
            error('mip:unknownFlag', 'Unknown flag "%s".', arg);
        end
        fieldName = flagMap(arg);
    elseif ischar(arg) && numel(arg) == 2 && arg(1) == '-' && isfield(aliases, arg(2))
        fieldName = aliases.(arg(2));
    end

    if isempty(fieldName)
        positionals{end+1} = arg; %#ok<AGROW>
        i = i + 1;
        continue
    end

    if islogical(spec.(fieldName))
        opts.(fieldName) = true;
        i = i + 1;
        continue
    end

    if i + 1 > numel(args)
        error('mip:missingFlagValue', '%s requires a value.', arg);
    end
    value = args{i + 1};
    if isstring(value) && isscalar(value)
        value = char(value);
    end
    if iscell(spec.(fieldName))
        opts.(fieldName) = [opts.(fieldName), {value}];
    else
        if isfield(seen, fieldName)
            error('mip:repeatedFlag', '%s may be specified at most once.', arg);
        end
        seen.(fieldName) = true;
        opts.(fieldName) = value;
    end
    i = i + 2;
end

end

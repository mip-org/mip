function t = classify_arg(arg)
%CLASSIFY_ARG   Classify an environment argument as a name or a path.
%
% Usage:
%   t = mip.env.classify_arg(arg)
%
% Environment arguments are disambiguated syntactically, never by
% guessing: a bare word is a name in the baseline envs/ store; anything
% containing a path separator ('/', or '\' on Windows) is a path. There
% is no fallback from one namespace to the other.
%
% Returns a struct:
%   kind - 'name' or 'path'
%   name - the environment name ('' for paths)
%   path - absolute path of the environment root
%
% Names are validated with mip.name.is_valid (same rule as package-name
% components) and compared exactly as typed. Relative paths are stored
% and displayed absolute; the target does not need to exist.

arg = char(arg);
if isempty(arg)
    error('mip:env:invalidName', 'Environment name must not be empty.');
end

isPath = contains(arg, '/') || (ispc && contains(arg, '\'));
if isPath
    t = struct('kind', 'path', 'name', '', 'path', absolutize(arg));
    return
end

if ~mip.name.is_valid(arg)
    error('mip:env:invalidName', ...
          ['Invalid environment name "%s". Names may contain letters, ' ...
           'digits, hyphens, and underscores, and must start and end ' ...
           'with a letter or digit.'], arg);
end
t = struct('kind', 'name', 'name', arg, 'path', ...
           fullfile(mip.env.store_dir(), arg));

end

function p = absolutize(p)
% Resolve a possibly-nonexistent path to an absolute, normalized form.
% mip.paths.get_absolute_path requires the target to exist, so it is only
% used when it can be; otherwise the path is anchored to pwd and '.'/'..'
% segments are collapsed lexically.

    if isfolder(p)
        p = mip.paths.get_absolute_path(p);
        return
    end

    if startsWith(p, '~')
        home = getenv('HOME');
        if ~isempty(home) && (numel(p) == 1 || p(2) == '/' || (ispc && p(2) == '\'))
            p = fullfile(home, p(2:end));
        end
    end
    if ~is_absolute(p)
        p = fullfile(pwd, p);
    end
    p = collapse_segments(p);
end

function tf = is_absolute(p)
    if ispc
        tf = ~isempty(regexp(p, '^[A-Za-z]:[\\/]', 'once')) ...
             || startsWith(p, '\\') || startsWith(p, '//');
    else
        tf = startsWith(p, '/');
    end
end

function p = collapse_segments(p)
% Lexically collapse '.' and '..' segments and duplicate separators.
    if ispc
        parts = strsplit(p, {'\', '/'}, 'CollapseDelimiters', false);
    else
        parts = strsplit(p, '/', 'CollapseDelimiters', false);
    end
    head = parts{1};  % '' for a unix absolute path, 'C:' on Windows
    stack = {};
    for i = 2:numel(parts)
        s = parts{i};
        if isempty(s) || strcmp(s, '.')
            continue
        end
        if strcmp(s, '..')
            if ~isempty(stack)
                stack(end) = [];
            end
            continue
        end
        stack{end+1} = s; %#ok<AGROW>
    end
    p = strjoin([{head}, stack], filesep);
    if isempty(stack) && isempty(head)
        p = filesep;  % collapsed all the way to the unix root
    end
end

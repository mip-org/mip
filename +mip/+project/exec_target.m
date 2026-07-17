function exec_target(target, extraArgs)
%EXEC_TARGET   Execute a "mip project run" target in a scoped workspace.
%
% Usage:
%   mip.project.exec_target(target, extraArgs)
%
% Dispatches the target syntactically: script / function call /
% expression. Every form executes in this function's workspace, which is
% discarded on return - mip never injects variables into the base
% workspace (no evalin/assignin). A target's output is what it displays
% or writes to disk.
%
% This lives in its own file (rather than inside mip.project.run) so the
% script form can call MATLAB's run: inside a function named "run", an
% unqualified run(...) would recurse.

% A target can look path-like and still be an expression that merely
% mentions a path, e.g. save('./out/x.mat','v'). Treat it as a script only
% when the file exists, or when it carries no expression syntax at all --
% so a genuinely missing script still errors instead of being eval'd.
looksLikePath = contains(target, '/') || (ispc && contains(target, '\')) ...
                || endsWith(target, '.m');
isExpressionLike = ~isempty(regexp(target, '[;()=,]', 'once'));
isScript = looksLikePath && (isfile(target) || ~isExpressionLike);
if isScript
    if ~isfile(target)
        error('mip:project:targetNotFound', 'Script "%s" not found.', target);
    end
    % MATLAB's usual script semantics: run executes the script from the
    % directory it lives in.
    run(target);
    return
end

if ~isempty(regexp(target, '^[A-Za-z]\w*$', 'once'))
    % Command syntax: every argument arrives as char, and an unsuppressed
    % result displays as it would at the prompt.
    if isempty(extraArgs)
        cmd = target;
    else
        quoted = cellfun(@(a) ['''' escape_quotes(a) ''''], extraArgs, ...
                         'UniformOutput', false);
        cmd = sprintf('%s(%s)', target, strjoin(quoted, ', '));
    end
    eval(cmd);
    return
end

if ~isempty(extraArgs)
    error('mip:project:tooManyArgs', ...
          ['The expression form of "mip project run" takes a single ' ...
           'quoted expression; put arguments inside it.']);
end
eval(target);

end

function s = escape_quotes(s)
    s = strrep(s, '''', '''''');
end

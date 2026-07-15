function edit_spec(specPath, group, addEntries, removeNames)
%EDIT_SPEC   Edit a dependency list in a project's mip.yaml, in place.
%
% Usage:
%   mip.project.edit_spec(specPath, group, addEntries, removeNames)
%
% The targeted editor behind "mip project add" and "mip project remove".
% mip.yaml is a user-owned file, so the edit is surgical: only the lines
% of the target list change; everything else - comments, ordering, other
% keys - is preserved byte for byte.
%
% Args:
%   specPath    - Path to mip.yaml
%   group       - '' for the top-level dependencies list, or a
%                 dependency_groups group name (created if missing)
%   addEntries  - Cell array of dependency specs to add. An entry whose
%                 package name (name-equivalence, @version ignored)
%                 already appears in the list replaces that entry, so
%                 "add chebfun@2.0" updates an existing chebfun pin.
%   removeNames - Cell array of package names/specs to remove (matched by
%                 package name, @version and channel ignored). A name not
%                 present in the list is an error.
%
% Supported list layouts: a block sequence ("- entry" lines), a flow
% sequence ("dependencies: [a, b]", rewritten in flow style), an empty
% key, or a missing key (appended). Entries must be scalars, which
% dependency lists always are.

text = fileread(specPath);
crlf = contains(text, sprintf('\r\n'));
text = strrep(text, sprintf('\r\n'), sprintf('\n'));
lines = strsplit(text, '\n', 'CollapseDelimiters', false);
% strsplit leaves a trailing '' when the file ends with a newline; drop
% it and re-add the final newline on write.
if ~isempty(lines) && isempty(lines{end})
    lines = lines(1:end-1);
end

loc = locate_list(lines, group);

% Apply removals first (a replace is handled by add itself).
for i = 1:numel(removeNames)
    name = strip_version(removeNames{i});
    idx = find_entry(loc.entries, name);
    if isempty(idx)
        listLabel = list_label(group);
        error('mip:project:dependencyNotDeclared', ...
              '"%s" is not in %s of mip.yaml.', name, listLabel);
    end
    loc.entries(idx) = [];
end

% Apply additions (replacing an existing entry for the same package).
for i = 1:numel(addEntries)
    entry = addEntries{i};
    idx = find_entry(loc.entries, strip_version(entry));
    if isempty(idx)
        loc.entries{end+1} = entry;
    else
        for k = 1:numel(idx)
            loc.entries{idx(k)} = entry;
        end
    end
end

lines = render_list(lines, loc, group);

fid = fopen(specPath, 'w');
if fid == -1
    error('mip:fileError', 'Could not write to %s', specPath);
end
out = [strjoin(lines, newline) newline];
if crlf
    out = strrep(out, newline, sprintf('\r\n'));
end
fwrite(fid, out);
fclose(fid);

end

% =====================================================================

function loc = locate_list(lines, group)
% Find the target list in the file. Returns a struct:
%   kind       - 'block' | 'flow' | 'empty' | 'missing' | 'missing-parent'
%   keyLine    - index of the key line (0 when missing)
%   keyIndent  - indentation of the key line
%   itemLines  - indices of the "- entry" lines (block lists)
%   itemIndent - indentation for item lines
%   entries    - current entry strings, in order
%   parentLine - dependency_groups key line (groups only; 0 when missing)
    loc = struct('kind', 'missing', 'keyLine', 0, 'keyIndent', 0, ...
                 'itemLines', [], 'itemIndent', 2, 'entries', {{}}, ...
                 'parentLine', 0);

    if isempty(group)
        keyPattern = '^dependencies\s*:';
        searchRange = [1, numel(lines)];
        keyIndentExpected = 0;
    else
        parentLine = 0;
        for i = 1:numel(lines)
            if ~isempty(regexp(lines{i}, '^dependency_groups\s*:', 'once'))
                parentLine = i;
                break
            end
        end
        loc.parentLine = parentLine;
        if parentLine == 0
            loc.kind = 'missing-parent';
            return
        end
        % The parent block ends at the next non-blank, non-comment line
        % with zero indentation.
        blockEnd = numel(lines);
        for i = parentLine+1:numel(lines)
            if is_blank_or_comment(lines{i})
                continue
            end
            if indent_of(lines{i}) == 0
                blockEnd = i - 1;
                break
            end
        end
        keyPattern = ['^\s+' regexptranslate('escape', group) '\s*:'];
        searchRange = [parentLine+1, blockEnd];
        keyIndentExpected = -1;  % any positive indent
    end

    keyLine = 0;
    for i = searchRange(1):searchRange(2)
        if isempty(regexp(lines{i}, keyPattern, 'once'))
            continue
        end
        if keyIndentExpected == 0 && indent_of(lines{i}) ~= 0
            continue
        end
        keyLine = i;
        break
    end
    if keyLine == 0
        return  % kind 'missing' (base) - or a group missing under an existing parent
    end

    loc.keyLine = keyLine;
    loc.keyIndent = indent_of(lines{keyLine});

    rest = strtrim(regexprep(lines{keyLine}, keyPattern, '', 'once'));
    rest = strip_comment(rest);
    if ~isempty(rest)
        if rest(1) == '['
            loc.kind = 'flow';
            loc.entries = parse_flow_entries(rest, lines{keyLine});
            return
        end
        error('mip:project:specUnsupported', ...
              'Cannot edit mip.yaml: the "%s" value is not a list.', ...
              list_label(group));
    end

    % Block or empty: collect "- entry" item lines below the key.
    loc.kind = 'empty';
    for i = keyLine+1:numel(lines)
        if is_blank_or_comment(lines{i})
            continue
        end
        ind = indent_of(lines{i});
        if ind <= loc.keyIndent
            break
        end
        trimmed = strtrim(lines{i});
        if trimmed(1) ~= '-'
            break  % a nested mapping, not a sequence - leave untouched
        end
        loc.kind = 'block';
        loc.itemLines(end+1) = i;
        loc.itemIndent = ind;
        loc.entries{end+1} = parse_item_entry(lines{i});
    end
    if strcmp(loc.kind, 'empty')
        loc.itemIndent = loc.keyIndent + 2;
    end
end

function lines = render_list(lines, loc, group)
% Write the edited entry list back into the file lines.
    switch loc.kind
        case 'flow'
            lines{loc.keyLine} = sprintf('%s%s: %s', ...
                blanks(loc.keyIndent), key_name(group), render_flow(loc.entries));

        case {'block', 'empty'}
            itemLines = cellfun(@(e) sprintf('%s- %s', blanks(loc.itemIndent), e), ...
                                loc.entries, 'UniformOutput', false);
            if strcmp(loc.kind, 'block')
                % Replace the item span with the new items; blank/comment
                % lines interleaved between items are preserved after them.
                first = loc.itemLines(1);
                last = loc.itemLines(end);
                span = first:last;
                interleaved = lines(span(~ismember(span, loc.itemLines)));
                lines = [lines(1:first-1), itemLines, interleaved, lines(last+1:end)];
            else
                if isempty(loc.entries)
                    return
                end
                lines = [lines(1:loc.keyLine), itemLines, lines(loc.keyLine+1:end)];
            end

        case 'missing'
            newLines = {};
            newLines{end+1} = sprintf('%s:', key_name(group));
            for i = 1:numel(loc.entries)
                newLines{end+1} = sprintf('  - %s', loc.entries{i}); %#ok<AGROW>
            end
            if isempty(loc.entries)
                newLines = {sprintf('%s: []', key_name(group))};
            end
            if ~isempty(group) && loc.parentLine > 0
                % dependency_groups exists but the group does not: insert
                % the group at the top of the parent block.
                groupLines = cellfun(@(l) ['  ' l], newLines, 'UniformOutput', false);
                lines = [lines(1:loc.parentLine), groupLines, lines(loc.parentLine+1:end)];
            else
                lines = [lines, newLines];
            end

        case 'missing-parent'
            newLines = {'dependency_groups:'};
            newLines{end+1} = sprintf('  %s:', group);
            for i = 1:numel(loc.entries)
                newLines{end+1} = sprintf('    - %s', loc.entries{i}); %#ok<AGROW>
            end
            lines = [lines, newLines];
    end
end

function name = key_name(group)
    if isempty(group)
        name = 'dependencies';
    else
        name = group;
    end
end

function label = list_label(group)
    if isempty(group)
        label = 'dependencies';
    else
        label = sprintf('dependency group "%s"', group);
    end
end

function idx = find_entry(entries, name)
% Indices of entries whose package name matches name (name equivalence;
% @version and channel qualification ignored).
    idx = [];
    for i = 1:numel(entries)
        try
            entryName = mip.parse.parse_package_arg(entries{i}).name;
        catch
            continue
        end
        if mip.name.match(entryName, name)
            idx(end+1) = i; %#ok<AGROW>
        end
    end
end

function name = strip_version(entry)
    parsed = mip.parse.parse_package_arg(entry);
    name = parsed.name;
end

function tf = is_blank_or_comment(line)
    t = strtrim(line);
    tf = isempty(t) || t(1) == '#';
end

function n = indent_of(line)
    n = numel(line) - numel(regexprep(line, '^ +', ''));
end

function entry = parse_item_entry(line)
    t = strtrim(line);
    t = strtrim(t(2:end));      % drop the '-'
    t = strip_comment(t);
    t = strip_quotes(t);
    entry = t;
end

function s = strip_comment(s)
% Remove a trailing " # comment" (quote-aware enough for scalar entries:
% a '#' inside quotes is kept).
    if isempty(s)
        return
    end
    if s(1) == '"' || s(1) == ''''
        q = s(1);
        closeIdx = find(s(2:end) == q, 1);
        if ~isempty(closeIdx)
            s = s(1:closeIdx+1);
        end
        return
    end
    hashIdx = regexp(s, '\s#', 'once');
    if ~isempty(hashIdx)
        s = strtrim(s(1:hashIdx-1));
    end
end

function s = strip_quotes(s)
    if numel(s) >= 2 && ((s(1) == '"' && s(end) == '"') || ...
                         (s(1) == '''' && s(end) == ''''))
        s = s(2:end-1);
    end
end

function entries = parse_flow_entries(rest, keyLine)
% Parse the entries of a single-line flow sequence "[a, b@1.0]".
    if rest(end) ~= ']'
        error('mip:project:specUnsupported', ...
              'Cannot edit mip.yaml: unterminated flow list on line "%s".', ...
              strtrim(keyLine));
    end
    inner = strtrim(rest(2:end-1));
    entries = {};
    if isempty(inner)
        return
    end
    parts = strsplit(inner, ',');
    for i = 1:numel(parts)
        e = strip_quotes(strtrim(parts{i}));
        if ~isempty(e)
            entries{end+1} = e; %#ok<AGROW>
        end
    end
end

function s = render_flow(entries)
    if isempty(entries)
        s = '[]';
    else
        s = ['[' strjoin(entries, ', ') ']'];
    end
end

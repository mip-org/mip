function result = parse_yaml(yamlText)
%PARSE_YAML   Parse a YAML stream into MATLAB data.
%
% A pared-down YAML 1.2 parser covering a reasonable subset of YAML
% syntax. Derived from the parseYaml routine in yaml_matlab
% (https://github.com/magland/yaml_matlab).
%
% Supported features:
%   - Block and flow mappings and sequences
%   - Plain, single-quoted, and double-quoted (single-line) scalars
%   - Comments (full-line and end-of-line)
%   - Type resolution per the YAML 1.2 core schema:
%       null:  null, Null, NULL, ~, (empty)
%       bool:  true, True, TRUE, false, False, FALSE
%       int:   decimal, 0o-octal, 0x-hex (with optional sign)
%       float: decimal, scientific, .inf, -.inf, .nan
%       str:   anything else
%
% Not supported: multi-document streams, block scalars (| and >),
% multi-line plain or quoted scalars, anchors, aliases, custom tags,
% merge keys, complex (mapping/sequence) keys.
%
% MATLAB representation:
%   mapping  -> struct (field names must be valid MATLAB identifiers)
%   sequence -> row cell array
%   null     -> []
%   bool     -> logical scalar
%   int/float -> double
%   string   -> char row vector

    % --- Input normalization ----------------------------------------------
    if isstring(yamlText)
        if numel(yamlText) ~= 1
            error('mip:parse_yaml:type', ...
                'Input string must be a scalar string.');
        end
        yamlText = char(yamlText);
    elseif ~ischar(yamlText)
        error('mip:parse_yaml:type', ...
            'Input must be a char vector or string scalar.');
    end
    text = yamlText(:).';
    % Strip BOM
    if ~isempty(text) && double(text(1)) == 65279
        text = text(2:end);
    end
    % Normalize line endings
    text = strrep(text, sprintf('\r\n'), sprintf('\n'));
    text = strrep(text, sprintf('\r'), sprintf('\n'));
    % Ensure trailing newline so the parser can always look ahead
    if isempty(text) || text(end) ~= sprintf('\n')
        text = [text sprintf('\n')];
    end

    NL = sprintf('\n');

    pos = 1;
    len = numel(text);
    lineStart = 1;

    skipBlankAndCommentLines();
    if pos > len
        result = struct();
        return;
    end

    rootIndent = pos - lineStart;
    result = parseBlockNode(rootIndent);

    skipBlankAndCommentLines();
    if pos <= len
        error('mip:parse_yaml:trailing', ...
            'Unexpected content after document at position %d.', pos);
    end

    if isempty(result)
        result = struct();
    end

% =====================================================================
% Nested parsing functions
% =====================================================================

    function v = parseBlockNode(indent)
        % Called when pos is at the first non-blank char of a line whose
        % indentation column equals 'indent'. Returns the parsed node.
        if pos > len
            v = [];
            return;
        end
        c = text(pos);
        if c == '-' && (pos+1 > len || text(pos+1) == ' ' || text(pos+1) == NL)
            v = parseBlockSequence(indent);
            return;
        end
        if lineLooksLikeMappingEntry()
            v = parseBlockMapping(indent);
        else
            % Single inline value at this position (rare at top level).
            v = parseInlineValue();
            skipSpacesInLine();
            if pos <= len && text(pos) == '#'
                skipRestOfLine();
            elseif pos <= len && text(pos) == NL
                advanceNewline();
            end
        end
    end

    function tf = lineLooksLikeMappingEntry()
        % Scan from pos to end of current line, ignoring quoted regions
        % and balanced flow brackets, looking for ':' followed by space,
        % newline, or end-of-input. Returns true if found.
        i = pos;
        depth = 0;
        while i <= len
            ch = text(i);
            if ch == NL
                tf = false;
                return;
            end
            if ch == '"'
                i = skipDoubleQuoted(i) + 1;
                continue;
            end
            if ch == ''''
                i = skipSingleQuoted(i) + 1;
                continue;
            end
            if ch == '[' || ch == '{'
                depth = depth + 1;
            elseif ch == ']' || ch == '}'
                depth = depth - 1;
            elseif depth == 0 && ch == ':'
                if i+1 > len || text(i+1) == ' ' || text(i+1) == NL
                    tf = true;
                    return;
                end
            elseif depth == 0 && ch == '#' && i > pos && text(i-1) == ' '
                tf = false;
                return;
            end
            i = i + 1;
        end
        tf = false;
    end

    function endIdx = skipDoubleQuoted(startIdx)
        % Returns index of the closing '"'.
        i = startIdx + 1;
        while i <= len
            if text(i) == '\'
                i = i + 2;
                continue;
            end
            if text(i) == '"'
                endIdx = i;
                return;
            end
            if text(i) == NL
                error('mip:parse_yaml:unterminatedString', ...
                    'Unterminated double-quoted string at position %d.', startIdx);
            end
            i = i + 1;
        end
        error('mip:parse_yaml:unterminatedString', ...
            'Unterminated double-quoted string at position %d.', startIdx);
    end

    function endIdx = skipSingleQuoted(startIdx)
        % Returns index of the closing single quote (handles '' escape).
        i = startIdx + 1;
        while i <= len
            if text(i) == ''''
                if i+1 <= len && text(i+1) == ''''
                    i = i + 2;
                    continue;
                end
                endIdx = i;
                return;
            end
            if text(i) == NL
                error('mip:parse_yaml:unterminatedString', ...
                    'Unterminated single-quoted string at position %d.', startIdx);
            end
            i = i + 1;
        end
        error('mip:parse_yaml:unterminatedString', ...
            'Unterminated single-quoted string at position %d.', startIdx);
    end

    % -----------------------------------------------------------------
    % Block sequence
    % -----------------------------------------------------------------
    function v = parseBlockSequence(indent)
        items = {};
        while true
            loopGuardPos = pos;
            if pos > len
                break;
            end
            curIndent = pos - lineStart;
            if curIndent ~= indent
                break;
            end
            if text(pos) ~= '-'
                break;
            end
            if pos+1 <= len && text(pos+1) ~= ' ' && text(pos+1) ~= NL
                break;
            end
            % Consume '-'
            pos = pos + 1;
            if pos <= len && text(pos) == ' '
                pos = pos + 1;
            end
            if pos <= len && text(pos) == NL
                % Block child on next line(s)
                advanceNewline();
                skipBlankAndCommentLines();
                if pos > len
                    items{end+1} = []; %#ok<AGROW>
                else
                    childIndent = pos - lineStart;
                    if childIndent <= indent
                        items{end+1} = []; %#ok<AGROW>
                    else
                        items{end+1} = parseBlockNode(childIndent); %#ok<AGROW>
                    end
                end
            else
                % Inline value on same line as '-'
                inlineIndent = pos - lineStart;
                items{end+1} = parseInlineOrCompactBlock(inlineIndent); %#ok<AGROW>
            end
            skipBlankAndCommentLines();
            if pos == loopGuardPos
                error('mip:parse_yaml:noProgress', ...
                    'parseBlockSequence: no progress at position %d.', pos);
            end
        end
        v = items;
    end

    function v = parseInlineOrCompactBlock(inlineIndent)
        % After "- " there can be either an inline value or a compact
        % block collection (e.g. "- key: value" or "- - subitem").
        if pos > len
            v = [];
            return;
        end
        c = text(pos);
        if c == '-' && (pos+1 > len || text(pos+1) == ' ' || text(pos+1) == NL)
            v = parseBlockSequence(inlineIndent);
            return;
        end
        if lineLooksLikeMappingEntry()
            v = parseBlockMapping(inlineIndent);
            return;
        end
        v = parseInlineValue();
        skipSpacesInLine();
        if pos <= len && text(pos) == '#'
            skipRestOfLine();
        elseif pos <= len && text(pos) == NL
            advanceNewline();
        end
    end

    % -----------------------------------------------------------------
    % Block mapping
    % -----------------------------------------------------------------
    function v = parseBlockMapping(indent)
        keys = {};
        values = {};
        while true
            loopGuardPos = pos;
            if pos > len
                break;
            end
            curIndent = pos - lineStart;
            if curIndent ~= indent
                break;
            end
            if ~lineLooksLikeMappingEntry()
                break;
            end
            key = readMappingKey();
            % Skip optional spaces between (quoted) key and colon
            while pos <= len && text(pos) == ' '
                pos = pos + 1;
            end
            if pos > len || text(pos) ~= ':'
                error('mip:parse_yaml:expectColon', ...
                    'Expected '':'' at position %d.', pos);
            end
            pos = pos + 1;
            % Skip spaces after colon
            while pos <= len && text(pos) == ' '
                pos = pos + 1;
            end
            if pos <= len && (text(pos) == NL || text(pos) == '#')
                if text(pos) == '#'
                    skipRestOfLine();
                else
                    advanceNewline();
                end
                skipBlankAndCommentLines();
                if pos > len
                    val = [];
                else
                    childIndent = pos - lineStart;
                    if childIndent > indent
                        val = parseBlockNode(childIndent);
                    elseif childIndent == indent && pos <= len && ...
                            text(pos) == '-' && (pos+1 > len || ...
                            text(pos+1) == ' ' || text(pos+1) == NL)
                        % YAML allows a block sequence as a mapping value
                        % to be at the same indent as the mapping itself.
                        val = parseBlockSequence(childIndent);
                    else
                        val = [];
                    end
                end
            else
                % Inline value on same line as the key
                val = parseInlineValue();
                skipSpacesInLine();
                if pos <= len && text(pos) == '#'
                    skipRestOfLine();
                elseif pos <= len && text(pos) == NL
                    advanceNewline();
                end
            end
            keys{end+1} = key; %#ok<AGROW>
            values{end+1} = val; %#ok<AGROW>
            skipBlankAndCommentLines();
            if pos == loopGuardPos
                error('mip:parse_yaml:noProgress', ...
                    'parseBlockMapping: no progress at position %d.', pos);
            end
        end
        v = makeMapping(keys, values);
    end

    function key = readMappingKey()
        if pos > len
            error('mip:parse_yaml:expectKey', ...
                'Expected mapping key at position %d.', pos);
        end
        c = text(pos);
        if c == '"'
            key = parseDoubleQuoted();
        elseif c == ''''
            key = parseSingleQuoted();
        else
            % Plain scalar key: read until ':' (followed by space/newline/EOF)
            startPos = pos;
            while pos <= len
                ch = text(pos);
                if ch == NL
                    error('mip:parse_yaml:keyNewline', ...
                        'Unexpected newline in mapping key at position %d.', startPos);
                end
                if ch == ':' && (pos+1 > len || text(pos+1) == ' ' || text(pos+1) == NL)
                    break;
                end
                pos = pos + 1;
            end
            key = strtrim(text(startPos:pos-1));
        end
        if isempty(key)
            key = '';
        elseif ~ischar(key)
            key = char(string(key));
        end
    end

    % -----------------------------------------------------------------
    % Inline (single value) parsing
    % -----------------------------------------------------------------
    function v = parseInlineValue()
        if pos > len
            v = [];
            return;
        end
        c = text(pos);
        if c == '['
            v = parseFlowSequence();
        elseif c == '{'
            v = parseFlowMapping();
        elseif c == '"'
            v = parseDoubleQuoted();
        elseif c == ''''
            v = parseSingleQuoted();
        else
            v = parsePlainScalar(false);
        end
    end

    % -----------------------------------------------------------------
    % Flow collections
    % -----------------------------------------------------------------
    function v = parseFlowSequence()
        % pos is at '['
        pos = pos + 1;
        items = {};
        skipFlowWhitespace();
        if pos <= len && text(pos) == ']'
            pos = pos + 1;
            v = items;
            return;
        end
        while true
            loopGuardPos = pos;
            skipFlowWhitespace();
            items{end+1} = parseFlowNode(); %#ok<AGROW>
            skipFlowWhitespace();
            if pos > len
                error('mip:parse_yaml:unterminatedFlow', ...
                    'Unterminated flow sequence.');
            end
            if text(pos) == ','
                pos = pos + 1;
                skipFlowWhitespace();
                if pos <= len && text(pos) == ']'
                    pos = pos + 1;
                    v = items;
                    return;
                end
            elseif text(pos) == ']'
                pos = pos + 1;
                v = items;
                return;
            else
                error('mip:parse_yaml:flowSeparator', ...
                    'Expected '','' or '']'' in flow sequence at position %d.', pos);
            end
            if pos == loopGuardPos
                error('mip:parse_yaml:noProgress', ...
                    'parseFlowSequence: no progress at position %d.', pos);
            end
        end
    end

    function v = parseFlowMapping()
        % pos is at '{'
        pos = pos + 1;
        keys = {};
        values = {};
        skipFlowWhitespace();
        if pos <= len && text(pos) == '}'
            pos = pos + 1;
            v = makeMapping(keys, values);
            return;
        end
        while true
            loopGuardPos = pos;
            skipFlowWhitespace();
            if pos > len
                error('mip:parse_yaml:unterminatedFlow', ...
                    'Unterminated flow mapping.');
            end
            kc = text(pos);
            if kc == '"'
                key = parseDoubleQuoted();
            elseif kc == ''''
                key = parseSingleQuoted();
            else
                startPos = pos;
                while pos <= len
                    ch = text(pos);
                    if ch == ':' && (pos+1 > len || text(pos+1) == ' ' || ...
                            text(pos+1) == NL || text(pos+1) == ',' || ...
                            text(pos+1) == '}' || text(pos+1) == ']')
                        break;
                    end
                    if ch == ',' || ch == '}' || ch == ']' || ch == NL
                        break;
                    end
                    pos = pos + 1;
                end
                key = strtrim(text(startPos:pos-1));
            end
            skipFlowWhitespace();
            if pos <= len && text(pos) == ':'
                pos = pos + 1;
                skipFlowWhitespace();
                if pos <= len && text(pos) ~= ',' && text(pos) ~= '}'
                    val = parseFlowNode();
                else
                    val = [];
                end
            else
                val = [];
            end
            keys{end+1} = key; %#ok<AGROW>
            values{end+1} = val; %#ok<AGROW>
            skipFlowWhitespace();
            if pos > len
                error('mip:parse_yaml:unterminatedFlow', ...
                    'Unterminated flow mapping.');
            end
            if text(pos) == ','
                pos = pos + 1;
                skipFlowWhitespace();
                if pos <= len && text(pos) == '}'
                    pos = pos + 1;
                    v = makeMapping(keys, values);
                    return;
                end
            elseif text(pos) == '}'
                pos = pos + 1;
                v = makeMapping(keys, values);
                return;
            else
                error('mip:parse_yaml:flowSeparator', ...
                    'Expected '','' or ''}'' in flow mapping at position %d.', pos);
            end
            if pos == loopGuardPos
                error('mip:parse_yaml:noProgress', ...
                    'parseFlowMapping: no progress at position %d.', pos);
            end
        end
    end

    function v = parseFlowNode()
        skipFlowWhitespace();
        if pos > len
            v = [];
            return;
        end
        c = text(pos);
        if c == '['
            v = parseFlowSequence();
        elseif c == '{'
            v = parseFlowMapping();
        elseif c == '"'
            v = parseDoubleQuoted();
        elseif c == ''''
            v = parseSingleQuoted();
        else
            v = parsePlainScalar(true);
        end
    end

    function skipFlowWhitespace()
        % Skip spaces, tabs, newlines, and comments inside flow context.
        while pos <= len
            ch = text(pos);
            if ch == ' ' || ch == sprintf('\t')
                pos = pos + 1;
            elseif ch == NL
                advanceNewline();
            elseif ch == '#'
                skipRestOfLine();
            else
                return;
            end
        end
    end

    % -----------------------------------------------------------------
    % Scalars
    % -----------------------------------------------------------------
    function v = parsePlainScalar(inFlow)
        % Read a single-line plain scalar.
        startPos = pos;
        while pos <= len
            ch = text(pos);
            if ch == NL
                break;
            end
            if ch == ':' && (pos+1 > len || text(pos+1) == ' ' || ...
                    text(pos+1) == NL || (inFlow && (text(pos+1) == ',' || ...
                    text(pos+1) == '}' || text(pos+1) == ']')))
                break;
            end
            if ch == '#' && pos > startPos && text(pos-1) == ' '
                break;
            end
            if inFlow && (ch == ',' || ch == '[' || ch == ']' || ch == '{' || ch == '}')
                break;
            end
            pos = pos + 1;
        end
        raw = strtrim(text(startPos:pos-1));
        v = resolveScalar(raw);
    end

    function v = parseSingleQuoted()
        % pos is at the opening single quote
        pos = pos + 1;
        startPos = pos;
        buf = '';
        while pos <= len
            ch = text(pos);
            if ch == ''''
                if pos+1 <= len && text(pos+1) == ''''
                    buf = [buf text(startPos:pos)]; %#ok<AGROW>
                    pos = pos + 2;
                    startPos = pos;
                    continue;
                end
                buf = [buf text(startPos:pos-1)]; %#ok<AGROW>
                pos = pos + 1;
                v = buf;
                return;
            end
            if ch == NL
                error('mip:parse_yaml:unterminatedString', ...
                    'Unterminated single-quoted string.');
            end
            pos = pos + 1;
        end
        error('mip:parse_yaml:unterminatedString', ...
            'Unterminated single-quoted string.');
    end

    function v = parseDoubleQuoted()
        % pos is at the opening double quote
        pos = pos + 1;
        buf = '';
        startPos = pos;
        while pos <= len
            ch = text(pos);
            if ch == '\'
                if pos > startPos
                    buf = [buf text(startPos:pos-1)]; %#ok<AGROW>
                end
                if pos+1 > len
                    error('mip:parse_yaml:badEscape', ...
                        'Bad escape at end of input.');
                end
                esc = text(pos+1);
                switch esc
                    case '0',  buf = [buf char(0)]; pos = pos + 2; %#ok<AGROW>
                    case 'a',  buf = [buf char(7)]; pos = pos + 2; %#ok<AGROW>
                    case 'b',  buf = [buf char(8)]; pos = pos + 2; %#ok<AGROW>
                    case 't',  buf = [buf char(9)]; pos = pos + 2; %#ok<AGROW>
                    case 'n',  buf = [buf char(10)]; pos = pos + 2; %#ok<AGROW>
                    case 'v',  buf = [buf char(11)]; pos = pos + 2; %#ok<AGROW>
                    case 'f',  buf = [buf char(12)]; pos = pos + 2; %#ok<AGROW>
                    case 'r',  buf = [buf char(13)]; pos = pos + 2; %#ok<AGROW>
                    case 'e',  buf = [buf char(27)]; pos = pos + 2; %#ok<AGROW>
                    case ' ',  buf = [buf ' '];     pos = pos + 2; %#ok<AGROW>
                    case '"',  buf = [buf '"'];     pos = pos + 2; %#ok<AGROW>
                    case '/',  buf = [buf '/'];     pos = pos + 2; %#ok<AGROW>
                    case '\',  buf = [buf '\'];     pos = pos + 2; %#ok<AGROW>
                    case 'x'
                        if pos+3 > len
                            error('mip:parse_yaml:badEscape', ...
                                'Bad \\x escape at position %d.', pos);
                        end
                        hex = text(pos+2:pos+3);
                        buf = [buf char(hex2dec(hex))]; %#ok<AGROW>
                        pos = pos + 4;
                    case 'u'
                        if pos+5 > len
                            error('mip:parse_yaml:badEscape', ...
                                'Bad \\u escape at position %d.', pos);
                        end
                        hex = text(pos+2:pos+5);
                        buf = [buf char(hex2dec(hex))]; %#ok<AGROW>
                        pos = pos + 6;
                    otherwise
                        error('mip:parse_yaml:badEscape', ...
                            'Unknown escape \\%s at position %d.', esc, pos);
                end
                startPos = pos;
                continue;
            end
            if ch == '"'
                if pos > startPos
                    buf = [buf text(startPos:pos-1)]; %#ok<AGROW>
                end
                pos = pos + 1;
                v = buf;
                return;
            end
            if ch == NL
                error('mip:parse_yaml:unterminatedString', ...
                    'Unterminated double-quoted string.');
            end
            pos = pos + 1;
        end
        error('mip:parse_yaml:unterminatedString', ...
            'Unterminated double-quoted string.');
    end

    % -----------------------------------------------------------------
    % Whitespace / position helpers
    % -----------------------------------------------------------------
    function skipBlankAndCommentLines()
        % Skip blank lines and comment lines starting from pos. After
        % returning, pos is positioned at the first non-space character of
        % the next content line (or past EOF).
        while pos <= len
            sbcGuard = pos;
            if pos ~= lineStart
                while pos <= len && text(pos) == ' '
                    pos = pos + 1;
                end
                if pos > len, return; end
                if text(pos) == NL
                    advanceNewline();
                    if pos == sbcGuard, return; end
                    continue;
                end
                if text(pos) == '#'
                    skipRestOfLine();
                    if pos == sbcGuard, return; end
                    continue;
                end
                return;
            end

            % At line start. Walk leading spaces.
            p = pos;
            while p <= len && text(p) == ' '
                p = p + 1;
            end
            if p > len
                pos = p;
                return;
            end
            if text(p) == NL
                pos = p;
                advanceNewline();
                if pos == sbcGuard, return; end
                continue;
            end
            if text(p) == '#'
                pos = p;
                skipRestOfLine();
                if pos == sbcGuard, return; end
                continue;
            end
            % Non-blank, non-comment line: position pos at first non-space
            pos = p;
            return;
        end
    end

    function skipSpacesInLine()
        while pos <= len && text(pos) == ' '
            pos = pos + 1;
        end
    end

    function skipRestOfLine()
        while pos <= len && text(pos) ~= NL
            pos = pos + 1;
        end
        if pos <= len && text(pos) == NL
            advanceNewline();
        end
    end

    function advanceNewline()
        % Assumes text(pos) == NL
        pos = pos + 1;
        lineStart = pos;
    end
end

% =====================================================================
% Local helpers
% =====================================================================

function s = makeMapping(keys, values)
    s = struct();
    for k = 1:numel(keys)
        key = keys{k};
        if ~ischar(key)
            key = char(string(key));
        end
        if ~isvarname(key)
            sanitized = matlab.lang.makeValidName(key);
            warning('mip:parse_yaml:keyName', ...
                'Mapping key "%s" is not a valid MATLAB field name; using "%s".', ...
                key, sanitized);
            key = sanitized;
        end
        s.(key) = values{k};
    end
end

function v = resolveScalar(raw)
    % Apply YAML 1.2 core schema type resolution to a plain scalar string.
    if isempty(raw)
        v = [];
        return;
    end
    % null
    if any(strcmp(raw, {'null', 'Null', 'NULL', '~'}))
        v = [];
        return;
    end
    % bool
    if any(strcmp(raw, {'true', 'True', 'TRUE'}))
        v = true;
        return;
    end
    if any(strcmp(raw, {'false', 'False', 'FALSE'}))
        v = false;
        return;
    end
    % int (decimal, hex, octal)
    if ~isempty(regexp(raw, '^[-+]?[0-9]+$', 'once'))
        v = sscanf(raw, '%lf');
        return;
    end
    if ~isempty(regexp(raw, '^0x[0-9a-fA-F]+$', 'once'))
        v = double(hex2dec(raw(3:end)));
        return;
    end
    if ~isempty(regexp(raw, '^0o[0-7]+$', 'once'))
        v = double(base2dec(raw(3:end), 8));
        return;
    end
    % float
    if ~isempty(regexp(raw, '^[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?$', 'once'))
        v = sscanf(raw, '%lf');
        return;
    end
    if any(strcmp(raw, {'.inf', '.Inf', '.INF'}))
        v = inf;
        return;
    end
    if any(strcmp(raw, {'+.inf', '+.Inf', '+.INF'}))
        v = inf;
        return;
    end
    if any(strcmp(raw, {'-.inf', '-.Inf', '-.INF'}))
        v = -inf;
        return;
    end
    if any(strcmp(raw, {'.nan', '.NaN', '.NAN'}))
        v = nan;
        return;
    end
    % string
    v = raw;
end

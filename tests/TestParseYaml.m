classdef TestParseYaml < matlab.unittest.TestCase
%TESTPARSEYAML   Tests for mip.parse.parse_yaml.

    methods (Test)

        %% Empty / trivial inputs

        function testEmptyInput(testCase)
            r = mip.parse.parse_yaml('');
            testCase.verifyTrue(isstruct(r));
            testCase.verifyTrue(isempty(fieldnames(r)));
        end

        function testCommentsOnlyInput(testCase)
            r = mip.parse.parse_yaml(sprintf('# just a comment\n# another\n'));
            testCase.verifyTrue(isstruct(r));
            testCase.verifyTrue(isempty(fieldnames(r)));
        end

        %% Basic mappings

        function testSingleKeyValue(testCase)
            r = mip.parse.parse_yaml(sprintf('name: foo\n'));
            testCase.verifyEqual(r.name, 'foo');
        end

        function testMultipleKeyValues(testCase)
            r = mip.parse.parse_yaml(sprintf('name: foo\nversion: 1.2.3\n'));
            testCase.verifyEqual(r.name, 'foo');
            testCase.verifyEqual(r.version, '1.2.3');
        end

        function testNestedMapping(testCase)
            yaml = sprintf(['outer:\n' ...
                            '  inner: value\n' ...
                            '  other: 42\n']);
            r = mip.parse.parse_yaml(yaml);
            testCase.verifyEqual(r.outer.inner, 'value');
            testCase.verifyEqual(r.outer.other, 42);
        end

        function testDeeplyNestedMapping(testCase)
            yaml = sprintf(['a:\n' ...
                            '  b:\n' ...
                            '    c: deep\n']);
            r = mip.parse.parse_yaml(yaml);
            testCase.verifyEqual(r.a.b.c, 'deep');
        end

        %% Quoted strings

        function testDoubleQuotedString(testCase)
            r = mip.parse.parse_yaml(sprintf('name: "hello world"\n'));
            testCase.verifyEqual(r.name, 'hello world');
        end

        function testSingleQuotedString(testCase)
            r = mip.parse.parse_yaml(sprintf('name: ''hello world''\n'));
            testCase.verifyEqual(r.name, 'hello world');
        end

        function testSingleQuotedEscapedQuote(testCase)
            r = mip.parse.parse_yaml(sprintf('msg: ''it''''s ok''\n'));
            testCase.verifyEqual(r.msg, 'it''s ok');
        end

        function testDoubleQuotedEscapeSequences(testCase)
            r = mip.parse.parse_yaml(sprintf('msg: "line1\\nline2\\ttab"\n'));
            testCase.verifyEqual(r.msg, sprintf('line1\nline2\ttab'));
        end

        function testQuotedKeepsLeadingZero(testCase)
            r = mip.parse.parse_yaml(sprintf('version: "1.0"\n'));
            testCase.verifyEqual(r.version, '1.0');
        end

        function testQuotedColonInValue(testCase)
            r = mip.parse.parse_yaml(sprintf('url: "https://example.com:8080/path"\n'));
            testCase.verifyEqual(r.url, 'https://example.com:8080/path');
        end

        %% Plain scalar type resolution

        function testIntegerScalar(testCase)
            r = mip.parse.parse_yaml(sprintf('count: 42\n'));
            testCase.verifyEqual(r.count, 42);
            testCase.verifyClass(r.count, 'double');
        end

        function testNegativeInteger(testCase)
            r = mip.parse.parse_yaml(sprintf('value: -17\n'));
            testCase.verifyEqual(r.value, -17);
        end

        function testFloatScalar(testCase)
            r = mip.parse.parse_yaml(sprintf('pi: 3.14\n'));
            testCase.verifyEqual(r.pi, 3.14);
        end

        function testScientificFloat(testCase)
            r = mip.parse.parse_yaml(sprintf('big: 1.5e3\n'));
            testCase.verifyEqual(r.big, 1500);
        end

        function testHexInteger(testCase)
            r = mip.parse.parse_yaml(sprintf('flag: 0xff\n'));
            testCase.verifyEqual(r.flag, 255);
        end

        function testOctalInteger(testCase)
            r = mip.parse.parse_yaml(sprintf('mode: 0o755\n'));
            testCase.verifyEqual(r.mode, 493);
        end

        function testBooleanTrue(testCase)
            r = mip.parse.parse_yaml(sprintf('on: true\n'));
            testCase.verifyTrue(r.on);
            testCase.verifyClass(r.on, 'logical');
        end

        function testBooleanFalse(testCase)
            r = mip.parse.parse_yaml(sprintf('off: false\n'));
            testCase.verifyFalse(r.off);
        end

        function testNullValues(testCase)
            yaml = sprintf(['a: null\n' ...
                            'b: ~\n' ...
                            'c: NULL\n']);
            r = mip.parse.parse_yaml(yaml);
            testCase.verifyEmpty(r.a);
            testCase.verifyEmpty(r.b);
            testCase.verifyEmpty(r.c);
        end

        function testInfNan(testCase)
            yaml = sprintf(['a: .inf\nb: -.inf\nc: .nan\n']);
            r = mip.parse.parse_yaml(yaml);
            testCase.verifyEqual(r.a, inf);
            testCase.verifyEqual(r.b, -inf);
            testCase.verifyTrue(isnan(r.c));
        end

        function testPlainString(testCase)
            r = mip.parse.parse_yaml(sprintf('lang: matlab\n'));
            testCase.verifyEqual(r.lang, 'matlab');
        end

        %% Flow sequences

        function testEmptyFlowSequence(testCase)
            r = mip.parse.parse_yaml(sprintf('items: []\n'));
            testCase.verifyEqual(r.items, {});
        end

        function testFlowSequenceOfStrings(testCase)
            r = mip.parse.parse_yaml(sprintf('deps: [a, b, c]\n'));
            testCase.verifyEqual(r.deps, {'a', 'b', 'c'});
        end

        function testFlowSequenceOfNumbers(testCase)
            r = mip.parse.parse_yaml(sprintf('nums: [1, 2, 3]\n'));
            testCase.verifyEqual(r.nums, {1, 2, 3});
        end

        function testFlowSequenceMixedTypes(testCase)
            r = mip.parse.parse_yaml(sprintf('mix: [foo, 42, true, null]\n'));
            testCase.verifyEqual(r.mix{1}, 'foo');
            testCase.verifyEqual(r.mix{2}, 42);
            testCase.verifyEqual(r.mix{3}, true);
            testCase.verifyEmpty(r.mix{4});
        end

        function testFlowSequenceTrailingComma(testCase)
            r = mip.parse.parse_yaml(sprintf('items: [a, b,]\n'));
            testCase.verifyEqual(r.items, {'a', 'b'});
        end

        %% Block sequences

        function testBlockSequenceOfScalars(testCase)
            yaml = sprintf(['items:\n' ...
                            '  - first\n' ...
                            '  - second\n' ...
                            '  - third\n']);
            r = mip.parse.parse_yaml(yaml);
            testCase.verifyEqual(r.items, {'first', 'second', 'third'});
        end

        function testBlockSequenceSameIndentAsKey(testCase)
            yaml = sprintf(['items:\n' ...
                            '- first\n' ...
                            '- second\n']);
            r = mip.parse.parse_yaml(yaml);
            testCase.verifyEqual(r.items, {'first', 'second'});
        end

        function testBlockSequenceOfMappings(testCase)
            yaml = sprintf(['builds:\n' ...
                            '  - name: a\n' ...
                            '    arch: x86\n' ...
                            '  - name: b\n' ...
                            '    arch: arm\n']);
            r = mip.parse.parse_yaml(yaml);
            testCase.verifyEqual(length(r.builds), 2);
            testCase.verifyEqual(r.builds{1}.name, 'a');
            testCase.verifyEqual(r.builds{1}.arch, 'x86');
            testCase.verifyEqual(r.builds{2}.name, 'b');
            testCase.verifyEqual(r.builds{2}.arch, 'arm');
        end

        function testBlockSequenceOfMappingsWithFlow(testCase)
            yaml = sprintf(['builds:\n' ...
                            '  - architectures: [linux, macos]\n' ...
                            '    release: 1\n' ...
                            '  - architectures: [windows]\n' ...
                            '    release: 2\n']);
            r = mip.parse.parse_yaml(yaml);
            testCase.verifyEqual(r.builds{1}.architectures, {'linux', 'macos'});
            testCase.verifyEqual(r.builds{1}.release, 1);
            testCase.verifyEqual(r.builds{2}.architectures, {'windows'});
            testCase.verifyEqual(r.builds{2}.release, 2);
        end

        function testNestedBlockSequence(testCase)
            yaml = sprintf(['outer:\n' ...
                            '  - name: foo\n' ...
                            '    addpaths:\n' ...
                            '      - path: a\n' ...
                            '      - path: b\n']);
            r = mip.parse.parse_yaml(yaml);
            testCase.verifyEqual(r.outer{1}.name, 'foo');
            testCase.verifyEqual(length(r.outer{1}.addpaths), 2);
            testCase.verifyEqual(r.outer{1}.addpaths{1}.path, 'a');
            testCase.verifyEqual(r.outer{1}.addpaths{2}.path, 'b');
        end

        %% Comments

        function testFullLineComment(testCase)
            yaml = sprintf(['# leading comment\n' ...
                            'name: foo\n' ...
                            '# middle comment\n' ...
                            'version: 1\n']);
            r = mip.parse.parse_yaml(yaml);
            testCase.verifyEqual(r.name, 'foo');
            testCase.verifyEqual(r.version, 1);
        end

        function testEndOfLineComment(testCase)
            r = mip.parse.parse_yaml(sprintf('name: foo  # this is a comment\n'));
            testCase.verifyEqual(r.name, 'foo');
        end

        function testCommentInsideBlockSequence(testCase)
            yaml = sprintf(['items:\n' ...
                            '  - a\n' ...
                            '  # skip me\n' ...
                            '  - b\n']);
            r = mip.parse.parse_yaml(yaml);
            testCase.verifyEqual(r.items, {'a', 'b'});
        end

        %% Blank line handling

        function testBlankLinesIgnored(testCase)
            yaml = sprintf(['name: foo\n' ...
                            '\n' ...
                            'version: 1\n' ...
                            '\n' ...
                            '\n' ...
                            'license: MIT\n']);
            r = mip.parse.parse_yaml(yaml);
            testCase.verifyEqual(r.name, 'foo');
            testCase.verifyEqual(r.version, 1);
            testCase.verifyEqual(r.license, 'MIT');
        end

        %% No trailing newline

        function testNoTrailingNewline(testCase)
            r = mip.parse.parse_yaml('name: foo');
            testCase.verifyEqual(r.name, 'foo');
        end

        %% Realistic mip.yaml example

        function testRealisticMipYaml(testCase)
            yaml = sprintf([ ...
                'name: fmm2d\n' ...
                'description: "Flatiron Institute Fast Multipole Methods in 2D"\n' ...
                'version: main\n' ...
                'license: "Apache-2.0"\n' ...
                'homepage: "https://github.com/flatironinstitute/fmm2d"\n' ...
                'dependencies: []\n' ...
                '\n' ...
                'addpaths:\n' ...
                '  - path: "matlab"\n' ...
                '  # comment in the middle\n' ...
                '  - path: "matlab/numbl"\n' ...
                '\n' ...
                'builds:\n' ...
                '  - architectures: [linux_x86_64, macos_x86_64]\n' ...
                '    release_number: 101\n' ...
                '    compile_script: compile.m\n' ...
                '  - architectures: [numbl_wasm]\n' ...
                '    release_number: 1\n' ...
                '    compile_script: compile_numbl_wasm.m\n']);

            r = mip.parse.parse_yaml(yaml);
            testCase.verifyEqual(r.name, 'fmm2d');
            testCase.verifyEqual(r.description, 'Flatiron Institute Fast Multipole Methods in 2D');
            testCase.verifyEqual(r.version, 'main');
            testCase.verifyEqual(r.license, 'Apache-2.0');
            testCase.verifyEqual(r.homepage, 'https://github.com/flatironinstitute/fmm2d');
            testCase.verifyEqual(r.dependencies, {});

            testCase.verifyEqual(length(r.addpaths), 2);
            testCase.verifyEqual(r.addpaths{1}.path, 'matlab');
            testCase.verifyEqual(r.addpaths{2}.path, 'matlab/numbl');

            testCase.verifyEqual(length(r.builds), 2);
            testCase.verifyEqual(r.builds{1}.architectures, {'linux_x86_64', 'macos_x86_64'});
            testCase.verifyEqual(r.builds{1}.release_number, 101);
            testCase.verifyEqual(r.builds{1}.compile_script, 'compile.m');
            testCase.verifyEqual(r.builds{2}.architectures, {'numbl_wasm'});
            testCase.verifyEqual(r.builds{2}.release_number, 1);
        end

        %% Error cases

        function testErrorOnUnterminatedDoubleQuote(testCase)
            testCase.verifyError(@() mip.parse.parse_yaml(sprintf('name: "unterminated\n')), ...
                'mip:parse_yaml:unterminatedString');
        end

        function testErrorOnUnterminatedSingleQuote(testCase)
            testCase.verifyError(@() mip.parse.parse_yaml(sprintf('name: ''unterminated\n')), ...
                'mip:parse_yaml:unterminatedString');
        end

        function testErrorOnUnterminatedFlowSequence(testCase)
            testCase.verifyError(@() mip.parse.parse_yaml(sprintf('items: [a, b\n')), ...
                'mip:parse_yaml:unterminatedFlow');
        end

    end
end

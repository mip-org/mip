classdef TestKeyValueStorage < matlab.unittest.TestCase
%TESTKEYVALUESTORAGE   Tests for key_value_get/set/append/remove.

    properties
        TestKey = 'MIP_TEST_KEY_12345'
    end

    methods (TestMethodSetup)
        function clearTestKey(testCase)
            if isappdata(0, testCase.TestKey)
                rmappdata(0, testCase.TestKey);
            end
        end
    end

    methods (TestMethodTeardown)
        function removeTestKey(testCase)
            if isappdata(0, testCase.TestKey)
                rmappdata(0, testCase.TestKey);
            end
        end
    end

    methods (Test)

        function testGetEmptyReturnsEmptyCell(testCase)
            val = mip.utils.key_value_get(testCase.TestKey);
            testCase.verifyEqual(val, {});
        end

        function testSetAndGet(testCase)
            mip.utils.key_value_set(testCase.TestKey, {'a', 'b'});
            val = mip.utils.key_value_get(testCase.TestKey);
            testCase.verifyEqual(val, {'a', 'b'});
        end

        function testAppendToEmpty(testCase)
            mip.utils.key_value_append(testCase.TestKey, 'first');
            val = mip.utils.key_value_get(testCase.TestKey);
            testCase.verifyEqual(val, {'first'});
        end

        function testAppendMultiple(testCase)
            mip.utils.key_value_append(testCase.TestKey, 'a');
            mip.utils.key_value_append(testCase.TestKey, 'b');
            mip.utils.key_value_append(testCase.TestKey, 'c');
            val = mip.utils.key_value_get(testCase.TestKey);
            testCase.verifyEqual(val, {'a', 'b', 'c'});
        end

        function testAppendDuplicateIsNoOp(testCase)
            mip.utils.key_value_append(testCase.TestKey, 'x');
            mip.utils.key_value_append(testCase.TestKey, 'x');
            val = mip.utils.key_value_get(testCase.TestKey);
            testCase.verifyEqual(val, {'x'});
        end

        function testRemove(testCase)
            mip.utils.key_value_set(testCase.TestKey, {'a', 'b', 'c'});
            mip.utils.key_value_remove(testCase.TestKey, 'b');
            val = mip.utils.key_value_get(testCase.TestKey);
            testCase.verifyEqual(val, {'a', 'c'});
        end

        function testRemoveNonExistent(testCase)
            mip.utils.key_value_set(testCase.TestKey, {'a', 'b'});
            mip.utils.key_value_remove(testCase.TestKey, 'z');
            val = mip.utils.key_value_get(testCase.TestKey);
            testCase.verifyEqual(val, {'a', 'b'});
        end

        function testRemoveFromEmpty(testCase)
            mip.utils.key_value_remove(testCase.TestKey, 'x');
            val = mip.utils.key_value_get(testCase.TestKey);
            testCase.verifyEqual(val, {});
        end

        function testSetOverwrites(testCase)
            mip.utils.key_value_set(testCase.TestKey, {'old'});
            mip.utils.key_value_set(testCase.TestKey, {'new1', 'new2'});
            val = mip.utils.key_value_get(testCase.TestKey);
            testCase.verifyEqual(val, {'new1', 'new2'});
        end

    end
end

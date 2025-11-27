require('luacov')
local assert = require('assert')
local errno = require('errno')
local sleep = require('time.sleep')
local canceler = require('canceler')
-- Lua 5.1 compatibility
local unpack = unpack or table.unpack

local testcase = {}

-- Helper function to assert not done state
local function assert_not_done(done, err, timeout)
    assert.is_false(done)
    assert.is_nil(err)
    assert.is_nil(timeout)
end

-- Helper function to assert canceled state
local function assert_canceled(ctx, expected_msg)
    local done, err, timeout, sec_left = ctx:check()
    assert.is_true(done)
    assert.equal(err.type, errno.ECANCELED)
    assert.re_match(err, expected_msg)
    assert.is_nil(timeout)
    assert.is_nil(sec_left)
end

-- Helper function to assert timeout state
local function assert_timed_out(ctx, expected_msg)
    local done, err, timeout, sec_left = ctx:check()
    assert.is_true(done)
    assert.equal(err.type, errno.ETIMEDOUT)
    assert.re_match(err, expected_msg)
    assert.is_true(timeout)
    assert.is_nil(sec_left)
end

-- Helper function to create parent-child canceler pairs
local function create_parent_child(parent_timeout, child_timeout, parent_msg,
                                   child_msg)
    local parent_ctx, parent_cancel = canceler(parent_msg or 'parent',
                                               parent_timeout)
    local child_ctx, child_cancel = canceler(child_msg or 'child',
                                             child_timeout, parent_ctx)
    return {
        parent_ctx,
        parent_cancel,
    }, {
        child_ctx,
        child_cancel,
    }
end

function testcase.create_canceler()
    -- test that create new canceler
    local ctx, cancel = canceler('test cancel')
    assert.match(ctx, '^canceler: ', false)
    assert.is_func(cancel)

    -- test that throws an error if cause is not string
    local err = assert.throws(canceler, 123)
    assert.match(err, 'cause must be string')
end

function testcase.call_cancel_function()
    -- test that create new canceler
    local ctx, cancel = canceler('test cancel')

    -- test that check() return false if not cancelled
    local done, err, timeout, sec_left = ctx:check()
    assert_not_done(done, err, timeout)
    assert.is_nil(sec_left)

    -- test that check return true and ECANCELED if cancel function is called
    cancel()
    assert_canceled(ctx, 'test cancel')

    -- test that call cancel function with custom message
    ctx, cancel = canceler('test cancel with msg')
    cancel('custom cancel message')
    assert_canceled(ctx, 'custom cancel message')

    -- test that throws an error if cancel message is not string
    err = assert.throws(cancel, 123)
    assert.match(err, 'msg must be string')
end

function testcase.create_canceler_with_timeout()
    -- test that create new canceler with timeout_sec
    local ctx, cancel = assert(canceler('test', 0.1))
    assert.match(ctx, '^canceler: ', false)
    assert.is_func(cancel)

    -- test that check() return false if not cancelled or timed out
    local done, err, timeout, sec_left = ctx:check()
    assert_not_done(done, err, timeout)
    assert.less(sec_left, 0.1)
    assert.greater(sec_left, 0)

    -- test that check() return true and ETIMEDOUT after timeout duration
    sleep(0.2)
    assert_timed_out(ctx, 'test')

    -- test that create new canceler with already timed out
    ctx, cancel = canceler('test timeout', -1)
    assert.match(ctx, '^canceler: ', false)
    assert.is_func(cancel)
    assert_timed_out(ctx, 'test timeout')

    -- test that throws an error if timeout_sec is not finite number
    err = assert.throws(canceler, 'test', 0 / 0)
    assert.match(err, 'timeout must be finite number')
end

function testcase.create_canceler_with_parent()
    -- test that create new canceler with parent
    local parent, child = create_parent_child(nil, nil, 'parent canceler',
                                              'child canceler')
    local _, pcancel = unpack(parent)
    local child_ctx, _ = unpack(child)

    -- test that parent cancellation will be propagated to child
    assert.is_nil(pcancel())
    assert_canceled(child_ctx, 'parent canceler')

    -- test that child cancellation will not affect parent
    parent, child = create_parent_child(nil, nil, 'parent canceler 2',
                                        'child canceler 2')
    local parent_ctx2, _ = unpack(parent)
    child_ctx = child[1]
    local _, ccancel2 = unpack(child)
    assert.is_nil(ccancel2())
    assert_canceled(child_ctx, 'child canceler 2')

    -- check parent remains not done
    local done, err, timeout = parent_ctx2:check()
    assert_not_done(done, err, timeout)

    -- test that throws an error if parent is not instance of canceler
    err = assert.throws(canceler, 'test', nil, {})
    assert.match(err, 'parent must be instance of canceler')
end

function testcase.create_canceler_with_timeout_and_parent()
    -- test that parent timeout will be propagated to child
    local _, child = create_parent_child(0.1, 1, 'parent canceler',
                                         'child canceler')
    local child_ctx = child[1]
    sleep(0.2)
    assert_timed_out(child_ctx, 'parent canceler')

    -- test that child timeout will not affect parent
    local parent
    parent, child = create_parent_child(1, 0.1, 'parent canceler',
                                        'child canceler')
    local parent_ctx = parent[1]
    child_ctx = child[1]
    sleep(0.2)
    assert_timed_out(child_ctx, 'child canceler')

    -- check parent remains not done with time left
    local done, err, timeout, sec_left = parent_ctx:check()
    assert_not_done(done, err, timeout)
    assert.less(sec_left, 1)
end

function testcase.check_time_calculation()
    -- test check() returns correct time_left when parent has shorter timeout
    local _, child = create_parent_child(0.1, 0.5, 'parent timeout',
                                         'child timeout')
    local child_ctx = child[1]

    -- check() should return parent's shorter time
    local done, err, timeout, sec_left = child_ctx:check()
    assert_not_done(done, err, timeout)
    assert.less(sec_left, 0.1)
    assert.greater(sec_left, 0)

    -- test that check() returns child's timeout when it's shorter
    local _, child2 = create_parent_child(0.5, 0.1, 'parent timeout', 'child timeout')
    child_ctx = child2[1]
    done, err, timeout, sec_left = child_ctx:check()
    assert_not_done(done, err, timeout)
    assert.less(sec_left, 0.1)
    assert.greater(sec_left, 0)

    -- test child with timeout and no parent timeout
    local _, child_timeout = create_parent_child(nil, 0.1, 'parent none',
                                                 'child timeout')
    done, err, timeout, sec_left = child_timeout[1]:check()
    assert_not_done(done, err, timeout)
    assert.less(sec_left, 0.1)
    assert.greater(sec_left, 0)

    -- test check() returns parent's time when child has no timeout
    local _, child3 = create_parent_child(0.1, nil, 'parent timeout', 'child none')
    child_ctx = child3[1]
    done, err, timeout, sec_left = child_ctx:check()
    assert_not_done(done, err, timeout)
    assert.less(sec_left, 0.1)
    assert.greater(sec_left, 0)
end

function testcase.immediate_timeout_coverage()
    -- test that create canceler with immediate timeout works
    local ctx = canceler('immediate timeout', -0.001)
    assert_timed_out(ctx, 'immediate timeout')
end

for k, f in pairs(testcase) do
    local ok, err = xpcall(f, debug.traceback)
    if ok then
        print(k .. ': ok')
    else
        print(k .. ': failed')
        print(err)
    end
end

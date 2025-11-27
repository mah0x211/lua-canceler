# lua-canceler

[![test](https://github.com/mah0x211/lua-canceler/actions/workflows/test.yml/badge.svg)](https://github.com/mah0x211/lua-canceler/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/mah0x211/lua-canceler/branch/master/graph/badge.svg)](https://codecov.io/gh/mah0x211/lua-canceler)

The canceler module provides golang-like canceler functionality.


## Installation

```
luarocks install canceler
```


## Usage

```lua
local canceler = require('canceler')

local function busyfunc(ctx)
    while true do
        --
        -- do something
        --

        local done, err, timeout, sec_left = ctx:check()
        if done then
            -- canceled or timed out
            return done, err, timeout
        elseif sec_left then
            -- still working, sec_left indicates time left until timeout
            print('time left:', sec_left)
        end
    end
end

-- create new canceler with timeout duration 100ms.
local ctx, cancel = canceler('example cancel', 0.1)
local done, err, timeout, sec_left = busyfunc(ctx)
print(done, err) -- true ...: [ETIMEDOUT:60][canceler] Operation timed out
print(timeout) -- true
```

## Error Handling

the functions return the error object created by https://github.com/mah0x211/lua-errno module.


## ctx, cancel = canceler( cause [, timeout_sec [, parent]] )

create new canceler.

**Parameters**

- `cause:string`: a cancellation cause.
- `timeout_sec:number`: specify a timeout duration in seconds as number.
  - If `> 0`: sets a timeout that will trigger after the specified duration.
  - If `<= 0`: the canceler will be in timeout state immediately.
  - If `nil`: no timeout is set (manual cancellation only).
- `parent:canceler`: a parent canceler. Child cancelers will be canceled when their parent is canceled.

**Returns**

- `ctx:canceler`: an instance of canceler.
- `cancel:fun(cause:string?)`: cancel function. if this function is called, the `canceler:check()` method will return `true`.
    - `cause:string`: optional cancellation cause. if not specified, the cause specified when creating the canceler will be used.




## done, err, timeout, sec_left = canceler:check()

detects whether a canceler is done and provides the current state information.

**Returns**

- `done:boolean`: `true` if the canceler is canceled or timed out, `false` otherwise.
- `err:error`: if `done` is `true`, err will be one of the following values:
  - `errno.ECANCELED`: the canceler was canceled by the cancel function.
  - `errno.ETIMEDOUT`: the specified timeout duration has elapsed.
  - If `done` is `false`, this will be `nil`.
- `timeout:boolean`: `true` if the canceler is timed out, `false` or `nil` otherwise.
- `sec_left:number|nil`: the remaining time until the canceler is timed out.
  - If the canceler has a timeout and is not done: returns the minimum time left considering parent timeouts.
  - If the canceler is timed out: returns `nil`.
  - If no timeout is set and no parent has a timeout: returns `nil`.


## Examples

### Basic Usage with Timeout

```lua
local canceler = require('canceler')

-- Create a canceler with 2-second timeout
local ctx, cancel = canceler('operation timeout', 2)

-- Simulate work
local start_time = os.time()
while os.time() - start_time < 3 do
    local done, err, timeout, sec_left = ctx:check()
    if done then
        print('Operation canceled:', err)
        break
    end
    print('Working... time left:', sec_left)
    -- do some work
end
```

### Parent-Child Canceler Relationship

```lua
local canceler = require('canceler')

-- Create parent canceler with 1-second timeout
local parent_ctx, parent_cancel = canceler('parent operation', 1)

-- Create child canceler with 2-second timeout (will use parent's shorter timeout)
local child_ctx, child_cancel = canceler('child operation', 2, parent_ctx)

-- Child will timeout after 1 second due to parent's shorter timeout
local done, err, timeout, sec_left = child_ctx:check()
print('Time left from child:', sec_left) -- Will be <= 1.0

-- Cancel parent (will also cancel child)
parent_cancel('parent was canceled')
local done, err = child_ctx:check()
print('Child canceled:', done, err) -- true, ECANCELED
```

### Manual Cancellation

```lua
local canceler = require('canceler')

-- Create canceler without timeout (manual only)
local ctx, cancel = canceler('manual operation')

-- In another part of your code (e.g., signal handler)
cancel('user requested cancellation')

-- Check for cancellation
local done, err = ctx:check()
if done then
    print('Operation was canceled:', err)
end
```


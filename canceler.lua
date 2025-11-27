--
-- Copyright (C) 2025 Masatoshi Fukunaga
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
local type = type
local new_errno = require('errno').new
local new_metamodule = require('metamodule').new
local instanceof = require('metamodule').instanceof

--- @class time.clock.deadline
--- @field time fun():number
--- @field remain fun():number

--- @type fun(duration?: number):(d:time.clock.deadline, sec:number)
local new_deadline = require('time.clock.deadline').new

--- constants
local INF_POS = math.huge
local INF_NEG = -math.huge

--- is_finite returns true if x is finite number
--- @param x number
--- @return boolean
local function is_finite(x)
    return type(x) == 'number' and (x < INF_POS and x > INF_NEG)
end

--- @class canceler
--- @field parent canceler?
--- @field done boolean
--- @field err any
--- @field timedout boolean?
--- @field cause string?
--- @field deadl? time.clock.deadline
local Canceler = {}

--- creates a new canceler context
--- @param cause string cancellation cause
--- @param timeout_sec number? timeout in seconds
--- @param parent canceler? parent canceler context
--- @return canceler cancelctx
--- @return fun(cause:string?) cancelfn
function Canceler:init(cause, timeout_sec, parent)
    self.parent = parent
    self.cause = cause
    self.done = false
    self.err = nil
    self.timedout = nil

    if type(cause) ~= 'string' then
        error('cause must be string', 3)
    end

    if timeout_sec ~= nil then
        if not is_finite(timeout_sec) then
            error('timeout must be finite number', 3)
        elseif timeout_sec > 0 then
            -- set deadline
            self.deadl = new_deadline(timeout_sec)
        else
            -- already timed out
            self.done = true
            self.err = new_errno('ETIMEDOUT', cause, 'canceler')
            self.timedout = true
        end
    end

    if parent ~= nil and not instanceof(parent, 'canceler') then
        error('parent must be instance of canceler', 3)
    end

    local ctx = self
    return self, function(msg)
        assert(msg == nil or type(msg) == 'string', 'msg must be string')
        if not ctx.done then
            ctx.done = true
            -- set cancellation error with msg or cause
            ctx.err = new_errno('ECANCELED', msg or ctx.cause, 'canceler')
        end
    end
end


--- check if canceled or timed out
--- @return boolean done
--- @return any err
--- @return boolean? timedout
--- @return number? sec_left
function Canceler:check()
    if self.done then
        -- already done
        return true, self.err, self.timedout
    end

    local sec
    if self.deadl then
        sec = self.deadl:remain()
        if sec <= 0 then
            -- timeout occurred
            self.done = true
            self.err = new_errno('ETIMEDOUT', self.cause, 'canceler')
            self.timedout = true
            return true, self.err, true
        end
    end

    if self.parent then
        -- check parent and cache result
        local psec
        self.done, self.err, self.timedout, psec = self.parent:check()
        if self.done then
            return true, self.err, self.timedout
        elseif not sec then
            -- use parent's time left
            sec = psec
        elseif psec then
            -- use the minimum time left
            sec = sec < psec and sec or psec
        end
    end

    return false, nil, nil, sec
end

Canceler = new_metamodule(Canceler)
return Canceler


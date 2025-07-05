local async = {}

--- Create a new Promise
---@param executor function
function async.promise(executor)
	local resolve, reject
	local result, err
	local status = "pending"
	local fulfilled_callbacks = {}
	local rejected_callbacks = {}

	local function call_callbacks(callbacks, value)
		for _, cb in ipairs(callbacks) do
			cb(value)
		end
	end

	resolve = function(value)
		if status ~= "pending" then
			return
		end
		status = "fulfilled"
		result = value
		call_callbacks(fulfilled_callbacks, value)
	end

	reject = function(reason)
		if status ~= "pending" then
			return
		end
		status = "rejected"
		err = reason
		call_callbacks(rejected_callbacks, reason)
	end

	local ok, exec_err = pcall(function()
		executor(resolve, reject)
	end)

	if not ok then
		reject(exec_err)
	end

	return {
		then_ = function(self, on_fulfilled)
			if status == "fulfilled" then
				on_fulfilled(result)
			elseif status == "pending" then
				table.insert(fulfilled_callbacks, on_fulfilled)
			end
			return self
		end,

		catch_ = function(self, on_rejected)
			if status == "rejected" then
				on_rejected(err)
			elseif status == "pending" then
				table.insert(rejected_callbacks, on_rejected)
			end
			return self
		end,

		await = function(self)
			local co = coroutine.running()
			if not co then
				error("await must be called inside a coroutine")
			end
			self:then_(function(val)
				coroutine.resume(co, val)
			end):catch_(function(e)
				error(e)
			end)
			return coroutine.yield()
		end,
	}
end

-- Wraps a function that uses a callback into a promise
function async.wrap(fn)
	return function(...)
		local args = { ... }
		return async.promise(function(resolve, reject)
			local ok, err = pcall(function()
				fn(unpack(args), function(result)
					resolve(result)
				end)
			end)
			if not ok then
				reject(err)
			end
		end)
	end
end

-- Run a coroutine-based async function
function async.run(fn)
	coroutine.wrap(fn)()
end

return async

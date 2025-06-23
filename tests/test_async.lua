local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local async = require("org_markdown.async")

-- A fake async function that resolves after a short delay
local function fake_callback(value, cb)
	vim.defer_fn(function()
		cb(value)
	end, 50)
end

T["async.wrap returns awaited result"] = function()
	async.run(function()
		local wrapped = async.wrap(fake_callback)
		local result = wrapped("hello"):await()
		MiniTest.expect.equality(result, "hello")
	end)
end

T["async.await works inside async.run"] = function()
	async.run(function()
		local wrapped = async.wrap(function(cb)
			vim.defer_fn(function()
				cb(42)
			end, 30)
		end)

		local val = wrapped():await()
		MiniTest.expect.equality(val, 42)
	end)
end

T["async.promise .then_ is called"] = function()
	local called = false

	local p = async.promise(function(resolve, _)
		vim.defer_fn(function()
			resolve("done")
		end, 10)
	end)

	p:then_(function(res)
		called = true
		MiniTest.expect.equality(res, "done")
	end)

	vim.defer_fn(function()
		MiniTest.expect.equality(called, true)
	end, 100)
end

T["async.promise .catch_ is called on error"] = function()
	local p = async.promise(function(_, reject)
		reject("fail")
	end)

	p:catch_(function(err)
		MiniTest.expect.equality(err, "fail")
	end)
end

T["async.await waits before continuing iteration"] = function()
	async.run(function()
		local values = { 3, 2, 1 }
		local results = {}

		local wrapped = async.wrap(function(i, cb)
			-- Simulate longer wait for earlier (larger) values
			vim.defer_fn(function()
				cb(i * 100)
			end, i * 20) -- i=3 waits 60ms, i=2 waits 40ms, etc.
		end)

		for _, v in ipairs(values) do
			local result = wrapped(v):await()
			table.insert(results, result)
		end

		-- Ensure the results match the iteration order, not return timing
		MiniTest.expect.equality(results, { 300, 200, 100 })
	end)
end

return T

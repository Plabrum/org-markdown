# Run all # Run all tests using tests/init.lua
test:
	nvim --headless -u tests/init.lua

# Run test from specific file, passed in as FILE=tests/test_parser.lua
test_file:
	nvim --headless -u tests/init.lua -c "luafile $(FILE)" -c "lua require('mini.test').run()" -c "q"

local luau = require("@lune/luau"); local fs = require("@lune/fs"); local process = require("@lune/process")
local bad = 0
for _, path in process.args do
	local ok, err = pcall(luau.compile, fs.readFile(path))
	print(ok and "OK  " or "ERR ", path, ok and "" or tostring(err))
	if not ok then bad += 1 end
end
process.exit(bad)

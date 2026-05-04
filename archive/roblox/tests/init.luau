--!strict
-- Test runner. Run with `lune run tests` from the repo root.
-- Each spec module returns an ordered list of { name, fn } pairs; the
-- runner pcall's each fn and prints a per-spec, per-case summary, then
-- exits non-zero if any case failed.

local process = require("@lune/process")

type TestCase = { [number]: any }
type Spec = { name: string, cases: { TestCase } }

local specs: { Spec } = {
	{ name = "RunState", cases = require("./RunState.spec") },
	{ name = "WaveDirector", cases = require("./WaveDirector.spec") },
	{ name = "WaveDirector partial lobby", cases = require("./WaveDirectorPartialLobby.spec") },
	{ name = "Combat registry", cases = require("./Combat.spec") },
}

local total = 0
local failed = 0
local failures: { string } = {}

for _, spec in ipairs(specs) do
	print("[" .. spec.name .. "]")
	for _, case in ipairs(spec.cases) do
		local caseName: string = case[1]
		local caseFn: () -> () = case[2]
		total += 1
		local ok, err = pcall(caseFn)
		if ok then
			print("  PASS  " .. caseName)
		else
			failed += 1
			print("  FAIL  " .. caseName)
			print("        " .. tostring(err))
			table.insert(failures, spec.name .. " > " .. caseName)
		end
	end
end

print("")
print(string.format("%d passed, %d failed (of %d total)", total - failed, failed, total))

if failed > 0 then
	for _, line in ipairs(failures) do
		print("  FAIL: " .. line)
	end
	process.exit(1)
end

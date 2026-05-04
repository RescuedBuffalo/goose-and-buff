--!strict
-- Tiny assertion helpers. Failures throw with a useful message so the
-- runner's pcall catches them and reports per-test.

local expect = {}

function expect.eq(actual: any, want: any, label: string?)
	if actual ~= want then
		error(
			string.format(
				"%sexpected %s, got %s",
				if label then label .. ": " else "",
				tostring(want),
				tostring(actual)
			),
			2
		)
	end
end

function expect.truthy(value: any, label: string?)
	if not value then
		error(
			string.format("%sexpected truthy, got %s", if label then label .. ": " else "", tostring(value)),
			2
		)
	end
end

function expect.falsy(value: any, label: string?)
	if value then
		error(
			string.format("%sexpected falsy, got %s", if label then label .. ": " else "", tostring(value)),
			2
		)
	end
end

function expect.nilish(value: any, label: string?)
	if value ~= nil then
		error(
			string.format("%sexpected nil, got %s", if label then label .. ": " else "", tostring(value)),
			2
		)
	end
end

function expect.notNil(value: any, label: string?)
	if value == nil then
		error(string.format("%sexpected non-nil", if label then label .. ": " else ""), 2)
	end
end

function expect.deepEq(actual: any, want: any, label: string?)
	local function eq(a: any, b: any): boolean
		if a == b then
			return true
		end
		if type(a) ~= "table" or type(b) ~= "table" then
			return false
		end
		for k, v in pairs(a) do
			if not eq(v, b[k]) then
				return false
			end
		end
		for k in pairs(b) do
			if a[k] == nil then
				return false
			end
		end
		return true
	end

	if not eq(actual, want) then
		local function show(t: any): string
			if type(t) ~= "table" then
				return tostring(t)
			end
			local parts = {}
			for k, v in pairs(t) do
				table.insert(parts, tostring(k) .. "=" .. show(v))
			end
			return "{" .. table.concat(parts, ", ") .. "}"
		end
		error(
			string.format(
				"%sexpected %s, got %s",
				if label then label .. ": " else "",
				show(want),
				show(actual)
			),
			2
		)
	end
end

return expect

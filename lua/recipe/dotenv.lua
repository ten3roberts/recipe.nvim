local M = {}
local util = require("recipe.util")

local keywords = { export = "export" }

---@class Token
---@field data string
---@field kind string
---@field is_str string|nil

---@param data string
---@param _ Token|nil
---@return Token|nil
---@return string|nil
local function tok_keyword(data, _)
	local start, stop = string.find(data, "^%w+")
	if start == nil then
		return nil, nil
	end

	local head = string.sub(data, start, stop)
	local tail = string.sub(data, stop + 1)

	local keyword = keywords[head]
	if keyword then
		return { data = keyword, kind = "keyword" }, tail
	end

	return nil
end

---@param data string
---@return Token|nil
---@return string|nil
local function tok_ident(data, _)
	local start, stop = string.find(data, "^[a-zA-Z0-9_]+")
	if start == nil then
		return nil, nil
	end

	local head = string.sub(data, start, stop)
	local tail = string.sub(data, stop + 1)

	return { data = head, kind = "ident" }, tail
end

local function tok_comment(data, _)
	local start, stop = string.find(data, "^#[^\n]*")
	if start == nil then
		return nil, nil
	end

	local head = string.sub(data, start, stop)
	local tail = string.sub(data, stop + 1)

	return { data = head, kind = "comment" }, tail
end

local symbols = { ["="] = "=" }
local function tok_symbol(data, _)
	local sym = symbols[data:sub(1, 1)]
	if sym then
		return { data = sym, kind = "symbol" }, data:sub(2)
	end
end

local whitespace = { [" "] = " ", ["\n"] = "\n", ["\t"] = "\t" }
local function tok_whitespace(data, _)
	local ws = whitespace[data:sub(1, 1)]
	if ws then
		return { data = ws, kind = "whitespace" }, data:sub(2)
	end
end

local function tok_string_start(data, prev)
	if not prev.is_str then
		if data:sub(1, 3) == '"""' then
			return { data = '"""', kind = "string_start", is_str = '"""' }, data:sub(4)
		elseif data:sub(1, 1) == '"' then
			return { data = '"', kind = "string_start", is_str = '"' }, data:sub(2)
		elseif data:sub(1, 1) == "'" then
			return { data = "'", kind = "string_start", is_str = "'" }, data:sub(2)
		end
	end
end

local function tok_string_end(data, prev)
	if prev.is_str and data:sub(1, #prev.is_str) == prev.is_str then
		return { data = prev.is_str, kind = "string_end" }, data:sub(1 + #prev.is_str)
	end
end

---@param data string
---@return Token|nil
---@return string|nil
local function tok_string(data, prev)
	if not prev.is_str then
		return
	end

	local s = {}

	local in_escape = false

	local consumed = 0
	for i = 1, #data do
		consumed = consumed + 1
		local c = data:sub(i, i)

		if in_escape then
			if c == "n" then
				s[#s + 1] = "\n"
			elseif c == '"' then
				s[#s + 1] = '"'
			elseif c == "'" then
				s[#s + 1] = "'"
			else
				return util.log_error("unknown escape: " .. c)
			end
			in_escape = false
		elseif c == "\\" then
			in_escape = true
		elseif c == prev.is_str then
			break
		else
			s[#s + 1] = c
		end
	end

	local tail = string.sub(data, consumed)

	return { data = table.concat(s), kind = "string", is_str = prev.is_str }, tail
end

local tokenizers = {
	tok_string_start,
	tok_string_end,
	tok_string,
	tok_symbol,
	tok_keyword,
	tok_ident,
	tok_string,
	tok_whitespace,
	tok_comment,
}

---@return table|nil
---@return string|nil
local function tok_next(data, prev)
	for _, tok in ipairs(tokenizers) do
		local token, tail = tok(data, prev)
		if token then
			return token, tail
		end
	end
end

---@class Parser
---@field pos number
---@field take fun(self: Parser): Token
---@field peek fun(self: Parser): Token
---@field tokens Token[]

---@param data string
---@return Token
local function tokenize(data)
	local tokens = {}
	local prev = { data = "", kind = "whitespace" }
	local i = 0

	while #data > 0 and i < 100 do
		local token, tail = tok_next(data, prev)
		if not token or not tail then
			util.log_error("Failed to parse dotenv. Unexpected near: " .. data:sub(1, math.min(#data, 16)))
			return {}
		end

		prev = token
		tokens[#tokens + 1] = token

		i = i + 1
		data = tail
	end

	return tokens
end

---@param parser Parser
local function parse_string(parser)
	if parser:peek().kind ~= "string" then
		return util.log_error('Expected string after "')
	end

	local s = ""
	while true do
		local part = parser:take()
		if part.kind == "string_end" then
			break
		end

		s = s .. part.data
	end

	return s
end
---@param parser Parser
local function parse_value(parser)
	local tok = parser:peek()
	if tok.kind == "string_start" then
		parser:take()
		return parse_string(parser)
	elseif tok.kind == "ident" then
		parser:take()
		return tok.data
	else
		return util.log_error("Failed to parse dotenv. Expected string after key")
	end
end

---@param parser Parser
local function parse_var(parser)
	if parser:peek().kind ~= "ident" then
		util.log_error("Expected ident")
		return
	end

	local key = parser:take().data

	local eq = parser:take()
	if eq.kind ~= "symbol" and eq.data == "=" then
		return util.log_error("Expected equal after ident")
	end

	local value = parse_value(parser)
	return { key = key, value = value }
end

---@type Token
local EOF = {
	data = "",
	kind = "eof",
}

---@param tokens Token[]
local function parse(tokens)
	---@type Parser
	local parser = {
		tokens = tokens,
		pos = 1,
	}

	function parser:take()
		local tok = self.tokens[self.pos] or EOF
		self.pos = self.pos + 1
		return tok
	end

	function parser:peek()
		local tok = self.tokens[self.pos] or EOF
		return tok
	end

	local variables = {}

	while true do
		local tok = parser:peek()
		if tok.kind == "ident" then
			local var = parse_var(parser)
			if not var then
				break
			end

			variables[var.key] = var.value
		elseif tok.kind == "eof" then
			break
		elseif tok.kind == "keyword" or tok.kind == "whitespace" or tok.kind == "comment" then
			parser:take()
		else
			util.log_error("Unexpected token: " .. vim.inspect(tok))
			return
		end
	end

	return variables
end

local memo = util.memoize_files(vim.secure.read)

--- Loads an environment file, by default .env
---@async
---@param path string
---@return table<string, string>, boolean
function M.load(path)
	return memo(path or ".env", function(data)
		if not data then
			return {}
		end

		local tokens = tokenize(data)
		if not tokens then
			util.log_error("Failed to tokenize dotenv")
			return {}
		end

		local env = parse(tokens)
		if not env then
			util.log_error("Failed to load env from " .. path)
			return {}
		end

		local t = {}
		for key, value in pairs(env) do
			t[#t + 1] = key .. "=" .. value
		end

		vim.notify("Loaded env:\n" .. table.concat(t, "\n"))
		return env
	end)
end

function M.test()
	local async = require("plenary.async")
	local _ = async.util.block_on(function()
		return M.load("./.env")
	end)

	local env, loaded = async.util.block_on(function()
		return M.load("./.env")
	end)

	assert(not loaded, "Env should be cached")
	print("Env: ", vim.inspect(env))

	assert(env.TEST == "foo", vim.inspect(env))
	assert(env.NUMBER == "\nFor'\"")
end

return M

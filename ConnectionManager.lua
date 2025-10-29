local ConnectionManager = {}
ConnectionManager.__index = ConnectionManager

local function is_rbx_connection(obj)
	return typeof(obj) == "RBXScriptConnection"
end

local function is_connectable(obj)
	if typeof(obj) == "RBXScriptSignal" then
		return true
	end
	local t = type(obj)
	if t == "table" or t == "userdata" then
		return type(obj.Connect) == "function"
	end
	return false
end

local function is_callable(fn)
	return type(fn) == "function"
end

function ConnectionManager.new()
	return setmetatable({
		_items = {},
		_nameIndex = {},
	}, ConnectionManager)
end

function ConnectionManager:_registerName(name, entry)
	if not name or not entry then return end
	local list = self._nameIndex[name]
	if not list then
		self._nameIndex[name] = { entry }
	else
		table.insert(list, entry)
	end
end

function ConnectionManager:_unregisterName(name, entry)
	if not name or not entry then return end
	local list = self._nameIndex[name]
	if not list then return end
	for i = #list, 1, -1 do
		if list[i] == entry then
			table.remove(list, i)
			break
		end
	end
	if #list == 0 then
		self._nameIndex[name] = nil
	end
end

function ConnectionManager:Add(item, name)
	if item == nil then return nil end

	local entryType
	if is_rbx_connection(item) then
		entryType = "conn"
	elseif is_callable(item) then
		entryType = "fn"
	else
		return nil
	end

	local entry = { type = entryType, ref = item, name = name }
	table.insert(self._items, entry)
	self:_registerName(name, entry)

	return item
end

function ConnectionManager:Connect(event, fn, name)
	if not is_callable(fn) or not is_connectable(event) then return nil end

	local conn = event:Connect(fn)
	if not is_rbx_connection(conn) then return nil end

	local entry = { type = "conn", ref = conn, name = name }
	table.insert(self._items, entry)
	self:_registerName(name, entry)

	return conn
end

function ConnectionManager:_findIndexForRef(ref)
	for i, v in ipairs(self._items) do
		if v.ref == ref then
			return i
		end
	end
	return nil
end

function ConnectionManager:_disconnectEntry(entry, idx)
	if not entry then return end

	if entry.type == "conn" then
		if is_rbx_connection(entry.ref) and entry.ref.Connected ~= false then
			entry.ref:Disconnect()
		end
	elseif entry.type == "fn" then
		if is_callable(entry.ref) then
			entry.ref()
		end
	end

	self:_unregisterName(entry.name, entry)
	if idx then
		table.remove(self._items, idx)
	end
end

function ConnectionManager:Remove(identifier)
	if identifier == nil then return false end

	if type(identifier) == "number" then
		local entry = self._items[identifier]
		if not entry then return false end
		self:_disconnectEntry(entry, identifier)
		return true
	end

	if type(identifier) == "string" then
		self:DisconnectByName(identifier)
		return true
	end

	local idx = self:_findIndexForRef(identifier)
	if idx then
		self:_disconnectEntry(self._items[idx], idx)
		return true
	end

	return false
end

function ConnectionManager:DisconnectAll()
	for i = #self._items, 1, -1 do
		self:_disconnectEntry(self._items[i], i)
	end
	self._nameIndex = {}
end

function ConnectionManager:DisconnectByName(name)
	if not name then return end
	local list = self._nameIndex[name]
	if not list then return end

	local copy = {}
	for i = 1, #list do copy[i] = list[i] end

	for _, entry in ipairs(copy) do
		local idx = self:_findIndexForRef(entry.ref)
		self:_disconnectEntry(entry, idx)
	end
end

function ConnectionManager:CallAllFns(...)
	for _, v in ipairs(self._items) do
		if v.type == "fn" and is_callable(v.ref) then
			v.ref(...)
		end
	end
end

function ConnectionManager:List()
	local out = {}
	for i, v in ipairs(self._items) do
		table.insert(out, { i = i, type = v.type, name = v.name, ref = v.ref })
	end
	return out
end

function ConnectionManager:Count()
	return #self._items
end

function ConnectionManager:GetByName(name)
	local list = self._nameIndex[name]
	if not list then return {} end
	local out = {}
	for i = 1, #list do out[i] = list[i] end
	return out
end

function ConnectionManager:Destroy()
	if not self._items then return end
	self:DisconnectAll()
	self._items, self._nameIndex = nil, nil
	setmetatable(self, nil)
end

function ConnectionManager:__tostring()
	return ("ConnectionManager[%d items]"):format(self._items and #self._items or 0)
end

return ConnectionManager

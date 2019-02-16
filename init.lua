-- @name            Ambassador Library
-- @author          brianush1
-- @description     A library that allows for easy communication between client and server
-- @version         0.08

--[[
	Changelog:
	
	0.08:
		- Fix several security vulnerabilities
		- Refactor several parts of the source code
			- Add Ambassador.DataReceived signal
				Server: Event Ambassador.DataReceived(Player player, string name, data)
				Client: Event Ambassador.DataReceived(string name, data)
			- Remove unnecessary encryption
			- Fix typo in "transmittion" to "transmission"

	0.07:
		- Critical bugfix

	0.06:
		- Allow passing instances

	0.05:
		- Fix a security vulnerability

	0.04:
		- Add basic encryption

	0.03:
		- Allow passing metatables

	0.02:
		- Fix bug of objects transmitted back and forth making new copies
		  e.g. object A transmitted Client -> Server -> Client != object A
]]

-- Signal library

function Signal()
	local this = {}

	local mBindableEvent = Instance.new('BindableEvent')
	local mAllCns = {} --all connection objects returned by mBindableEvent::connect

	--main functions
	function this:connect(func)
		if self ~= this then error("connect must be called with `:`, not `.`", 2) end
		if type(func) ~= 'function' then
			error("Argument #1 of connect must be a function, got a "..type(func), 2)
		end
		local pubCn = {}
		function pubCn:disconnect()
			mAllCns[pubCn] = nil
		end
		pubCn.Disconnect = pubCn.disconnect
		mAllCns[pubCn] = function(...)
			pcall(function(...) coroutine.wrap(func)(...) end, ...)
		end
		
		return pubCn
	end
	
	function this:disconnect()
		if self ~= this then error("disconnect must be called with `:`, not `.`", 2) end
		for cn, _ in pairs(mAllCns) do
			mAllCns[cn] = nil
		end
	end
	
	function this:wait()
		if self ~= this then error("wait must be called with `:`, not `.`", 2) end
		local bindable = Instance.new("BindableEvent")
		
		local len, data
		local cn = this:connect(function(...)
			len = select("#", ...)
			data = {...}
			bindable:Fire()
		end)
		
		bindable.Event:Wait()
		bindable:Destroy()
		
		if len ~= nil then
			return unpack(data, 1, len)
		else
			return
		end
	end
	
	this.Connect = this.connect
	this.Disconnect = this.disconnect
	this.Wait = this.wait

	return this, function(...)
		for cn, fn in pairs(mAllCns) do
			fn(...)
		end
	end
end

-- End Signal library

local Ambassador = {}

local IS_SERVER = game:GetService("RunService"):IsServer()

function getRemote(name)
	if IS_SERVER then
		local remote = game:GetService("ReplicatedStorage"):FindFirstChild("Ambassador/" .. name)

		if remote then return remote end

		remote = Instance.new("RemoteFunction")
		remote.Name = "Ambassador/" .. name
		remote.Parent = game:GetService("ReplicatedStorage")
		return remote
	else
		return game:GetService("ReplicatedStorage"):WaitForChild("Ambassador/" .. name)
	end
end

function onRemoteCall(name, func)
	local remote = getRemote(name)
	if IS_SERVER then
		remote.OnServerInvoke = func
	else
		remote.OnClientInvoke = func
	end
end

local objects = {}
local players = {}

function generateObjectId(object)
	if objects[object] then return objects[object] end

	local id = game:GetService("HttpService"):GenerateGUID()
	objects[id] = object
	objects[object] = id
	return id
end

function pack(...)
	return select("#", ...), {...}
end

local instanceIDs = {}

local dataReceivedSignal, fireDataReceived = Signal()
Ambassador.DataReceived = dataReceivedSignal

if IS_SERVER then

	function getId(instance)
		if instanceIDs[instance] then
			return instanceIDs[instance]
		else
			local id = game:GetService("HttpService"):GenerateGUID()
			instanceIDs[instance] = id
			instanceIDs[id] = instance
			return id
		end
	end

	onRemoteCall("Transmission", function(player, name, data)
		fireDataReceived(player, name, decodeTransmission(player, data))
	end)

	onRemoteCall("FunctionCall", function(player, id, data)
		local success, result = pcall(function()
			return encodeTransmission(player, objects[id](decodeTransmission(player, data)))
		end)

		if success then
			return result
		else
			warn("Error: " .. result)
			error("An error occurred on the server", 0)
		end
	end)

	onRemoteCall("GetID", function(player, instance)
		if typeof(instance) ~= "Instance" then return "" end
		return getId(instance)
	end)

	onRemoteCall("GetInstance", function(player, id)
		if type(id) ~= "string" then return "" end
		if instanceIDs[id] then
			return instanceIDs[id]
		else
			return nil
		end
	end)

else

	onRemoteCall("Transmission", function(name, data)
		fireDataReceived(name, decodeTransmission(nil, data))
	end)

	onRemoteCall("FunctionCall", function(id, data)
		return encodeTransmission(nil, objects[id](decodeTransmission(nil, data)))
	end)

end

function encode(player, ...)
	if select("#", ...) ~= 1 then
		local length = select("#", ...)
		local encoded = {}

		for i = 1, length do
			encoded[i] = encode(player, (select(i, ...)))
		end

		return {
			type = "vararg",
			length = length,
			value = encoded
		}
	end

	local data = ...
	local dataType = typeof(data)

	local result
	if dataType == "string" or dataType == "number" then
		result = data
	elseif dataType == "boolean" then
		result = {
			type = "bool",
			data = data and 1 or 0
		}
	elseif dataType == "nil" then
		result = {
			type = "nil"
		}
	elseif dataType == "table" then -- Metatable support is kind of iffy, cuz yielding in a metamethod can't happen
		-- Iffy meaning non-existent*
		local meta = getmetatable(data)

		if type(meta) ~= "table" and meta ~= nil then error("Cannot encode locked metatable", 0) end

		local encoded = {}

		for key, value in pairs(data) do
			encoded[encode(player, key)] = encode(player, value)
		end

		result = {
			type = meta and "metatable" or "regtable",
			id = generateObjectId(data),
			meta = meta and encode(player, meta),
			value = encoded
		}
	elseif dataType == "function" then
		result = {
			type = "function",
			id = generateObjectId(data)
		}
	elseif dataType == "EnumItem" then
		result = {
			type = "enum",
			enum = tostring(data.EnumType),
			name = data.Name
		}
	elseif dataType == "Instance" then
		local id
		
		if IS_SERVER then
			id = getId(data)
		else
			id = getRemote("GetID"):InvokeServer(data)
		end
		
		result = {
			type = "instance",
			id = id
		}
	end

	if data ~= nil and objects[data] then
		return {
			type = "remoteObject",
			id = objects[data],
			fallback = result
		}
	elseif result ~= nil then
		return result
	end

	error("Cannot encode '" .. dataType .. "'", 0)
end

function decode(player, data)
	local dataType = type(data)
	if dataType == "string" or dataType == "number" or dataType == "boolean" then
		return data
	elseif dataType == "table" then
		dataType = data.type

		if data.id and objects[data.id] then
			return objects[data.id]
		end

		if data.id then
			players[data.id] = player
		end

		if data.type == "remoteObject" then
			return decode(player, data.fallback)
		elseif dataType == "enum" then
			return Enum[data.enum][data.name]
		elseif dataType == "bool" then
			return data.data == 1
		elseif dataType == "nil" then
			return nil
		elseif dataType == "regtable" then
			local decoded = {}
	
			for key, value in pairs(data.value) do
				decoded[decode(player, key)] = decode(player, value)
			end
	
			local result = decoded

			objects[data.id] = result
			objects[result] = data.id

			return result
		elseif dataType == "metatable" then
			local meta = decode(player, data.meta)

			meta.__metatable = "The metatable is locked"

			local decoded = {}
	
			for key, value in pairs(data.value) do
				decoded[decode(player, key)] = decode(player, value)
			end

			local result = setmetatable(decoded, {
				__metatable = "The metatable is locked",
				__index = function(self, key)
					return meta.__index and meta:__index(key) or meta[key]
				end
			})

			objects[data.id] = result
			objects[result] = data.id

			return result
		elseif dataType == "vararg" then
			local decoded = {}

			for index, value in ipairs(data.value) do
				decoded[index] = decode(player, value)
			end

			return unpack(decoded, 1, data.length)
		elseif dataType == "function" then
			local result = function(...)
				if IS_SERVER then
					local player = players[data.id]
					return decodeTransmission(player, getRemote("FunctionCall"):InvokeClient(player, data.id, encodeTransmission(player, ...)))
				else
					return decodeTransmission(nil, getRemote("FunctionCall"):InvokeServer(data.id, encodeTransmission(nil, ...)))
				end
			end

			objects[data.id] = result
			objects[result] = data.id

			return result
		elseif dataType == "instance" then
			local instance
			
			if IS_SERVER then
				instance = instanceIDs[data.id or ""]
			else
				instance = getRemote("GetInstance"):InvokeServer(data.id)
			end
			
			return instance
		end
	end

	error("Cannot decode '" .. dataType .. "'", 0)
end

function encodeTransmission(to, ...)
	local length = select("#", ...)
	local encoded = {}

	for i = 1, length do
		encoded[i] = encode(to, (select(i, ...)))
	end

	return game:GetService("HttpService"):JSONEncode({
		type = "vararg",
		length = length,
		value = encoded
	})
end

function decodeTransmission(from, data)
	return decode(from, game:GetService("HttpService"):JSONDecode(data))
end

function Ambassador:Send(name, target, data)
	assert(not (IS_SERVER and not data), "Expected target for server ambassador")

	if IS_SERVER then
		assert(target.Parent, "Expected target to be in-game")
	else
		data = target
		target = game.Players.LocalPlayer
	end

	if IS_SERVER then
		getRemote("Transmission"):InvokeClient(target, name, encodeTransmission(target, data))
	else
		getRemote("Transmission"):InvokeServer(name, encodeTransmission(nil, data))
	end
end

function Ambassador:Await(name, target, timeout)
	assert(not (IS_SERVER and not target), "Expected target for client ambassador")

	if IS_SERVER then
		assert(target.Parent, "Expected target to be in-game")
	else
		timeout = target
		target = game.Players.LocalPlayer
	end

	timeout = timeout or 30
	
	-- this should be improved code-wise

	local len, resultData

	coroutine.wrap(function()
		wait(timeout)
		resultData = { false, "Timeout" }
		len = 2
	end)()

	coroutine.wrap(function()
		local hasResult, result
		repeat
			if IS_SERVER then
				local nextPlayer, nextName, nextData = dataReceivedSignal:Wait()
				if nextPlayer == target and nextName == name then
					result = nextData
					hasResult = true
				end
			else
				local nextName, nextData = dataReceivedSignal:Wait()
				if nextName == name then
					result = nextData
					hasResult = true
				end
			end

			wait() until hasResult or len
		resultData = { true, result }
		len = 2
	end)()
	
	repeat wait() until len ~= nil

	return unpack(resultData, 1, len)
end

function Ambassador:Receive(...)
	local success, ambassador = Ambassador:Await(...)
	assert(success, "Could not receive ambassador")
	return ambassador
end

if IS_SERVER then
	function Ambassador:Cleanup(player)
		local suffix = "/" .. player.Name
		for i, v in ipairs(game:GetService("ReplicatedStorage"):GetChildren()) do
			if v.Name:sub(#v.Name - #suffix + 1) == suffix then
				pcall(v.Destroy, v)
			end
		end
	end
end

return Ambassador

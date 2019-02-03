-- @name            Ambassador Library
-- @author          brianush1
-- @description     A library that allows for easy communication between client and server
-- @version         0.07

--[[
	Changelog:

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

local Ambassador = {}

local Server = game:GetService("RunService"):IsServer()

function getName(server, name, target)
	return (server and "Server" or "Client") .. "Ambassador/" .. name .. "/" .. target.Name
end

local InvokationType = {
	RequestAmbassador = 0
}

local key = "builtinAMQLFPXMFTWLkey"

--[[

Encryption/Decryption
By: NoliCAIKS
Source: https://wiki.roblox.com/index.php?title=User:NoliCAIKS/Code/Encryption

]]
function decrypt(cipher, key)
	local key_bytes
	if type(key) == "string" then
		key_bytes = {}
		for key_index = 1, #key do
			key_bytes[key_index] = string.byte(key, key_index)
		end
	else
		key_bytes = key
	end
	local cipher_raw_length = #cipher
	local key_length = #key_bytes
	local cipher_bytes = {}
	local cipher_length = 0
	local cipher_bytes_index = 1
	for byte_str in string.gmatch(cipher, "%x%x") do
		cipher_length = cipher_length + 1
		cipher_bytes[cipher_length] = tonumber(byte_str, 16)
	end
	local random_bytes = {}
	local random_seed = 0
	for key_index = 1, key_length do
		random_seed = (random_seed + key_bytes[key_index] * key_index) * 1103515245 + 12345
		random_seed = (random_seed - random_seed % 65536) / 65536 % 4294967296
	end
	for random_index = 1, (cipher_length - key_length + 1) * key_length do
		random_seed = (random_seed % 4194304 * 1103515245 + 12345)
		random_bytes[random_index] = (random_seed - random_seed % 65536) / 65536 % 256
	end
	local random_index = #random_bytes
	local last_key_byte = key_bytes[key_length]
	local result_bytes = {}
	for cipher_index = cipher_length, key_length, -1 do
		local result_byte = cipher_bytes[cipher_index] - last_key_byte
		if result_byte < 0 then
			result_byte = result_byte + 256
		end
		result_byte = result_byte - random_bytes[random_index]
		random_index = random_index - 1
		if result_byte < 0 then
			result_byte = result_byte + 256
		end
		for key_index = key_length - 1, 1, -1 do
			cipher_index = cipher_index - 1
			local cipher_byte = cipher_bytes[cipher_index] - key_bytes[key_index]
			if cipher_byte < 0 then
				cipher_byte = cipher_byte + 256
			end
			cipher_byte = cipher_byte - result_byte
			if cipher_byte < 0 then
				cipher_byte = cipher_byte + 256
			end
			cipher_byte = cipher_byte - random_bytes[random_index]
			random_index = random_index - 1
			if cipher_byte < 0 then
				cipher_byte = cipher_byte + 256
			end
			cipher_bytes[cipher_index] = cipher_byte
		end
		result_bytes[cipher_index] = result_byte
	end
	local result_characters = {}
	for result_index = 1, #result_bytes do
		result_characters[result_index] = string.char(result_bytes[result_index])
	end
	return table.concat(result_characters)
end

function encrypt(message, key)
	local key_bytes
	if type(key) == "string" then
		key_bytes = {}
		for key_index = 1, #key do
			key_bytes[key_index] = string.byte(key, key_index)
		end
	else
		key_bytes = key
	end
	local message_length = #message
	local key_length = #key_bytes
	local message_bytes = {}
	for message_index = 1, message_length do
		message_bytes[message_index] = string.byte(message, message_index)
	end
	local result_bytes = {}
	local random_seed = 0
	for key_index = 1, key_length do
		random_seed = (random_seed + key_bytes[key_index] * key_index) * 1103515245 + 12345
		random_seed = (random_seed - random_seed % 65536) / 65536 % 4294967296
	end
	for message_index = 1, message_length do
		local message_byte = message_bytes[message_index]
		for key_index = 1, key_length do
			local key_byte = key_bytes[key_index]
			local result_index = message_index + key_index - 1
			local result_byte = message_byte + (result_bytes[result_index] or 0)
			if result_byte > 255 then
				result_byte = result_byte - 256
			end
			result_byte = result_byte + key_byte
			if result_byte > 255 then
				result_byte = result_byte - 256
			end
			random_seed = (random_seed % 4194304 * 1103515245 + 12345)
			result_byte = result_byte + (random_seed - random_seed % 65536) / 65536 % 256
			if result_byte > 255 then
				result_byte = result_byte - 256
			end
			result_bytes[result_index] = result_byte
		end
	end
	local result_buffer = {}
	local result_buffer_index = 1
	for result_index = 1, #result_bytes do
		local result_byte = result_bytes[result_index]
		result_buffer[result_buffer_index] = string.format("%02x", result_byte)
		result_buffer_index = result_buffer_index + 1
	end
	return table.concat(result_buffer)
end

function createRemote(name)
	if Server then
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = game:GetService("ReplicatedStorage")
		return remote
	else
		return game:GetService("ReplicatedStorage"):WaitForChild("Ambassador/RemoteRequestHandler"):InvokeServer(name)
	end
end

function getRemote(name)
	if Server then
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

function remoteInvokeHandler(name, func)
	local remote = getRemote(name)
	if Server then
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

if Server then

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

	remoteInvokeHandler("RemoteRequestHandler", function(player, name)
		return createRemote(name)
	end)

	remoteInvokeHandler("FunctionCall", function(player, id, data)
		local success, result = pcall(function()
			return encodeTransmittion(player, objects[id](decodeTransmittion(player, data)))
		end)

		if success then
			return result
		else
			warn("Error: " .. result)
			error("An error occurred on the server", 0)
		end
	end)

	remoteInvokeHandler("GetID", function(player, instance)
		if typeof(instance) ~= "Instance" then return "" end
		return getId(instance)
	end)

	remoteInvokeHandler("GetInstance", function(player, id)
		if type(id) ~= "string" then return "" end
		if instanceIDs[id] then
			return instanceIDs[id]
		else
			return nil
		end
	end)

else

	remoteInvokeHandler("FunctionCall", function(id, data)
		return encodeTransmittion(nil, objects[id](decodeTransmittion(nil, data)))
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
		
		if Server then
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
				if Server then
					local player = players[data.id]
					return decodeTransmittion(player, getRemote("FunctionCall"):InvokeClient(player, data.id, encodeTransmittion(player, ...)))
				else
					return decodeTransmittion(nil, getRemote("FunctionCall"):InvokeServer(data.id, encodeTransmittion(nil, ...)))
				end
			end

			objects[data.id] = result
			objects[result] = data.id

			return result
		elseif dataType == "instance" then
			local instance
			
			if Server then
				instance = instanceIDs[data.id or ""]
			else
				instance = getRemote("GetInstance"):InvokeServer(data.id)
			end
			
			return instance
		end
	end

	error("Cannot decode '" .. dataType .. "'", 0)
end

function encodeTransmittion(to, ...)
	local length = select("#", ...)
	local encoded = {}

	for i = 1, length do
		encoded[i] = encode(to, (select(i, ...)))
	end

	local result = {
		type = "vararg",
		length = length,
		value = encoded
	}

	return encrypt(game:GetService("HttpService"):JSONEncode(result), key)
end

function decodeTransmittion(from, data)
	return decode(from, game:GetService("HttpService"):JSONDecode(decrypt(data, key)))
end

function Ambassador:Send(name, target, data)
	assert(not (Server and not data), "Expected target for server ambassador")

	if Server then
		assert(target.Parent, "Expected target to be in-game")
	else
		data = target
		target = game.Players.LocalPlayer
	end

	local remote = createRemote(getName(Server, name, target))

	local function invokationHandler(whosRequesting, type, ...)
		if type == InvokationType.RequestAmbassador then
			return encodeTransmittion(whosRequesting, data)
		else
			error("Unknown request", 0)
		end
	end

	if Server then
		function remote.OnServerInvoke(player, ...)
			return invokationHandler(player, ...)
		end
	else
		function remote.OnClientInvoke(...)
			return invokationHandler(nil, ...)
		end
	end
end

function Ambassador:Await(name, target, timeout)
	assert(not (Server and not target), "Expected target for client ambassador")

	if Server then
		assert(target.Parent, "Expected target to be in-game")
	else
		timeout = target
		target = game.Players.LocalPlayer
	end

	timeout = timeout or 30

	local remote
	local start = tick()
	repeat
		remote = game:GetService("ReplicatedStorage"):FindFirstChild(getName(not Server, name, target))

		if tick() - start > timeout then
			return false, "Timeout"
		end

		wait() until remote

	if Server then
		return true, decodeTransmittion(target, remote:InvokeClient(target, InvokationType.RequestAmbassador))
	else
		return true, decodeTransmittion(nil, remote:InvokeServer(InvokationType.RequestAmbassador))
	end
end

function Ambassador:Receive(...)
	local success, ambassador = Ambassador:Await(...)
	assert(success, "Could not receive ambassador")
	return ambassador
end

if Server then
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

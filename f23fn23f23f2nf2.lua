local DEBUG_LOG_EVERYTHING = getgenv().RainSettings.INSTANCE_METAMETHOD_LOGS
local DEBUG_LOG_CALL_ARGUMENTS = getgenv().RainSettings.INSTANCE_METAMETHOD_CALL_ARGS

local Inst = {}
local ClonedObjs = {}
local NewindexHooks = {
	Parent = "GetInstance"
}

local function handleargs(...)
	if ... == nil then
		return nil
	end

	local t = {...}

	for i, v in pairs(t) do
		if typeof(v) == "userdata" then
			t[i] = v:GetInstance()
		elseif typeof(v) == "table" then
			for key, value in pairs(v) do
				if typeof(value) == "userdata" then
					v[key] = value:GetInstance()
				end
			end
		end
	end

	return unpack(t)
end

local function handleresp(clone, ...)
	if ... == nil then
		return nil
	end

	local t = {...}

	for i, v in pairs(t) do
		if typeof(v) == "Instance" then
			t[i] = clone(v)
		elseif typeof(v) == "table" then
			for key, value in pairs(v) do
				if typeof(value) == "Instance" then
					v[key] = clone(value)
				end
			end
		end
	end

	return unpack(t)
end

local function pindex(tabl, value, callback)
	if tabl == nil then
		return callback
	end

	local s, r = pcall(function()
		return tabl[value]
	end)

	if s then
		return r
	else
		return callback
	end
end

local function clone(OriginalInstance, FunctionHooks)
	FunctionHooks = FunctionHooks or {}
	local InternalFunctionHooks = {}

	if OriginalInstance == nil then
		return nil
	end

	if typeof(OriginalInstance) == "userdata" then
		return OriginalInstance:GetInstance()
	end

	if typeof(OriginalInstance) ~= "Instance" then
		return OriginalInstance
	end

	local prox = newproxy(true)
	local meta = getmetatable(prox)

	if ClonedObjs[OriginalInstance] ~= nil then
		return ClonedObjs[OriginalInstance]
	end

	ClonedObjs[OriginalInstance] = prox

	InternalFunctionHooks.GetInstance = function()
		return OriginalInstance
	end

	InternalFunctionHooks.GetRawMetatable = function()
		return meta
	end

	InternalFunctionHooks.GetHiddenProperty = function(Property)
		local Success1, Check1 = pcall(function()
			return OriginalInstance[Property]
		end)

		if Success1 then
			return Check1, false -- property is not hidden
		else
			local Success2, Check2 = pcall(function()
				return game:GetService("UGCValidationService"):GetPropertyValue(OriginalInstance, Property)
			end)

			if Success2 then
				return Check2, true -- property is hidden
			else
				error("Property " .. Property .. " does not exist in instance " .. tostring(OriginalInstance) .. ".")
			end
		end
	end

	function meta:__index(call)
		if getgenv().RainSettings.ENABLE_LOGGING and DEBUG_LOG_EVERYTHING then
			print("[" .. tostring(OriginalInstance) .. "] Attempt to GET property/function " .. tostring(call))
		end

		if pindex(InternalFunctionHooks, call, false) then
			return function(_, ...)
				return InternalFunctionHooks[call](...)
			end
		end

		if pindex(FunctionHooks, call, false) then
			return function(_, ...)
				if getgenv().RainSettings.ENABLE_LOGGING and DEBUG_LOG_EVERYTHING then
					if DEBUG_LOG_CALL_ARGUMENTS then
						if ... ~= nil then
							local t = {...}
							local args = ""

							for i, v in pairs(t) do
								args = args .. tostring(v) .. " (ARG TYPE: " .. tostring(typeof(v)) .. "), "
							end

							print("[" .. tostring(OriginalInstance) .. "] Attempt to CALL hooked function " .. tostring(call) .. " with args: " .. args)
						else
							print("[" .. tostring(OriginalInstance) .. "] Attempt to CALL hooked function " .. tostring(call) .. " with no passed args")
						end
					else
						print("[" .. tostring(OriginalInstance) .. "] Attempt to CALL hooked function " .. tostring(call) .. " with no passed args")
					end
				end

				return handleresp(clone, FunctionHooks[call](handleargs(...)))
			end
		end

		local original_value = pindex(OriginalInstance, call, "i love yana")
		if original_value ~= "i love yana" then
			if typeof(original_value) ~= "function" then
				if typeof(original_value) == "Instance" then
					return clone(original_value, {})
				else
					return original_value
				end
			else
				return function(_, ...)
					if getgenv().RainSettings.ENABLE_LOGGING and DEBUG_LOG_EVERYTHING then
						if DEBUG_LOG_CALL_ARGUMENTS then
							if ... ~= nil then
								local t = {...}
								local args = ""

								for i, v in pairs(t) do
									args = args .. tostring(v) .. " (ARG TYPE: " .. tostring(typeof(v)) .. "), "
								end

								print("[" .. tostring(OriginalInstance) .. "] Attempt to CALL function " .. tostring(call) .. " with args: " .. args)
							else
								print("[" .. tostring(OriginalInstance) .. "] Attempt to CALL function " .. tostring(call) .. " with no passed args")
							end
						else
							print("[" .. tostring(OriginalInstance) .. "] Attempt to CALL function " .. tostring(call) .. " with no passed args")
						end
					end

					return handleresp(clone, OriginalInstance[call](OriginalInstance, handleargs(...)))
				end
			end
		else
			return error(call .. ' is not a valid member of ' .. tostring(OriginalInstance) .. ' "' .. OriginalInstance.Name .. '"')
		end
	end

	function meta:__newindex(prop, val)
		if pindex(OriginalInstance, prop, "i love yana") ~= "i love yana" then
			if getgenv().RainSettings.ENABLE_LOGGING and DEBUG_LOG_EVERYTHING then
				print("[" .. tostring(OriginalInstance) .. "] Attempt to SET property " .. tostring(prop) .. " with value " .. tostring(val))
			end

			if NewindexHooks[prop] ~= nil then
				if NewindexHooks[prop] == "GetInstance" then
					if typeof(val) == "userdata" then
						val = val:GetInstance()
					end
				end
			end

			local success, callback = pcall(function() OriginalInstance[prop] = val end)

			if not success then
				return error(callback)
			end
		else
			if OriginalInstance:IsA("BindableFunction") and prop == "OnInvoke" then
				OriginalInstance.OnInvoke = val
				return nil
			end
			return error(prop .. ' is not a valid member of ' .. tostring(OriginalInstance) .. ' "' .. OriginalInstance.Name .. '"')
		end
	end

	meta.__tostring = function()
		return tostring(OriginalInstance)
	end
	meta.__type = "Instance"
	meta.__metatable = "This metatable is locked"

	return prox
end

local function clonedatamodel(DataModel, FunctionHooks, ServiceHooks, BlockedServices)
	local InternalFunctionHooks = {}
	local prox = newproxy(true)
	local meta = getmetatable(prox)

	InternalFunctionHooks.GetInstance = function()
		return DataModel
	end

	InternalFunctionHooks.GetRawMetatable = function()
		return meta
	end

	InternalFunctionHooks.GetHiddenProperty = function(Property)
		local Success1, Check1 = pcall(function()
			return DataModel[Property]
		end)

		if Success1 then
			return Check1, false
		else
			local Success2, Check2 = pcall(function()
				return game:GetService("UGCValidationService"):GetPropertyValue(DataModel, Property)
			end)

			if Success2 then
				return Check2, true
			else
				error("Property " .. Property .. " does not exist in instance " .. tostring(DataModel) .. ".")
			end
		end
	end

	function meta:__index(call)
		if getgenv().RainSettings.ENABLE_LOGGING and DEBUG_LOG_EVERYTHING then
			print("[DataModel] Attempt to GET property/value " .. call)
		end

		if pindex(ServiceHooks, call, false) and DataModel[call] == game:FindService(call) then
			return clone(game:FindService(call), ServiceHooks[call])
		end

		if pindex(BlockedServices, call, false) and DataModel[call] == game:FindService(call) then
			return nil
		end

		if pindex(InternalFunctionHooks, call, false) then
			return function(_, ...)
				return InternalFunctionHooks[call](...)
			end
		end

		if pindex(FunctionHooks, call, false) then
			return function(_, ...)
				if getgenv().RainSettings.ENABLE_LOGGING and DEBUG_LOG_EVERYTHING then
					if DEBUG_LOG_CALL_ARGUMENTS then
						if ... ~= nil then
							local t = {...}
							local args = ""

							for i, v in pairs(t) do
								args = args .. tostring(v) .. " (ARG TYPE: " .. tostring(typeof(v)) .. "), "
							end

							print("[DataModel] Attempt to CALL hooked function " .. tostring(call) .. " with args: " .. args)
						else
							print("[DataModel] Attempt to CALL hooked function " .. tostring(call) .. " with no passed args")
						end
					else
						print("[DataModel] Attempt to CALL hooked function " .. tostring(call) .. " with no passed args")
					end
				end

				return handleresp(clone, FunctionHooks[call](handleargs(...)))
			end
		end

		local original_value = pindex(DataModel, call, "i love yana")
		if original_value ~= "i love yana" then
			if typeof(original_value) ~= "function" then
				if typeof(original_value) == "Instance" then
					return clone(original_value, {})
				else
					return original_value
				end
			else
				return function(_, ...)
					if getgenv().RainSettings.ENABLE_LOGGING and DEBUG_LOG_EVERYTHING then
						if DEBUG_LOG_CALL_ARGUMENTS then
							if ... ~= nil then
								local t = {...}
								local args = ""

								for i, v in pairs(t) do
									args = args .. tostring(v) .. " (ARG TYPE: " .. tostring(typeof(v)) .. "), "
								end

								print("[DataModel] Attempt to CALL function " .. tostring(call) .. " with args: " .. args)
							else
								print("[DataModel] Attempt to CALL function " .. tostring(call) .. " with no passed args")
							end
						else
							print("[DataModel] Attempt to CALL function " .. tostring(call) .. " with no passed args")
						end
					end

					return handleresp(clone, DataModel[call](DataModel, handleargs(...)))
				end
			end
		else
			return error(call .. ' is not a valid member of ' .. tostring(DataModel) .. ' "' .. DataModel.Name .. '"')
		end
	end

	function meta:__newindex(prop, val)
		if pindex(DataModel, prop, "i love yana") ~= "i love yana" then
			if getgenv().RainSettings.ENABLE_LOGGING and DEBUG_LOG_EVERYTHING then
				print("[DataModel] Attempt to SET property " .. tostring(prop) .. " with value " .. tostring(val))
			end

			local success, callback = pcall(function() DataModel[prop] = val end)

			if not success then
				return error(callback)
			end
		else
			return error(prop .. ' is not a valid member of ' .. tostring(DataModel) .. ' "' .. DataModel.Name .. '"')
		end
	end

	meta.__tostring = function()
		return tostring(DataModel)
	end
	meta.__type = "Instance"
	meta.__metatable = "This metatable is locked"

	return prox
end

Inst["clonedatamodel"] = clonedatamodel
Inst["clone"] = clone
Inst["pindex"] = pindex

return Inst

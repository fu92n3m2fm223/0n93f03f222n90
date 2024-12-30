local getInfo = getinfo or debug.getinfo
local debugMode = false
local hookedFunctions = {}
local detectedFunc, killFunc

setthreadidentity(2)

for _, value in ipairs(getgc(true)) do
    if typeof(value) == "table" then
        local detected = rawget(value, "Detected")
        local kill = rawget(value, "Kill")

        if typeof(detected) == "function" and not detectedFunc then
            detectedFunc = detected
            local originalHook
            originalHook = hookfunction(detectedFunc, function(method, info, ...)
                if method ~= "_" then
                    if debugMode then
                        warn(string.format(
                            "Adonis AntiCheat flagged\nMethod: %s\nInfo: %s",
                            tostring(method),
                            tostring(info)
                        ))
                    end
                end
                return true
            end)
            table.insert(hookedFunctions, detectedFunc)
        end

        if rawget(value, "Variables") and rawget(value, "Process") and typeof(kill) == "function" and not killFunc then
            killFunc = kill
            local originalHook
            originalHook = hookfunction(killFunc, function(info)
                if debugMode then
                    warn(string.format("Adonis AntiCheat tried to kill (fallback): %s", tostring(info)))
                end
            end)
            table.insert(hookedFunctions, killFunc)
        end
    end
end

local originalDebugInfo
originalDebugInfo = hookfunction(getrenv().debug.info, newcclosure(function(...)
    local firstArg, _ = ...
    if detectedFunc and firstArg == detectedFunc then
        if debugMode then
            warn("Adonis bypassed")
        end
        return coroutine.yield(coroutine.running())
    end
    return originalDebugInfo(...)
end))

setthreadidentity(7)

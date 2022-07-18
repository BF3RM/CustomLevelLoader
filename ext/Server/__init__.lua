---@param p_Command string
---@param p_Args string[]
---@return string[]
RCON:RegisterCommand("CLL.useHttp", RemoteCommandFlag.DisableAfterStartup, function(p_Command, p_Args)
	local s_BooleanString = p_Args[1]

	if not s_BooleanString then
		return { "OK", tostring(Config.USE_HTTP) }
	end

	if s_BooleanString == "1" or s_BooleanString:lower() == "true" then
		Config.USE_HTTP = true
	else
		Config.USE_HTTP = false
	end

	return { "OK" }
end)

---@param p_Command string
---@param p_Args string[]
---@return string[]
RCON:RegisterCommand("CLL.addMirror", RemoteCommandFlag.DisableAfterStartup, function(p_Command, p_Args)
	if p_Args[1] then
		table.insert(Config.MIRRORS, p_Args[1])
	end

	return { "OK" }
end)

---@param p_Player Player
Events:Subscribe('Player:Authenticated', function(p_Player)
	NetEvents:SendToLocal("CLL:HTTPINFO", p_Player, Config.USE_HTTP, Config.MIRRORS)
end)

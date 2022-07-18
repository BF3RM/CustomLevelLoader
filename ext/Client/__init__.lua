---@param p_UseHttp boolean
---@param p_Mirrors string[]
NetEvents:Subscribe("CLL:HTTPINFO", function(p_UseHttp, p_Mirrors)
	Config.USE_HTTP = p_UseHttp
	Config.MIRRORS = p_Mirrors
end)

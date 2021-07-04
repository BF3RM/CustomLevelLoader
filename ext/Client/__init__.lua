Events:Subscribe('Level:LoadingInfo', function()
	local s_Settings = ClientSettings(ResourceManager:GetSettings("ClientSettings"))
	if s_Settings then
		s_Settings.loadingTimeout = -1
	end
end)
NetEvents:Subscribe('MapLoader:GetLevel', function(p_Level)
	if p_Level == nil then
		print("Received no level")
		return
	end
	print('Received transforms for "' .. p_Level.header.mapName .. '".')
	g_CustomLevelData = p_Level
end)

Events:Subscribe('Level:LoadingInfo', function()
	local s_Settings = ClientSettings(ResourceManager:GetSettings("ClientSettings"))
	if(s_Settings) then
		s_Settings.loadingTimeout = -1
	end 
end)
NetEvents:Subscribe('MapLoader:GetLevel', function(level)
	if(level == nil) then
		print("Received no level")
		return
	end
	print('Received transforms for "' .. level.header.mapName .. '".')
	CustomLevelData = level
end)

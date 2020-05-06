Events:Subscribe('Level:LoadingInfo', function()
	--print("Loaded")
	--NetEvents:Send('MapLoader:GetLevel')
end)
NetEvents:Subscribe('MapLoader:GetLevel', function(level)
	print('Received transforms for "' .. level.header.mapName .. '".')
	CustomLevel = level
end)

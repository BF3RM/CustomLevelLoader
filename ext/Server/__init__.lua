local presetJSON = require "preset"
local preset = json.decode(presetJSON)
Events:Subscribe('Extension:Loaded', function()
	CustomLevel = preset
end)
NetEvents:Subscribe('MapLoader:GetLevel', function(player)
	print(player)
	print('Sending level to ' .. player.name)
	NetEvents:SendTo('MapLoader:GetLevel', player, preset)
end)

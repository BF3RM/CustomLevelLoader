--local presetJSON = require "preset"
local function DecodeParams(p_Table)
    if(p_Table == nil) then
        print("No table received")
        return false
	end
	for s_Key, s_Value in pairs(p_Table) do
		if s_Key == 'transform' or s_Key == 'localTransform'then
			local s_LinearTransform = LinearTransform(
					Vec3(s_Value.left.x, s_Value.left.y, s_Value.left.z),
					Vec3(s_Value.up.x, s_Value.up.y, s_Value.up.z),
					Vec3(s_Value.forward.x, s_Value.forward.y, s_Value.forward.z),
					Vec3(s_Value.trans.x, s_Value.trans.y, s_Value.trans.z))

			p_Table[s_Key] = s_LinearTransform

		elseif type(s_Value) == "table" then
			p_Table[s_Key] = DecodeParams(s_Value)
		end

	end

	return p_Table
end


local preset = nil
Events:Subscribe('Extension:Loaded', function()
	if(preset ~= nil) then
		print("Loaded preset: " .. preset.header.projectName)
		CustomLevel = preset
	end
end)

Events:Subscribe('MapLoader:LoadLevel', function(saveFile)
	preset = saveFile
	CustomLevel = preset
	print("Got savefile: " .. preset.header.projectName)
end)

NetEvents:Subscribe('MapLoader:GetLevel', function(player)
	print('Sending level to ' .. player.name)
	NetEvents:SendTo('MapLoader:GetLevel', player, CustomLevel)
end)


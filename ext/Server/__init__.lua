local presetJSON = require "preset"
local function DecodeParams(p_Table)
    if(p_Table == nil) then
        print("No table received")
        return false
	end
	for s_Key, s_Value in pairs(p_Table) do
		if s_Key == 'transform' then
			local s_LinearTransform = LinearTransform(
					Vec3(s_Value.left.x, s_Value.left.y, s_Value.left.z),
					Vec3(s_Value.up.x, s_Value.up.y, s_Value.up.z),
					Vec3(s_Value.forward.x, s_Value.forward.y, s_Value.forward.z),
					Vec3(s_Value.trans.x, s_Value.trans.y, s_Value.trans.z))

			p_Table[s_Key] = s_LinearTransform

		elseif type(s_Value) == "table" then
			DecodeParams(s_Value)
		end

	end

	return p_Table
end


local preset = DecodeParams(json.decode(presetJSON))
Events:Subscribe('Extension:Loaded', function()
	print("Loaded preset: " .. preset.header.projectName)
	CustomLevel = preset
end)
NetEvents:Subscribe('MapLoader:GetLevel', function(player)
	print(player)
	print('Sending level to ' .. player.name)
	NetEvents:SendTo('MapLoader:GetLevel', player, preset)
end)


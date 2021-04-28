--local presetJSON = require "preset"
local function DecodeParams(p_Table)
    if p_Table == nil then
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


local m_Preset = nil
Events:Subscribe('Extension:Loaded', function()
	if m_Preset ~= nil then
		print("Loaded preset: " .. m_Preset.header.projectName)
		g_CustomLevelData = m_Preset
	end
end)

Events:Subscribe('MapLoader:LoadLevel', function(p_SaveFile)
	m_Preset = p_SaveFile
	g_CustomLevelData = m_Preset
	print("Got savefile: " .. m_Preset.header.projectName)
end)

NetEvents:Subscribe('MapLoader:GetLevel', function(p_Player)
	print('Sending level to ' .. p_Player.name)
	NetEvents:SendTo('MapLoader:GetLevel', p_Player, g_CustomLevelData)
end)


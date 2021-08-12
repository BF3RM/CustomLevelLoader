GameObjectOriginType = {
	Vanilla = 1,
	Custom = 2,
	CustomChild = 3
}


-- This is a global table that stores the save file data as a Lua table. Will be populated on-demand by
-- the server via NetEvents on the client-side
-- Stores LevelData DataContainer guids.
local m_OriginalLevelIndeces = {}
local m_LastLoadedLevelName = nil
local m_ObjectVariations = {}
local m_PendingVariations = {}
local m_PrimaryLevelGuids = {}
local m_CustomLevelData = {}
local m_World = nil

local function PatchOriginalObject(p_Object)
	if p_Object.originalRef == nil then
		print("Object without original reference found, dynamic object?")
		return
	end

	local s_Reference = nil

	if p_Object.originalRef.partitionGuid == nil or p_Object.originalRef.partitionGuid == "nil" then -- perform a search without partitionguid
		s_Reference = ResourceManager:SearchForInstanceByGuid(Guid(p_Object.originalRef.instanceGuid))

		if s_Reference == nil then
			print("Unable to find original reference: " .. p_Object.originalRef.instanceGuid)
			return
		end
	else
		s_Reference = ResourceManager:FindInstanceByGuid(Guid(p_Object.originalRef.partitionGuid), Guid(p_Object.originalRef.instanceGuid))

		if s_Reference == nil then
			print("Unable to find original reference: " .. p_Object.originalRef.instanceGuid .. " in partition " .. p_Object.originalRef.partitionGuid)

			ResourceManager:RegisterInstanceLoadHandlerOnce(Guid(p_Object.originalRef.partitionGuid), Guid(p_Object.originalRef.instanceGuid), function(p_Instance)
				s_Reference = _G[p_Instance.typeInfo.name](p_Instance)
				s_Reference:MakeWritable()

				if p_Object.isDeleted then
					s_Reference.excluded = true
				end

				if p_Object.localTransform then
					s_Reference.blueprintTransform = LinearTransform(p_Object.localTransform) -- LinearTransform(p_Object.localTransform)
				else
					s_Reference.blueprintTransform = LinearTransform(p_Object.transform) -- LinearTransform(p_Object.transform)
				end

				print("Fixed original reference: " .. tostring(s_Reference.instanceGuid) .. " in partition " .. tostring(s_Reference.partitionGuid))
			end)

			return
		end
	end

	s_Reference = _G[s_Reference.typeInfo.name](s_Reference)
	s_Reference:MakeWritable()

	if p_Object.isDeleted then
		s_Reference.excluded = true
	end

	if p_Object.localTransform then
		s_Reference.blueprintTransform = LinearTransform(p_Object.localTransform) -- LinearTransform(p_Object.localTransform)
	else
		s_Reference.blueprintTransform = LinearTransform(p_Object.transform) -- LinearTransform(p_Object.transform)
	end
end

local function AddCustomObject(p_Object)
	local s_Blueprint = ResourceManager:FindInstanceByGuid(Guid(p_Object.blueprintCtrRef.partitionGuid), Guid(p_Object.blueprintCtrRef.instanceGuid))

	if s_Blueprint == nil then
		print('Cannot find blueprint with guid ' .. tostring(p_Object.blueprintCtrRef.instanceGuid))
		return
	end

	-- Filter BangerEntityData.
	if s_Blueprint:Is('ObjectBlueprint') then
		local s_ObjectBlueprint = ObjectBlueprint(s_Blueprint)

		if s_ObjectBlueprint.object and s_ObjectBlueprint.object:Is('BangerEntityData') then
			print("Cannot add custom object that is a BangerEntityData")
			return
		end
	end

	local s_Reference = nil

	if s_Blueprint:Is('EffectBlueprint') then
		s_Reference = EffectReferenceObjectData()
		s_Reference.autoStart = true
	else
		s_Reference = ReferenceObjectData()
	end

	if p_Object.localTransform then
		s_Reference.blueprintTransform = LinearTransform(p_Object.localTransform)
	else
		s_Reference.blueprintTransform = LinearTransform(p_Object.transform)
	end

	s_Reference.blueprint = Blueprint(s_Blueprint)

	if m_ObjectVariations[p_Object.variation] == nil and p_Object.variation ~= 0 then
		if m_PendingVariations[p_Object.variation] == nil then
			m_PendingVariations[p_Object.variation] = {}
		end

		table.insert(m_PendingVariations[p_Object.variation], s_Reference)
	else
		s_Reference.objectVariation = m_ObjectVariations[p_Object.variation]
	end

	s_Reference.isEventConnectionTarget = Realm.Realm_None
	s_Reference.isPropertyConnectionTarget = Realm.Realm_None
	s_Reference.excluded = false

	m_World.objects:add(s_Reference)
end

local function GetCustomLevel(p_LevelName, p_GameModeName)
	local s_LevelName = p_LevelName:gsub(".*/", "")

	local s_Path = '__shared/Levels/' .. s_LevelName .. '/' .. s_LevelName .. '_' .. p_GameModeName

	local s_Ok, s_PresetJson = pcall(require, s_Path)
	s_PresetJson = s_Ok and s_PresetJson or nil

	if not s_PresetJson then
		print('Couldn\'t find custom level data for Level: ' .. p_LevelName .. ' - GameMode: ' .. p_GameModeName)
		return nil
	end

	local s_Preset = json.decode(s_PresetJson)

	if not s_Preset then
		error('Couldn\'t decode json preset')
		return nil
	end

	print("preset found: " .. s_Path:gsub(".*/", ""))

	return s_Preset
end

local function GetIndexCount(p_PrimaryLevel)
	local s_IndexCount = 0

	--find index
	for _, l_Object in pairs(p_PrimaryLevel.objects) do
		if l_Object:Is('WorldPartReferenceObjectData') then
			local l_RefObjectData = WorldPartReferenceObjectData(l_Object)

			if l_RefObjectData.blueprint ~= nil and l_RefObjectData.blueprint:Is('WorldPartData') then
				local s_WorldPart = WorldPartData(l_RefObjectData.blueprint)

				if #s_WorldPart.objects ~= 0 then
					local s_ROD = s_WorldPart.objects[#s_WorldPart.objects] -- last one in array

					if s_ROD and s_ROD:Is('ReferenceObjectData') then
						s_ROD = ReferenceObjectData(s_ROD)

						if s_ROD.indexInBlueprint > s_IndexCount then
							s_IndexCount = s_ROD.indexInBlueprint
						end
					end
				end
			end
		end
	end

	return s_IndexCount
end

-- nº 1 in calling order
Events:Subscribe('Level:LoadResources', function()
	print("-----Loading resources")

	if m_LastLoadedLevelName == SharedUtils:GetLevelName() then
		print('Same level loading, skipping')
		return
	end

	m_ObjectVariations = {}
	m_PendingVariations = {}

	m_CustomLevelData = GetCustomLevel(SharedUtils:GetLevelName(), SharedUtils:GetCurrentGameMode())

	if m_CustomLevelData == nil then
		return
	end

	if m_CustomLevelData.data == nil then
		print("Custom Level preset is in a wrong format, abort.")
		m_CustomLevelData = nil
		return
	end

	m_World = WorldPartData(Guid("ADC31E4A-AF50-94EC-9628-E21026DF9B7D"))

	for _, l_Object in pairs(m_CustomLevelData.data) do
		ResourceManager:RegisterInstanceLoadHandlerOnce(Guid(l_Object.blueprintCtrRef.partitionGuid), Guid(l_Object.blueprintCtrRef.instanceGuid), function(p_Instance)
			if l_Object.origin == GameObjectOriginType.Custom then
				if not m_CustomLevelData.vanillaOnly then
					AddCustomObject(l_Object)
				end
			elseif l_Object.origin == GameObjectOriginType.Vanilla then
				PatchOriginalObject(l_Object)
			end
		end)
	end
end)

-- nº 3 in calling order
Events:Subscribe('Level:LoadingInfo', function(p_ScreenInfo)
	print("-----Loading Info - " .. p_ScreenInfo)

	if p_ScreenInfo ~= "Registering entity resources" then
		return
	end

	if m_LastLoadedLevelName == SharedUtils:GetLevelName() then
		return
	end

	m_LastLoadedLevelName = SharedUtils:GetLevelName()

	if m_CustomLevelData == nil then
		return
	end

	if m_PrimaryLevelGuids.instanceGuid == nil then
		print("No PrimaryLevelGuids available.")
		return
	end

	print("Patching level")

	local s_PrimaryLevel = ResourceManager:FindInstanceByGuid(m_PrimaryLevelGuids.partitionGuid, m_PrimaryLevelGuids.instanceGuid)

	if s_PrimaryLevel == nil then
		print("Can\'t add registry, primarylevel is nil")
		return
	end

	s_PrimaryLevel = LevelData(s_PrimaryLevel)

	local s_IndexCount = GetIndexCount(s_PrimaryLevel)
	print("Index count is: " .. s_IndexCount)

	local s_RegistryContainer = s_PrimaryLevel.registryContainer

	if s_RegistryContainer == nil then
		print('No RegistryContainer found, this shouldn\'t happen')
	end

	s_RegistryContainer = RegistryContainer(s_RegistryContainer)
	s_RegistryContainer:MakeWritable()

	local s_WorldPartReference = nil

	for l_Index = #s_PrimaryLevel.objects, 1, -1 do
		if s_PrimaryLevel.objects[l_Index].instanceGuid ~= nil and
		s_PrimaryLevel.objects[l_Index].instanceGuid == Guid("9F1DA12C-4DE6-528D-F0FB-4D391BC4510F") then
			s_WorldPartReference = WorldPartReferenceObjectData(s_PrimaryLevel.objects[l_Index])
			break
		end
	end

	if s_WorldPartReference == nil then
		print("WorldPartReferenceObjectData not found. Adding it again.")
		s_WorldPartReference = WorldPartReferenceObjectData(Guid("9F1DA12C-4DE6-528D-F0FB-4D391BC4510F"))

		s_WorldPartReference.indexInBlueprint = #s_PrimaryLevel.objects + 1
		s_WorldPartReference.isEventConnectionTarget = Realm.Realm_None
		s_WorldPartReference.isPropertyConnectionTarget = Realm.Realm_None
		s_WorldPartReference.excluded = false

		s_PrimaryLevel.objects:add(s_WorldPartReference)
	end

	s_WorldPartReference.blueprint = m_World

	for l_Index, l_Reference in pairs(WorldPartData(s_WorldPartReference.blueprint).objects) do
		l_Reference = _G[l_Reference.typeInfo.name](l_Reference)
		l_Reference.indexInBlueprint = l_Index + s_IndexCount
		s_RegistryContainer.referenceObjectRegistry:add(l_Reference)
	end

	s_RegistryContainer.blueprintRegistry:add(m_World)
	s_RegistryContainer.referenceObjectRegistry:add(s_WorldPartReference)


	-- Save original indeces in case LevelData has to be reset to default state later.
	m_OriginalLevelIndeces = {
		objects = #s_PrimaryLevel.objects,
		ROFs = #s_RegistryContainer.referenceObjectRegistry,
		blueprints = #s_RegistryContainer.blueprintRegistry,
		entity = #s_RegistryContainer.entityRegistry
	}

	m_World = nil

	print("Patched level")
end)

-- nº 2 in calling order
Events:Subscribe('Partition:Loaded', function(p_Partition)
	if not m_CustomLevelData then
		return
	end

	if p_Partition == nil then
		return
	end

	local s_PrimaryInstance = p_Partition.primaryInstance

	if s_PrimaryInstance == nil then
		print('Instance is null?')
		return
	end

	if s_PrimaryInstance:Is("LevelData") then
		local s_PrimaryLevel = LevelData(s_PrimaryInstance)

		if s_PrimaryLevel.name == SharedUtils:GetLevelName() then
			print("----Registering PrimaryLevel guids")
			s_PrimaryLevel:MakeWritable()

			m_PrimaryLevelGuids = {
				instanceGuid = s_PrimaryLevel.instanceGuid,
				partitionGuid = s_PrimaryLevel.partitionGuid
			}

			local s_WorldPartReference = WorldPartReferenceObjectData(Guid("9F1DA12C-4DE6-528D-F0FB-4D391BC4510F"))

			s_WorldPartReference.indexInBlueprint = #s_PrimaryLevel.objects + 1
			s_WorldPartReference.isEventConnectionTarget = Realm.Realm_None
			s_WorldPartReference.isPropertyConnectionTarget = Realm.Realm_None
			s_WorldPartReference.excluded = false

			s_PrimaryLevel.objects:add(s_WorldPartReference)
		end
	elseif s_PrimaryInstance:Is('ObjectVariation') then
		-- Store all variations in a map.
		local s_Variation = ObjectVariation(s_PrimaryInstance)
		m_ObjectVariations[s_Variation.nameHash] = s_Variation

		if m_PendingVariations[s_Variation.nameHash] ~= nil then
			for _, l_Object in pairs(m_PendingVariations[s_Variation.nameHash]) do
				l_Object.objectVariation = s_Variation
			end

			m_PendingVariations[s_Variation.nameHash] = nil
		end
	end
end)

-- Remove all DataContainer references and reset vars
Events:Subscribe('Level:Destroy', function()
	m_ObjectVariations = {}
	m_PendingVariations = {}

	-- TODO: remove all custom objects from level registry and leveldata if next round is
	-- the same map but a different save, once that is implemented. If it's a different map
	-- there is no need to clear anything, as the leveldata will be unloaded and a new one loaded
end)

GameObjectOriginType = {
	Vanilla = 1,
	Custom = 2,
	CustomChild = 3
}

-- Stores LevelData DataContainer.
local PrimaryLevel = nil

-- This is a global table that stores the save file data as a 
-- Lua table. Will be populated on-demand by
-- the server via NetEvents on the client-side
CustomLevelData = nil
local indexCount = 0
local customRegistryGuid = Guid('5FAD87FD-9934-4D44-A5BE-7C5B38FCE6AF')
local customRegistry = nil
local worldPartRefIndex = nil
local lastLoadedMap = nil

local function PatchOriginalObject(object, world)
	if(object.originalRef == nil) then
		print("Object without original reference found, dynamic object?")
		return
	end
	local s_Reference = nil
	if(object.originalRef.partitionGuid == nil or object.originalRef.partitionGuid == "nil") then -- perform a search without partitionguid
		 s_Reference = ResourceManager:SearchForInstanceByGuid(Guid(object.originalRef.instanceGuid))
		 if(s_Reference == nil) then
		 	print("Unable to find original reference: " .. object.originalRef.instanceGuid)
		 	return
		 end
	else
		 s_Reference = ResourceManager:FindInstanceByGuid(Guid(object.originalRef.partitionGuid), Guid(object.originalRef.instanceGuid))
		 if(s_Reference == nil) then
		 	print("Unable to find original reference: " .. object.originalRef.instanceGuid .. " in partition " .. object.originalRef.partitionGuid)
		 	return
		 end
	end
	s_Reference = _G[s_Reference.typeInfo.name](s_Reference)
	s_Reference:MakeWritable()
	if(object.isDeleted) then
		s_Reference.excluded = true
	end
	if(object.localTransform) then
		s_Reference.blueprintTransform = LinearTransform(object.localTransform) -- LinearTransform(object.localTransform)
	else
		s_Reference.blueprintTransform = LinearTransform(object.transform) -- LinearTransform(object.transform)
	end
end

local function AddCustomObject(object, world)
	--[[for k,v in pairs(object) do
		print("k: " .. k)
		print("v: " .. v)
	end]]--
	local blueprint = ResourceManager:FindInstanceByGuid(Guid(object.blueprintCtrRef.partitionGuid), Guid(object.blueprintCtrRef.instanceGuid))
	if blueprint == nil then
		print('Cannot find blueprint with guid ' .. tostring(object.blueprintCtrRef.instanceGuid))
	end

	-- Filter BangerEntityData.
	if blueprint:Is('ObjectBlueprint') then
		local objectBlueprint = ObjectBlueprint(blueprint)
		if objectBlueprint.object and objectBlueprint.object:Is('BangerEntityData') then
			return
		end
	end

	local s_Reference = ReferenceObjectData()
	customRegistry.referenceObjectRegistry:add(s_Reference)
	if(object.localTransform) then	
		s_Reference.blueprintTransform = LinearTransform(object.localTransform)
	else
		s_Reference.blueprintTransform = LinearTransform(object.transform)
	end
	--print("AddCustomObject: " .. object.transform)
	s_Reference.blueprint = Blueprint(blueprint)
	-- s_Reference.blueprint:MakeWritable()

	if(objectVariations[object.variation] == nil) then
		pendingVariations[object.variation] = s_Reference
	else
		s_Reference.objectVariation = objectVariations[object.variation]
	end
	s_Reference.indexInBlueprint = #world.objects + indexCount + 1
	s_Reference.isEventConnectionTarget = Realm.Realm_None
	s_Reference.isPropertyConnectionTarget = Realm.Realm_None

	world.objects:add(s_Reference)
end

local function CreateWorldPart()
	local world = WorldPartData()
	customRegistry.blueprintRegistry:add(world)
	
	--find index
	for _, object in pairs(PrimaryLevel.objects) do
		if object:Is('WorldPartReferenceObjectData') then
			local obj = WorldPartReferenceObjectData(object)
			if obj.blueprint:Is('WorldPartData') then
				local worldPart = WorldPartData(obj.blueprint)
				if #worldPart.objects ~= 0 then
					local rod = worldPart.objects[#worldPart.objects] -- last one in array
					if rod and rod:Is('ReferenceObjectData') then
						rod = ReferenceObjectData(rod)
						if rod.indexInBlueprint > indexCount then
							indexCount = rod.indexInBlueprint
						end
					end
				end
			end
		end
	end

	print('indexCount is:')
	print(indexCount)

	if lastLoadedMap ~= SharedUtils:GetLevelName() then
		for index, object in pairs(CustomLevelData.data) do
			if object.origin == GameObjectOriginType.Custom then
				if (not CustomLevelData.vanillaOnly) then
					AddCustomObject(object, world)
				end
			elseif object.origin == GameObjectOriginType.Vanilla then
				PatchOriginalObject(object, world)
			end
			-- TODO handle CustomChild
		end
		lastLoadedMap = SharedUtils:GetLevelName()
	end

	local s_WorldPartReference = WorldPartReferenceObjectData()
	s_WorldPartReference.blueprint = world

	s_WorldPartReference.isEventConnectionTarget = Realm.Realm_None
	s_WorldPartReference.isPropertyConnectionTarget = Realm.Realm_None
	s_WorldPartReference.excluded = false

	return s_WorldPartReference
end

Events:Subscribe('Partition:Loaded', function(p_Partition)
	if p_Partition == nil then
		return
	end
	
	local s_Instances = p_Partition.instances

	for _, l_Instance in pairs(s_Instances) do
		if l_Instance == nil then
			print('Instance is null?')
			break
		end
		if(l_Instance:Is("Blueprint")) then
			--print("-------"..Blueprint(l_Instance).name)
		end
		if(l_Instance.typeInfo.name == "LevelData") then
			local s_Instance = LevelData(l_Instance)
			if(s_Instance.name == SharedUtils:GetLevelName()) then
				print("Primary level")
				s_Instance:MakeWritable()
				PrimaryLevel = s_Instance
				if(SharedUtils:IsClientModule()) then
					NetEvents:Send('MapLoader:GetLevel')
				end
			end
		elseif l_Instance:Is('ObjectVariation') then
			-- Store all variations in a map.
			local variation = ObjectVariation(l_Instance)
			objectVariations[variation.nameHash] = variation
			if pendingVariations[variation.nameHash] ~= nil then
				for _, object in pairs(pendingVariations[variation.nameHash]) do
					object.objectVariation = variation
				end

				pendingVariations[variation.nameHash] = nil
			end
		end
	end
end)

Events:Subscribe('Level:LoadingInfo', function(p_Info)
	if(p_Info == "Registering entity resources") then
		if(not CustomLevelData) then
			print("No custom level specified.")
			return
		end

		print("Patching level")
		customRegistry = customRegistry or RegistryContainer(customRegistryGuid)
		local s_WorldPartReference = CreateWorldPart()

		s_WorldPartReference.indexInBlueprint = #PrimaryLevel.objects
		
		PrimaryLevel.objects:add(s_WorldPartReference)
		worldPartRefIndex = #PrimaryLevel.objects
		local s_Container = PrimaryLevel.registryContainer
		s_Container:MakeWritable()
		s_Container.referenceObjectRegistry:add(s_WorldPartReference)
		refObjRegistryIndex = #s_Container.referenceObjectRegistry
		print('Level patched')
	end
end)

Events:Subscribe('Level:Destroy', function()
	objectVariations = {}
	pendingVariations = {}
	indexCount = 0
	-- TODO: Check if the next map is the same level (or gamemode)
	if worldPartRefIndex ~= nil and PrimaryLevel ~= nil then
	--	PrimaryLevel.objects:erase(worldPartRefIndex)
	end

	if refObjRegistryIndex ~= nil and PrimaryLevel ~= nil and PrimaryLevel.registryContainer ~= nil then
	--	PrimaryLevel.registryContainer.referenceObjectRegistry:erase(refObjRegistryIndex)
	end
	worldPartRefIndex = nil
	refObjRegistryIndex = nil
	customRegistry = nil

	-- PrimaryLevel = nil
end)

Events:Subscribe('Level:LoadResources', function()
	print("Loading resources")
	objectVariations = {}
	pendingVariations = {}
end)

Events:Subscribe('Level:RegisterEntityResources', function(levelData)
	customRegistry = customRegistry or RegistryContainer(customRegistryGuid)
	ResourceManager:AddRegistry(customRegistry, ResourceCompartment.ResourceCompartment_Game)
end)

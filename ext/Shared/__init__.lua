-- This is a global table that will be populated on-demand by
-- the server via NetEvents on the client-side, or overriden
-- with the real data on the server-side.
PrimaryLevel = nil
local function PatchOriginalObject(object, world)
	print("Patching object: " .. object.guid)
	if(object.original == nil) then
		print("Object without original reference found, dynamic object?")
		return
	end
	local s_Reference = nil
	if(object.original.partitionGuid == nil or object.original.partitionGuid == "nil") then -- perform a search without partitionguid
		 s_Reference = ResourceManager:SearchForInstanceByGuid(Guid(object.original.instanceGuid))
		 if(s_Reference == nil) then
		 	print("Unable to find original reference: " .. object.original.instanceGuid)
		 	return
		 end
	else
		 s_Reference = ResourceManager:FindInstanceByGuid(Guid(object.original.partitionGuid), Guid(object.original.instanceGuid))
		 if(s_Reference == nil) then
		 	print("Unable to find original reference: " .. object.original.instanceGuid .. " in partition " .. object.original.partitionGuid)
		 	return
		 end
	end
	s_Reference = _G[s_Reference.typeInfo.name](s_Reference)
	s_Reference:MakeWritable()
	print(tostring(s_Reference))
	print("new: " .. tostring(s_Reference.blueprintTransform))
	print("org: " .. tostring(object.transform))
	if(object.isDeleted) then
		s_Reference.excluded = true
	end
	if(object.localTransform) then
		s_Reference.blueprintTransform = LinearTransform(object.localTransform)
	else
		s_Reference.blueprintTransform = LinearTransform(object.transform)
	end
end
local function AddCustomObject(object, world)
	local s_Reference = ReferenceObjectData()
	customRegistry.referenceObjectRegistry:add(s_Reference)
	s_Reference.blueprintTransform = LinearTransform(object.localTransform)
	s_Reference.blueprint = Blueprint(ResourceManager:FindInstanceByGuid(Guid(object.blueprintCtrRef.partitionGuid), Guid(object.blueprintCtrRef.instanceGuid)))
	s_Reference.blueprint:MakeWritable()
	s_Reference.blueprint.needNetworkId = true
	--print(s_Reference.blueprint.name)
	if(objectVariations[object.variation] == nil) then
		pendingVariations[object.variation] = s_Reference
	else
		s_Reference.objectVariation = objectVariations[object.variation]
	end
	s_Reference.indexInBlueprint = #world.objects + 30001
	s_Reference.isEventConnectionTarget = Realm.Realm_None
	s_Reference.isPropertyConnectionTarget = Realm.Realm_None

	world.objects:add(s_Reference)
end

local function CreateWorldPart()
	local world = WorldPartData()
	customRegistry.blueprintRegistry:add(world)
	for index, object in pairs(CustomLevel.data) do
		if(not object.isVanilla) then
			AddCustomObject(object, world)
		else
			PatchOriginalObject(object, world)
		end
	end
	local s_WorldPartReference = WorldPartReferenceObjectData()
	s_WorldPartReference.blueprint = world

	s_WorldPartReference.isEventConnectionTarget = Realm.Realm_None
	s_WorldPartReference.isPropertyConnectionTarget = Realm.Realm_None

	return s_WorldPartReference
end



Events:Subscribe('Partition:Loaded', function(p_Partition)
	if p_Partition == nil then
		return
	end
	
	local s_Instances = p_Partition.instances

	for _, l_Instance in ipairs(s_Instances) do
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
		print("Patching level")
		local s_WorldPartReference = CreateWorldPart()
		s_WorldPartReference.indexInBlueprint = #PrimaryLevel.objects + 6000
		PrimaryLevel.objects:add(s_WorldPartReference)
		local s_Container = PrimaryLevel.registryContainer
		s_Container:MakeWritable()
		s_Container.referenceObjectRegistry:add(s_WorldPartReference)
	end
end)
Events:Subscribe('Level:Destroy', function()
	objectVariations = {}
	pendingVariations = {}
	customRegistry = nil
end)

Events:Subscribe('Level:LoadResources', function()
	print("Loading resources")
	objectVariations = {}
	pendingVariations = {}
	customRegistry = RegistryContainer()
end)
Events:Subscribe('Level:RegisterEntityResources', function(levelData)
	print("Resources")
	ResourceManager:AddRegistry(customRegistry, ResourceCompartment.ResourceCompartment_Game)
end)

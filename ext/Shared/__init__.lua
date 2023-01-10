---@class CustomLevelLoaderConfig
---@field LOGGER_ENABLED boolean
---@field CLIENT_TIMEOUT number
Config = require "__shared/Config"

BUNDLE_PREFIX = 'CustomLevels'

local print = function(p_Message, p_IsWarning)
	if Config.LOGGER_ENABLED or p_IsWarning then
		if p_IsWarning then
			p_Message = 'WARNING: ' .. p_Message
		end

		print(p_Message)
	end
end

---@type table?
local m_LevelRODMap = {}
local m_LazyLoadedCount = 0

---Finds and returns the bundle name associated with the level and gamemode (@p_Path) loaded in the 
---case that there is a gamemode map file, and in case the map file does not exist or the path does 
---not have an entry it returns @p_Path
---@param p_Path string
---@return string
local function GetBundlePath(p_Path)
	local _, s_BundlesMapJson = pcall(require, '__shared/Levels/BundlesMap.lua')
	
	if not s_BundlesMapJson then
		return p_Path
	end

	local s_BundlesMap = json.decode(s_BundlesMapJson)

	-- Replace spaces in case of custom gamemodes with spaces in their names
	p_Path = p_Path:gsub(' ', '_')
	
	
	if s_BundlesMap and s_BundlesMap[p_Path] then
		print('Found custom bundle ' .. s_BundlesMap[p_Path] .. ' for gamemode ' .. p_Path .. ' in bundle map file')
		return s_BundlesMap[p_Path]
	end

	return p_Path
end

---@param p_LevelName string
---@param p_GameModeName string
---@return table|nil
local function GetLevelRODMap(p_LevelName, p_GameModeName)
	p_LevelName = p_LevelName:gsub(".*/", "")
	
	local s_FileName = GetBundlePath(p_LevelName .. '/' .. p_GameModeName)

	-- File name uses _ instead of /
	s_FileName = s_FileName:gsub('/', '_')

	local s_Path = '__shared/Levels/' .. p_LevelName .. '/' .. s_FileName

	local s_Ok, s_LevelRODMapJson = pcall(require, s_Path)
	s_LevelRODMapJson = s_Ok and s_LevelRODMapJson or nil

	if not s_LevelRODMapJson then
		print('Couldn\'t find ROD map file in path ' .. s_Path)
		return nil
	end

	local s_LevelRODMap = json.decode(s_LevelRODMapJson)

	if not s_LevelRODMap then
		error('Couldn\'t decode json ROD map')
		return nil
	end

	print("ROD map file found for Level: " .. p_LevelName .. " - GameMode: " .. p_GameModeName)

	return s_LevelRODMap
end

Hooks:Install('ResourceManager:LoadBundles', 100, function(p_Hook, p_Bundles, p_Compartment)
	print(p_Compartment)
	print(p_Bundles[1])
end)

-- nº 1 in calling order
Events:Subscribe('Level:LoadResources', function(p_LevelName, p_GameMode, p_IsDedicatedServer)
	print("-----Loading resources")

	local s_SuperBundleName = string.gsub(p_LevelName, 'Levels', BUNDLE_PREFIX)
	print("MountSuperBundle: " .. s_SuperBundleName)
	ResourceManager:MountSuperBundle(s_SuperBundleName)

	m_LevelRODMap = GetLevelRODMap(p_LevelName, p_GameMode)

	if m_LevelRODMap == nil then
		print('Could not get the level, level name: ' .. p_LevelName .. ', gamemode: ' .. p_GameMode, true)
		return
	end

	for l_PartitionGuid, l_Instances in pairs(m_LevelRODMap) do
		for _, l_InstanceGuid in ipairs(l_Instances) do
			ResourceManager:RegisterInstanceLoadHandlerOnce(Guid(l_PartitionGuid), Guid(l_InstanceGuid), function(p_Instance) 
				p_Instance = _G[p_Instance.typeInfo.name](p_Instance)
				p_Instance:MakeWritable()
				p_Instance.excluded = true
			end)
		end
	end
end)

local function _GetHighestIndexInPartition(s_Partition)
	local s_HighestIndexInPartition = 0

	for _, l_Instance in ipairs(s_Partition.instances) do
		if l_Instance:Is("GameObjectData") then
			l_Instance = GameObjectData(l_Instance)

			if l_Instance.indexInBlueprint > s_HighestIndexInPartition and l_Instance.indexInBlueprint ~= 65535 then
				s_HighestIndexInPartition = l_Instance.indexInBlueprint
			end
		end
	end

	return s_HighestIndexInPartition
end

---Patches the level, adding a SubWorldReferenceObjectData to the level that references the SubWorld in the custom bundle
local function _PatchLevel(p_LevelName)
	local s_Data = LevelData(ResourceManager:SearchForDataContainer(SharedUtils:GetLevelName()))
	s_Data:MakeWritable()

	local s_SWROD = SubWorldReferenceObjectData(Guid('6a724d44-4efd-4f7e-9249-2230121d7ecc'))

	local s_Path = GetBundlePath(p_LevelName:gsub(".*/", "") .. '/' .. SharedUtils:GetCurrentGameMode())
	
	s_SWROD.bundleName = BUNDLE_PREFIX .. '/' .. s_Path
	s_SWROD.blueprintTransform = LinearTransform()
	s_SWROD.blueprint = nil
	s_SWROD.objectVariation = nil
	s_SWROD.streamRealm = StreamRealm.StreamRealm_Both
	s_SWROD.castSunShadowEnable = true
	s_SWROD.excluded = false
	s_SWROD.inclusionSettings = nil
	s_SWROD.autoLoad = true
	s_SWROD.isWin32SubLevel = true
	s_SWROD.isXenonSubLevel = true
	s_SWROD.isPs3SubLevel = true
	s_SWROD.isEventConnectionTarget  = 2
	s_SWROD.isPropertyConnectionTarget  = 3

	local s_Partition = s_Data.partition

	if not s_Partition then
		print('Partition was nil', true)
		return
	end

	s_Partition:AddInstance(s_SWROD)

	local s_HighestIndexInPartition = _GetHighestIndexInPartition(s_Partition)
	s_SWROD.indexInBlueprint = s_HighestIndexInPartition + 1

	if s_Data.registryContainer ~= nil then
		s_Data.registryContainer:MakeWritable()
		local s_Registry = RegistryContainer(s_Data.registryContainer)
		s_Registry.referenceObjectRegistry:add(s_SWROD)
	end

	local s_LinkConnection = LinkConnection()
	s_LinkConnection.target = s_SWROD

	s_Data.linkConnections:add(s_LinkConnection)
	s_Data.objects:add(s_SWROD)
	print('Patched level')
end

Events:Subscribe('Partition:Loaded', function(p_Partition)
	local s_LevelName = SharedUtils:GetLevelName()

	if not s_LevelName then return end

	if p_Partition.name == s_LevelName:lower() then
		print('Patching level')

		local s_LevelData = LevelData(p_Partition.primaryInstance)

		for _, l_Object in ipairs(s_LevelData.objects) do
			l_Object = _G[l_Object.typeInfo.name](l_Object)

			if l_Object.blueprint and l_Object.blueprint.isLazyLoaded then
				m_LazyLoadedCount = m_LazyLoadedCount + 1
				print("LazyLoadedCount " .. m_LazyLoadedCount)
				
				l_Object.blueprint:RegisterLoadHandlerOnce(function (p_Instance)
					m_LazyLoadedCount = m_LazyLoadedCount - 1
					if m_LazyLoadedCount == 0 then _PatchLevel(s_LevelName) end
				end)
			end
		end

		if m_LazyLoadedCount == 0 then _PatchLevel(s_LevelName) end
	end
end)

-- Remove all DataContainer references and reset vars
Events:Subscribe('Level:Destroy', function()
	-- TODO: remove all custom objects from level registry and leveldata if next round is
	-- the same map but a different save, once that is implemented. If it's a different map
	-- there is no need to clear anything, as the leveldata will be unloaded and a new one loaded
end)

-- Increase timeout 
ResourceManager:RegisterInstanceLoadHandler(Guid('C4DCACFF-ED8F-BC87-F647-0BC8ACE0D9B4'), Guid('B479A8FA-67FF-8825-9421-B31DE95B551A'), function(p_Instance)
	p_Instance = ClientSettings(p_Instance)
	p_Instance:MakeWritable()
	p_Instance.loadedTimeout = Config.CLIENT_TIMEOUT
	p_Instance.loadingTimeout = Config.CLIENT_TIMEOUT
	p_Instance.ingameTimeout = Config.CLIENT_TIMEOUT
	print("Changed ClientSettings")
end)

ResourceManager:RegisterInstanceLoadHandler(Guid('C4DCACFF-ED8F-BC87-F647-0BC8ACE0D9B4'), Guid('818334B3-CEA6-FC3F-B524-4A0FED28CA35'), function(p_Instance)
	p_Instance = ServerSettings(p_Instance)
	p_Instance:MakeWritable()
	p_Instance.loadingTimeout = Config.CLIENT_TIMEOUT
	p_Instance.ingameTimeout = Config.CLIENT_TIMEOUT
	p_Instance.timeoutTime = Config.CLIENT_TIMEOUT
	print("Changed ServerSettings")
end)


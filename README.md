# CustomLevelLoader

Load your custom levels by putting your custom level presets created with MapEditor into a "Levels" subfolder following this convention:

Levels/LevelName/LevelName_GameModeName.lua

Check the realitymod branch for an example on how to use it:

Levels/XP3_Shield/XP3_Shield_ConquestLarge0.lua

The CustomLevelLoader will then automatically load that preset when the according level and gamemode is loaded.

## Important

If you want your custom levels to be officially available, create a fork of this mod and make a pull request. Your levels will then be available on a separate branch similar to the realitymod one.

This mod is currently a WIP. Destruction and data modifications not supported yet. There will be updates to the orginal mod, so make sure to keep your forks up to date. 

**It's mandatory to use ``-skipChecksum`` parameter in your server, or it will lead to client connection errors**

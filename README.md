# CustomLevelsLoader

Load your custom levels by creating a fork of this mod and put your custom level presets created with MapEditor into a "Levels" subfolder following this convention:

Levels/LevelName/LevelName_GameModeName.lua

There's an example contained in the mod:

Levels/XP3_Shield/XP3_Shield_ConquestLarge0.lua

The CustomLevelsLoader will then automatically load that preset when the according level and gamemode is loaded.

This mod is currently a WIP. Destruction and data modifications not supported yet. There will be updates to the orginal mod, so make sure to keep your forks up to date. 

**It's mandatory to use ``-skipchecksum`` parameter in your server, or it will lead to client connection errors**

local plugin = {}

plugin["name"] = "LxPS_NewProject"
plugin["author"] = "LexxersPS"
plugin["version"] = "0.1.0"
plugin["description"] = "Standalone, structured navmesh prototype: load tiles for current instance, detect current tile, verify calculations"
plugin["load"] = true            -- enable this new standalone project
plugin["is_library"] = false     -- this is a runnable plugin, not just a library
plugin["is_required_dependency"] = false

-- Professional filename/versioning policy:
-- - All Lua modules live under scripts/LxPS_NewProject/src/**
-- - Public API is exposed via scripts/LxPS_NewProject/main.lua only
-- - Logs go to scripts_log/ with prefix 'nxp_' for easy filtering
-- - Modules use clear names: core_adapter.lua, tile_index.lua, tile_loader.lua, verifier.lua, ui.lua

return plugin
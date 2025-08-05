local plugin = {}
plugin["name"] = "LxPS_Test"
plugin["author"] = "LexxersPS"
plugin["version"] = "1.0"
plugin["description"] = "Test plugin for navigation system validation with UI testing interface"
plugin["load"] = false  -- load it when true
plugin["is_library"] = false  -- not a library, it's a test plugin
plugin["is_required_dependency"] = false -- not a required dependency
plugin["dependencies"] = {"LxPS_Navigator"}  -- requires Navigator plugin
return plugin
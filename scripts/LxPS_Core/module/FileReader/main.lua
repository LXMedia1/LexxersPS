local FileReader = {}

--- Reads a file from the scripts_data directory
---@param filepath string The path relative to scripts_data (e.g. "mmaps/0001.mmap")
---@return string The file contents
function FileReader.read(filepath)
    return core.read_data_file(filepath)
end

--- Reads a mmap file from the mmaps directory
---@param filename string The mmap filename (e.g. "0001.mmap")
---@return string The file contents
function FileReader.read_mmap(filename)
    return core.read_data_file("mmaps/" .. filename)
end

return FileReader
local function createDrawing(type, properties)
    local d = Drawing.new(type)

    if type == "Square" or type == "Circle" then
        d.Filled = false
    end
    d.Visible = false
    d.Transparency = 1

    for k, v in pairs(properties) do
        pcall(function() d[k] = v end)
    end

    if type == "Square" or type == "Circle" then
        if properties.Filled ~= nil then
            d.Filled = properties.Filled
        else
            d.Filled = false
        end
    end

    return d
end

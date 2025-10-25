local Players = game:GetService("Players")

local HighlightPool = {}
HighlightPool.__index = HighlightPool

function HighlightPool.new()
	local self = setmetatable({
		pool = {},
	}, HighlightPool)

	local max = Players.MaxPlayers

	for i = 1, max do
		local hl = Instance.new("Highlight")
		hl.Enabled = false
		hl.Adornee = nil
		hl.FillColor = Color3.fromRGB(255, 255, 0)
		hl.OutlineColor = Color3.new(1, 1, 1)
		hl.Archivable = true
		table.insert(self.pool, hl)
	end

	return self
end

function HighlightPool:Get()
	return table.remove(self.pool) or Instance.new("Highlight")
end

function HighlightPool:Return(hl)
	hl.Enabled = false
	hl.Adornee = nil
	table.insert(self.pool, hl)
end

return HighlightPool

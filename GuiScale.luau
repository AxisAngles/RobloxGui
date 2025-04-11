--[[
	Usage:

	local con = GuiScale.getTracker(gui):connect(function(scale)
		print("gui scale is now", scale)
	end)

	con:disconnect()

	local currentScale = GuiScale.getScale(gui)
]]

local GuiScale = {}
GuiScale.__index = GuiScale
GuiScale._cache = {}

function GuiScale.getTracker(gui)
	return GuiScale._cache[gui] or GuiScale._new(gui)
end

function GuiScale.getScale(gui)
	return GuiScale.getTracker(gui).scale
end

function GuiScale._new(gui)
	if not gui or not gui:IsA("GuiBase2d") then return nil end
	local self = setmetatable({}, GuiScale)

	self._gui = gui;
	self._listeners = {};

	self._runId = 0;
	self._index = 0;
	self._count = 0;

	self._parentTracker = nil;

	self._uiScale = nil;
	self._uiScaleConn = nil;
	self._uiScaleValue = 1;

	self.scale = 1;

	GuiScale._cache[gui] = self

	-- Setup connections
	self._childAddedConn = gui.ChildAdded:Connect(function(child)
		if self._uiScale or not child:IsA("UIScale") then return end
		self:_setupUIScale()
	end)

	self._childRemovedConn = gui.ChildRemoved:Connect(function(child)
		if self._uiScale ~= child then return end
		self:_setupUIScale()
	end)

	self._ancestryChangedConn = gui.AncestryChanged:Connect(function(child)
		if child ~= gui then return end
		self:_setupParent()
	end)
	
	self._destroyedConn = gui.Destroying:Connect(function()
		self:destroy()
	end)

	-- Initialize
	self:_setupUIScale()
	self:_setupParent()

	return self
end

function GuiScale:_setupUIScale()
	-- Disconnect previous connection if exists
	if self._uiScaleConn then
		self._uiScaleConn:Disconnect()
		self._uiScaleConn = nil
	end

	-- Reset scale values
	self._uiScaleValue = 1

	-- Find UIScale
	self._uiScale = self._gui:FindFirstChildWhichIsA("UIScale")
	if self._uiScale then
		self._uiScaleValue = self._uiScale.Scale

		self._uiScaleConn = self._uiScale.Changed:Connect(function(prop)
			if prop ~= "Scale" then return end
			self._uiScaleValue = self._uiScale.Scale
			self:_updateScale()
		end)
	end

	self:_updateScale()
end

function GuiScale:_setupParent()
	-- Remove from previous parent
	if self._parentTracker then
		self._parentTracker:disconnect(self)
	end

	-- Connect to new parent
	self._parentTracker = GuiScale.getTracker(self._gui.Parent)
	if self._parentTracker then
		self._parentTracker:connect(self, true)
	end

	self:_updateScale()
end

function GuiScale:_updateScale()
	local newScale = 1

	-- Apply parent scale
	if self._parentTracker then
		newScale = self._parentTracker.scale
	end

	-- Apply own scale
	if self._uiScale then
		newScale *= self._uiScaleValue
	end

	-- Only update if changed
	if newScale == self.scale then return end
	self.scale = newScale

	self:_notify()
end

function GuiScale:_notify()
	-- Create new run ID to handle nested calls
	self._runId += 1
	local currentRun = self._runId

	-- Prepare iteration
	self._index = 0
	self._count = #self._listeners

	-- Notify all listeners
	while self._index < self._count do
		if currentRun ~= self._runId then return end

		self._index += 1
		local listener = self._listeners[self._index]

		if type(listener) == "function" then
			listener(self.scale)
		else
			listener:_updateScale()
		end
	end
end

local GuiScaleConnection = {}
GuiScaleConnection.__index = GuiScaleConnection

function GuiScaleConnection.new(tracker, listener)
	return setmetatable({
		tracker  = tracker;
		listener = listener;
	}, GuiScaleConnection)

end

function GuiScaleConnection:disconnect()
	self.tracker:disconnect(self.listener)
end

function GuiScale:connect(listener, _noConnection)
	table.insert(self._listeners, listener)
	if _noConnection then return end
	return GuiScaleConnection.new(self, listener)
end

function GuiScale:disconnect(listener)
	local foundIndex = table.find(self._listeners, listener)
	if not foundIndex then return end

	table.remove(self._listeners, foundIndex)

	-- Update iteration indices if we're in the middle of notifying
	if foundIndex <= self._index then self._index -= 1 end
	if foundIndex <= self._count then self._count -= 1 end

	-- Clean up if no more listeners
	if #self._listeners == 0 then
		self:destroy()
	end
end

function GuiScale:destroy()
	-- Remove from cache
	GuiScale._cache[self._gui] = nil

	-- Disconnect all connections
	self._childAddedConn:Disconnect()
	self._childRemovedConn:Disconnect()
	self._ancestryChangedConn:Disconnect()
	self._destroyedConn:Disconnect()

	if self._uiScaleConn then
		self._uiScaleConn:Disconnect()
	end

	if self._parentTracker then
		self._parentTracker:disconnect(self)
	end
end

return GuiScale

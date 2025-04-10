local ScaleTracker = {}
ScaleTracker.__index = ScaleTracker
ScaleTracker._cache = {}

function ScaleTracker.getTracker(gui)
	return ScaleTracker._cache[gui] or ScaleTracker._new(gui)
end

function ScaleTracker.getScale(gui)
	return ScaleTracker.getTracker(gui).scale
end

function ScaleTracker._new(gui)
	if not gui or not gui:IsA("GuiBase2d") then return nil end

	local self = setmetatable({
		_gui = gui;
		_listeners = {};
		_runId = 0;
		_index = 0;
		_count = 0;
		_parentTracker = nil;
		_uiScaleValue = 1;
		_uiScaleConn = nil;
		_uiScale = nil;
		scale = 1;
	}, ScaleTracker)

	ScaleTracker._cache[gui] = self

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

function ScaleTracker:_setupUIScale()
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

function ScaleTracker:_setupParent()
	-- Remove from previous parent
	if self._parentTracker then
		self._parentTracker:removeListener(self)
	end

	-- Connect to new parent
	self._parentTracker = ScaleTracker.getTracker(self._gui.Parent)
	if self._parentTracker then
		self._parentTracker:addListener(self)
	end

	self:_updateScale()
end

function ScaleTracker:_updateScale()
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

function ScaleTracker:_notify()
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

function ScaleTracker:addListener(listener)
	table.insert(self._listeners, listener)
	return self
end

function ScaleTracker:removeListener(listener)
	local idx = table.find(self._listeners, listener)
	if not idx then return end

	table.remove(self._listeners, idx)

	-- Update iteration indices if we're in the middle of notifying
	if idx <= self._index then self._index -= 1 end
	if idx <= self._count then self._count -= 1 end

	-- Clean up if no more listeners
	if #self._listeners == 0 then
		self:destroy()
	end
end

function ScaleTracker:destroy()
	-- Remove from cache
	ScaleTracker._cache[self._gui] = nil

	-- Disconnect all connections
	self._childAddedConn:Disconnect()
	self._childRemovedConn:Disconnect()
	self._ancestryChangedConn:Disconnect()
	self._destroyedConn:Disconnect()

	if self._uiScaleConn then
		self._uiScaleConn:Disconnect()
	end

	if self._parentTracker then
		self._parentTracker:removeListener(self)
	end
end

--return ScaleTracker

-- Usage:
--local scaleTracker = ScaleTracker.getTracker(script.Parent)
--local listener = scaleTracker:addListener(function(scale)
--	print("New scale:", scale)
--end)

-- and later:
--scaleTracker:removeListener(listener)

return ScaleTracker

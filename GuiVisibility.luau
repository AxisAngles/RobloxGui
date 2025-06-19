--[[
	Usage:

	local con = GuiVisibility.getTracker(gui):connect(function(isVisible)
		print("gui visibility is now", isVisible)
	end)

	con:disconnect()
]]

local Players = game:GetService("Players")

local GuiVisibility = {}
GuiVisibility.__index = GuiVisibility
GuiVisibility._cache = {}

function GuiVisibility.getTracker(gui)
	return GuiVisibility._cache[gui] or GuiVisibility._new(gui)
end

function GuiVisibility._new(gui)
	if not gui then return nil end
	local self = setmetatable({}, GuiVisibility)

	self._gui = gui
	self._listeners = {}
	self._runId = 0
	self._index = 0
	self._count = 0
	self._parentTracker = nil
	self.visible = false

	-- Cache the GUI type once
	if gui:IsA("GuiObject") then
		self._guiType = "GuiObject"
		self._visibilityValue = gui.Visible
	elseif gui:IsA("ScreenGui") then
		self._guiType = "ScreenGui"
		self._enabledValue = gui.Enabled
		self._hasValidAncestry = gui:IsDescendantOf(Players.LocalPlayer.PlayerGui)
	elseif gui:IsA("BillboardGui") then
		self._guiType = "BillboardGui"
		self._enabledValue = gui.Enabled
		self._hasValidAncestry = gui:IsDescendantOf(workspace)
	elseif gui:IsA("SurfaceGui") then
		self._guiType = "SurfaceGui"
		self._enabledValue = gui.Enabled
		self._hasValidAncestry = gui.Parent and gui.Parent:IsA("BasePart") and gui:IsDescendantOf(workspace)
	elseif gui:IsA("Folder") then
		self._guiType = "inert" -- Folders, etc.
	else
		return nil
	end

	GuiVisibility._cache[gui] = self

	-- Connect events based on type
	if self._guiType == "GuiObject" then
		self._visibilityConn = gui:GetPropertyChangedSignal("Visible"):Connect(function()
			self._visibilityValue = gui.Visible
			self:_updateVisibility()
		end)
		self._parentConn = gui:GetPropertyChangedSignal("Parent"):Connect(function()
			self:_setupParent()
		end)
	elseif self._guiType == "ScreenGui" or self._guiType == "BillboardGui" or self._guiType == "SurfaceGui" then
		self._enabledConn = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
			self._enabledValue = gui.Enabled
			self:_updateVisibility()
		end)
		self._ancestryChangedConn = gui.AncestryChanged:Connect(function()
			self:_updateAncestry()
		end)
	elseif self._guiType == "inert" then
		self._parentConn = gui:GetPropertyChangedSignal("Parent"):Connect(function()
			self:_setupParent()
		end)
	end

	-- Always connect to Destroying
	self._destroyedConn = gui.Destroying:Connect(function()
		self:destroy()
	end)

	-- Initialize
	if self._guiType == "GuiObject" or self._guiType == "inert" then
		self:_setupParent()
	else
		self:_updateVisibility()
	end

	return self
end

function GuiVisibility:_setupParent()
	-- Remove from previous parent
	if self._parentTracker then
		self._parentTracker:disconnect(self)
		self._parentTracker = nil
	end

	-- Find the appropriate parent to track
	self._parentTracker = GuiVisibility.getTracker(self._gui.Parent)
	if self._parentTracker then
		self._parentTracker:connect(self, true)
	end

	self:_updateVisibility()
end

function GuiVisibility:_updateAncestry()
	-- Update cached ancestry for root GUI types
	if self._guiType == "ScreenGui" then
		self._hasValidAncestry = self._gui:IsDescendantOf(Players.LocalPlayer.PlayerGui)
	elseif self._guiType == "BillboardGui" then
		self._hasValidAncestry = self._gui:IsDescendantOf(workspace)
	elseif self._guiType == "SurfaceGui" then
		self._hasValidAncestry = self._gui.Parent and self._gui.Parent:IsA("BasePart") and self._gui:IsDescendantOf(workspace)
	end
	self:_updateVisibility()
end

function GuiVisibility:_updateVisibility()
	local newVisible = true

	if self._guiType == "GuiObject" then
		-- Check own visibility and parent visibility
		if not self._visibilityValue then
			newVisible = false
		elseif self._parentTracker then
			newVisible = self._parentTracker.visible
		else
			newVisible = false -- No valid parent
		end
	elseif self._guiType == "ScreenGui" or self._guiType == "BillboardGui" or self._guiType == "SurfaceGui" then
		-- Check enabled state and cached ancestry
		newVisible = self._enabledValue and self._hasValidAncestry
	elseif self._guiType == "inert" then
		-- Inert objects are visible if their parent is visible
		newVisible = self._parentTracker and self._parentTracker.visible or false
	end

	-- Only update if changed
	if newVisible == self.visible then return end
	self.visible = newVisible
	self:_notify()
end

function GuiVisibility:_notify()
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
			listener(self.visible)
		else
			listener:_updateVisibility()
		end
	end
end

local GuiVisibilityConnection = {}
GuiVisibilityConnection.__index = GuiVisibilityConnection

function GuiVisibilityConnection.new(tracker, listener)
	return setmetatable({
		tracker  = tracker;
		listener = listener;
	}, GuiVisibilityConnection)
end

function GuiVisibilityConnection:disconnect()
	self.tracker:disconnect(self.listener)
end

function GuiVisibility:connect(listener, _noConnection)
	table.insert(self._listeners, listener)
	if _noConnection then return end
	return GuiVisibilityConnection.new(self, listener)
end

function GuiVisibility:disconnect(listener)
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

function GuiVisibility:destroy()
	-- Remove from cache
	GuiVisibility._cache[self._gui] = nil

	-- Disconnect all connections
	if self._visibilityConn then
		self._visibilityConn:Disconnect()
	end
	if self._enabledConn then
		self._enabledConn:Disconnect()
	end
	if self._parentConn then
		self._parentConn:Disconnect()
	end
	if self._ancestryChangedConn then
		self._ancestryChangedConn:Disconnect()
	end
	if self._destroyedConn then
		self._destroyedConn:Disconnect()
	end

	if self._parentTracker then
		self._parentTracker:disconnect(self)
	end
end

return GuiVisibility

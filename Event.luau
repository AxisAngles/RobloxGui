--[[
	By default, this event has deferred behavior.
	If skipSupersededFires is true, then it expresses immediate-like behavior,
		immediately canceling the current fire loop, firing with only the new arguments.
	This is useful for implementing Changed events where we don't want to fire with outdated args.
]]

local Event = {}
Event.__index = Event

function Event.new(skipSupersededFires)
	local self = setmetatable({}, Event)

	self._deferred = not skipSupersededFires

	self._listeners = {}
	self._index = 0
	self._count = 0

	self._pendingArgs = {}

	return self
end

local ChangedEventConnection = {}
ChangedEventConnection.__index = ChangedEventConnection

function ChangedEventConnection.new(event, listener)
	return setmetatable({
		event  = event;
		listener = listener;
	}, ChangedEventConnection)
end

function ChangedEventConnection:disconnect()
	self.event:disconnect(self.listener)
end

function Event:connect(listener, _noConnection)
	table.insert(self._listeners, listener)
	if _noConnection then return end
	return ChangedEventConnection.new(self, listener)
end

function Event:disconnect(listener)
	local foundIndex = table.find(self._listeners, listener)
	if not foundIndex then return end

	table.remove(self._listeners, foundIndex)

	-- Update iteration indices if we're in the middle of firing
	if foundIndex <= self._index then self._index -= 1 end
	if foundIndex <= self._count then self._count -= 1 end
end

function Event:fire(...)
	-- we we are in the middle of firing, 
	if self._deferred and self._index < self._count then
		local args = {n = select("#", ...); ...}
		table.insert(self._pendingArgs, args)
		return
	end

	self:_fireLoop(...)

	while self._pendingArgs[1] do
		local args = table.remove(self._pendingArgs, 1)
		self:_fireLoop(table.unpack(args, 1, args.n))
	end
end

function Event:_fireLoop(...)
	self._index = 0
	self._count = #self._listeners

	while self._index < self._count do
		self._index += 1
		local listener = self._listeners[self._index]
		listener(...)
	end
end


return Event

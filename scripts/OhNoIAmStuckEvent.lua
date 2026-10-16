-- Syncs Oh No I Am Stuck state (enabled, strength) between clients and server.

OhNoIAmStuckEvent = {}
local OhNoIAmStuckEvent_mt = Class(OhNoIAmStuckEvent, Event)

InitEventClass(OhNoIAmStuckEvent, "OhNoIAmStuckEvent")

function OhNoIAmStuckEvent.emptyNew()
    return Event.new(OhNoIAmStuckEvent_mt)
end

function OhNoIAmStuckEvent.new(vehicle, isActive, strengthIndex)
    local self = OhNoIAmStuckEvent.emptyNew()
    self.vehicle = vehicle
    self.isActive = isActive
    self.strengthIndex = strengthIndex
    return self
end

function OhNoIAmStuckEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.isActive = streamReadBool(streamId)
    self.strengthIndex = streamReadUIntN(streamId, 3)
    self:run(connection)
end

function OhNoIAmStuckEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteBool(streamId, self.isActive)
    streamWriteUIntN(streamId, self.strengthIndex, 3)
end

function OhNoIAmStuckEvent:run(connection)
    if not connection:getIsServer() then
        g_server:broadcastEvent(self, false, connection, self.vehicle)
    end

    if self.vehicle ~= nil and self.vehicle:getIsSynchronized() then
        self.vehicle:setOhNoIAmStuckState(self.isActive, self.strengthIndex, true)
    end
end

function OhNoIAmStuckEvent.sendEvent(vehicle, isActive, strengthIndex, noEventSend)
    if noEventSend == nil or noEventSend == false then
        if g_server ~= nil then
            g_server:broadcastEvent(OhNoIAmStuckEvent.new(vehicle, isActive, strengthIndex), nil, nil, vehicle)
        else
            g_client:getServerConnection():sendEvent(OhNoIAmStuckEvent.new(vehicle, isActive, strengthIndex))
        end
    end
end

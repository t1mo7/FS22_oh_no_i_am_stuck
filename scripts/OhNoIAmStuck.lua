-- OhNoIAmStuck
-- When you're stuck, turn this on and your throttle drives every wheel of the combination:
-- the tractor's differentials lock and every wheel of attached trailers and implements
-- gets drive torque in the direction you're driving.

OhNoIAmStuck = {}

OhNoIAmStuck.MOD_NAME = g_currentModName
OhNoIAmStuck.SPEC_NAME = g_currentModName .. ".ohNoIAmStuck"
OhNoIAmStuck.SPEC_TABLE_NAME = "spec_" .. OhNoIAmStuck.SPEC_NAME

-- factor = share of a trailer's own weight that its wheels may push with at full throttle
OhNoIAmStuck.STRENGTHS = {
    { textKey = "ohNoIAmStuck_low", factor = 0.2 },
    { textKey = "ohNoIAmStuck_medium", factor = 0.35 },
    { textKey = "ohNoIAmStuck_high", factor = 0.5 }
}
OhNoIAmStuck.STRENGTH_DEFAULT = 2

OhNoIAmStuck.FULL_ASSIST_SPEED = 8 -- km/h, full trailer torque below this speed
OhNoIAmStuck.CUTOFF_SPEED = 12 -- km/h, no trailer torque and diff locks open above this speed
OhNoIAmStuck.DIFF_UNLOCK_HYSTERESIS = 3 -- km/h above cutoff before diff locks open again
OhNoIAmStuck.MAX_WHEEL_SPEED = 25 -- km/h wheel surface speed, stops a lifted / spinning wheel from running away
OhNoIAmStuck.MIN_PEDAL = 0.05
OhNoIAmStuck.GRAVITY = 9.81

-- wheel -> torque we currently apply (server only); used to re-apply it when the game rewrites the wheel's physics props
OhNoIAmStuck.wheelTorques = {}

function OhNoIAmStuck.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Drivable, specializations)
        and SpecializationUtil.hasSpecialization(Motorized, specializations)
        and SpecializationUtil.hasSpecialization(Wheels, specializations)
end

function OhNoIAmStuck.initSpecialization()
    local schemaSavegame = Vehicle.xmlSchemaSavegame
    local key = "vehicles.vehicle(?)." .. OhNoIAmStuck.SPEC_NAME
    schemaSavegame:register(XMLValueType.INT, key .. "#strength", "Oh No I Am Stuck strength level", OhNoIAmStuck.STRENGTH_DEFAULT)
end

function OhNoIAmStuck.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "setOhNoIAmStuckState", OhNoIAmStuck.setOhNoIAmStuckState)
    SpecializationUtil.registerFunction(vehicleType, "getOhNoIAmStuckPedal", OhNoIAmStuck.getOhNoIAmStuckPedal)
    SpecializationUtil.registerFunction(vehicleType, "getOhNoIAmStuckWheels", OhNoIAmStuck.getOhNoIAmStuckWheels)
    SpecializationUtil.registerFunction(vehicleType, "setOhNoIAmStuckDiffsLocked", OhNoIAmStuck.setOhNoIAmStuckDiffsLocked)
end

function OhNoIAmStuck.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateVehiclePhysics", OhNoIAmStuck.updateVehiclePhysics)
end

function OhNoIAmStuck.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", OhNoIAmStuck)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", OhNoIAmStuck)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", OhNoIAmStuck)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", OhNoIAmStuck)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", OhNoIAmStuck)
    SpecializationUtil.registerEventListener(vehicleType, "onPostUpdate", OhNoIAmStuck)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", OhNoIAmStuck)
end

function OhNoIAmStuck:onLoad(savegame)
    local spec = self[OhNoIAmStuck.SPEC_TABLE_NAME]

    spec.isActive = false
    spec.strengthIndex = OhNoIAmStuck.STRENGTH_DEFAULT
    spec.lastAxisForward = 0
    spec.diffsLocked = false
    spec.appliedWheels = {} -- wheel -> vehicle owning it
    spec.actionEvents = {}

    if savegame ~= nil and not savegame.resetVehicles then
        local key = savegame.key .. "." .. OhNoIAmStuck.SPEC_NAME
        spec.strengthIndex = savegame.xmlFile:getValue(key .. "#strength", spec.strengthIndex)
        spec.strengthIndex = MathUtil.clamp(spec.strengthIndex, 1, #OhNoIAmStuck.STRENGTHS)
    end
end

function OhNoIAmStuck:onDelete()
    local spec = self[OhNoIAmStuck.SPEC_TABLE_NAME]
    if spec == nil or spec.appliedWheels == nil then
        return
    end

    for wheel, vehicle in pairs(spec.appliedWheels) do
        OhNoIAmStuck.releaseWheel(vehicle, wheel)
    end
    spec.appliedWheels = {}
end

-- The on/off state is deliberately not saved: the assist should be a conscious choice each time you get stuck.
function OhNoIAmStuck:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self[OhNoIAmStuck.SPEC_TABLE_NAME]
    xmlFile:setValue(key .. "#strength", spec.strengthIndex)
end

function OhNoIAmStuck:onReadStream(streamId, connection)
    local isActive = streamReadBool(streamId)
    local strengthIndex = streamReadUIntN(streamId, 3)
    self:setOhNoIAmStuckState(isActive, strengthIndex, true)
end

function OhNoIAmStuck:onWriteStream(streamId, connection)
    local spec = self[OhNoIAmStuck.SPEC_TABLE_NAME]
    streamWriteBool(streamId, spec.isActive)
    streamWriteUIntN(streamId, spec.strengthIndex, 3)
end

function OhNoIAmStuck:setOhNoIAmStuckState(isActive, strengthIndex, noEventSend)
    local spec = self[OhNoIAmStuck.SPEC_TABLE_NAME]

    strengthIndex = MathUtil.clamp(strengthIndex, 1, #OhNoIAmStuck.STRENGTHS)
    if spec.isActive == isActive and spec.strengthIndex == strengthIndex then
        return
    end

    OhNoIAmStuckEvent.sendEvent(self, isActive, strengthIndex, noEventSend)

    spec.isActive = isActive
    spec.strengthIndex = strengthIndex

    OhNoIAmStuck.updateActionEventTexts(self)
end

-- Remember the throttle input actually fed into the vehicle physics (also covers ThrottleHold and other mods feeding it).
function OhNoIAmStuck:updateVehiclePhysics(superFunc, axisForward, axisSide, doHandbrake, dt)
    local spec = self[OhNoIAmStuck.SPEC_TABLE_NAME]
    spec.lastAxisForward = axisForward or 0
    return superFunc(self, axisForward, axisSide, doHandbrake, dt)
end

-- Signed throttle in the tractor's own frame: positive drives towards the tractor's front, negative towards its back.
-- Zero while braking, coasting, in neutral or with the engine off.
function OhNoIAmStuck:getOhNoIAmStuckPedal()
    local spec = self[OhNoIAmStuck.SPEC_TABLE_NAME]

    if not self:getIsMotorStarted() then
        return 0
    end

    local motor = self:getMotor()
    if motor == nil then
        return 0
    end

    -- lastAcceleratorPedal is what the motor really got (0 while braking, includes cruise control); fall back to raw input
    local pedal = motor.lastAcceleratorPedal
    if pedal == nil then
        pedal = spec.lastAxisForward
    end

    local throttle = math.min(math.abs(pedal), 1)
    if throttle < OhNoIAmStuck.MIN_PEDAL then
        return 0
    end

    local direction
    if motor.getGearRatio ~= nil then
        local gearRatio = motor:getGearRatio()
        if gearRatio == nil or gearRatio == 0 then
            return 0
        end
        direction = gearRatio > 0 and 1 or -1
    else
        direction = pedal >= 0 and 1 or -1
    end

    return throttle * direction
end

-- All wheels of attached, non-motorized vehicles (trailers, dollies, implements) behind this tractor.
-- Returns a list of { vehicle = ..., wheel = ... }.
function OhNoIAmStuck:getOhNoIAmStuckWheels()
    local result = {}

    local vehicles
    if self.getChildVehicles ~= nil then
        vehicles = self:getChildVehicles()
    else
        vehicles = {}
        OhNoIAmStuck.collectAttachedVehicles(self, vehicles)
    end

    for _, vehicle in pairs(vehicles) do
        if vehicle ~= self and vehicle.spec_motorized == nil and vehicle.spec_wheels ~= nil and vehicle.isDeleted ~= true then
            for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
                if wheel.wheelShapeCreated ~= false and wheel.wheelShape ~= nil and wheel.wheelShape ~= 0 and wheel.node ~= nil then
                    table.insert(result, { vehicle = vehicle, wheel = wheel })
                end
            end
        end
    end

    return result
end

function OhNoIAmStuck.collectAttachedVehicles(vehicle, vehicles)
    table.insert(vehicles, vehicle)
    if vehicle.getAttachedImplements ~= nil then
        for _, implement in pairs(vehicle:getAttachedImplements()) do
            if implement.object ~= nil then
                OhNoIAmStuck.collectAttachedVehicles(implement.object, vehicles)
            end
        end
    end
end

-- Locking the differentials makes every driven wheel of the tractor turn at the same speed.
function OhNoIAmStuck:setOhNoIAmStuckDiffsLocked(locked)
    local spec = self[OhNoIAmStuck.SPEC_TABLE_NAME]
    if spec.diffsLocked == locked then
        return
    end
    spec.diffsLocked = locked

    local motorizedSpec = self.spec_motorized
    if updateDifferential == nil or motorizedSpec == nil or motorizedSpec.motorizedNode == nil or motorizedSpec.differentials == nil then
        return
    end

    for i, differential in ipairs(motorizedSpec.differentials) do
        if differential.torqueRatio ~= nil and differential.maxSpeedRatio ~= nil then
            local maxSpeedRatio = locked and 1 or differential.maxSpeedRatio
            updateDifferential(motorizedSpec.motorizedNode, i - 1, differential.torqueRatio, maxSpeedRatio)
        end
    end
end

function OhNoIAmStuck.getSpeedFade(speed)
    if speed <= OhNoIAmStuck.FULL_ASSIST_SPEED then
        return 1
    elseif speed >= OhNoIAmStuck.CUTOFF_SPEED then
        return 0
    end
    return (OhNoIAmStuck.CUTOFF_SPEED - speed) / (OhNoIAmStuck.CUTOFF_SPEED - OhNoIAmStuck.FULL_ASSIST_SPEED)
end

function OhNoIAmStuck.applyWheelTorque(wheel, torque)
    OhNoIAmStuck.wheelTorques[wheel] = torque
    setWheelShapeProps(wheel.node, wheel.wheelShape, torque, 0, wheel.steeringAngle or 0, wheel.rotationDamping or 0)
end

function OhNoIAmStuck.releaseWheel(vehicle, wheel)
    OhNoIAmStuck.wheelTorques[wheel] = nil

    if vehicle.isDeleted == true or wheel.node == nil or not entityExists(wheel.node) then
        return
    end

    setWheelShapeProps(wheel.node, wheel.wheelShape, 0, 0, wheel.steeringAngle or 0, wheel.rotationDamping or 0)

    -- force the vehicle to re-send its brake state to the wheels on the next brake update
    local wheelsSpec = vehicle.spec_wheels
    if wheelsSpec ~= nil and type(wheelsSpec.brakePedal) == "number" then
        wheelsSpec.brakePedal = -1
    end
end

function OhNoIAmStuck:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = self[OhNoIAmStuck.SPEC_TABLE_NAME]
    if not spec.isActive then
        return
    end

    if self.getIsEntered ~= nil and self:getIsEntered() then
        local strength = g_i18n:getText(OhNoIAmStuck.STRENGTHS[spec.strengthIndex].textKey)
        local numWheels = #self:getOhNoIAmStuckWheels()
        g_currentMission:addExtraPrintText(string.format(g_i18n:getText("ohNoIAmStuck_activeInfo"), strength, numWheels))
    end
end

-- Physics side, server only. Runs after the vehicle's own physics update so our wheel torques win.
function OhNoIAmStuck:onPostUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    if not self.isServer then
        return
    end

    local spec = self[OhNoIAmStuck.SPEC_TABLE_NAME]
    -- only the front vehicle of a combination drives it; a towed tractor's assist stays idle
    local isRoot = self.rootVehicle == nil or self.rootVehicle == self
    local isApplying = spec.isActive and isRoot
    local speed = self:getLastSpeed()

    if isApplying and speed < OhNoIAmStuck.CUTOFF_SPEED then
        self:setOhNoIAmStuckDiffsLocked(true)
    elseif not isApplying or speed > OhNoIAmStuck.CUTOFF_SPEED + OhNoIAmStuck.DIFF_UNLOCK_HYSTERESIS then
        self:setOhNoIAmStuckDiffsLocked(false)
    end

    local newWheels = {}

    local pedal = isApplying and self:getOhNoIAmStuckPedal() or 0
    local fade = OhNoIAmStuck.getSpeedFade(speed)

    if pedal ~= 0 and fade > 0 then
        local factor = OhNoIAmStuck.STRENGTHS[spec.strengthIndex].factor
        local tractorNode = self.components[1].node
        local tractorDirX, tractorDirY, tractorDirZ = localDirectionToWorld(tractorNode, 0, 0, 1)

        local entries = self:getOhNoIAmStuckWheels()

        -- the vehicle's weight is shared by its wheels
        local wheelsPerVehicle = {}
        for _, entry in ipairs(entries) do
            wheelsPerVehicle[entry.vehicle] = (wheelsPerVehicle[entry.vehicle] or 0) + 1
        end

        for _, entry in ipairs(entries) do
            local vehicle, wheel = entry.vehicle, entry.wheel

            local mass = vehicle.getTotalMass ~= nil and vehicle:getTotalMass(true) or 0
            -- t * m/s^2 = kN, * m = kNm
            local force = mass * OhNoIAmStuck.GRAVITY * factor / wheelsPerVehicle[vehicle]
            local torque = force * (wheel.radius or 0.5) * pedal * fade

            -- push along the trailer's own axis; a trailer at an angle gets proportionally less
            local wheelDirX, wheelDirY, wheelDirZ = localDirectionToWorld(wheel.node, 0, 0, 1)
            torque = torque * (wheelDirX * tractorDirX + wheelDirY * tractorDirY + wheelDirZ * tractorDirZ)

            if getWheelShapeAxleSpeed ~= nil then
                local axleSpeed = getWheelShapeAxleSpeed(wheel.node, wheel.wheelShape) or 0
                if math.abs(axleSpeed) * (wheel.radius or 0.5) * 3.6 > OhNoIAmStuck.MAX_WHEEL_SPEED then
                    torque = 0
                end
            end

            OhNoIAmStuck.applyWheelTorque(wheel, torque)
            newWheels[wheel] = vehicle
        end
    end

    -- wheels we drove last frame but not anymore (throttle released, trailer detached, assist off)
    for wheel, vehicle in pairs(spec.appliedWheels) do
        if newWheels[wheel] == nil then
            OhNoIAmStuck.releaseWheel(vehicle, wheel)
        end
    end
    spec.appliedWheels = newWheels
end

-- The game may rewrite a wheel's physics props (brakes, steering) after we set them; put our torque back.
if WheelsUtil ~= nil and WheelsUtil.updateWheelPhysics ~= nil then
    WheelsUtil.updateWheelPhysics = Utils.appendedFunction(WheelsUtil.updateWheelPhysics, function(vehicle, wheel, ...)
        if type(wheel) == "table" then
            local torque = OhNoIAmStuck.wheelTorques[wheel]
            if torque ~= nil then
                OhNoIAmStuck.applyWheelTorque(wheel, torque)
            end
        end
    end)
end

function OhNoIAmStuck:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if not self.isClient then
        return
    end

    local spec = self[OhNoIAmStuck.SPEC_TABLE_NAME]
    self:clearActionEventsTable(spec.actionEvents)

    if isActiveForInputIgnoreSelection then
        local _, toggleId = self:addActionEvent(spec.actionEvents, InputAction.OHNOIAMSTUCK_TOGGLE, self, OhNoIAmStuck.actionEventToggle, false, true, false, true, nil)
        g_inputBinding:setActionEventTextPriority(toggleId, GS_PRIO_HIGH)
        spec.toggleActionEventId = toggleId

        local _, strengthId = self:addActionEvent(spec.actionEvents, InputAction.OHNOIAMSTUCK_STRENGTH, self, OhNoIAmStuck.actionEventStrength, false, true, false, true, nil)
        g_inputBinding:setActionEventTextPriority(strengthId, GS_PRIO_NORMAL)
        spec.strengthActionEventId = strengthId

        OhNoIAmStuck.updateActionEventTexts(self)
    end
end

function OhNoIAmStuck:updateActionEventTexts()
    local spec = self[OhNoIAmStuck.SPEC_TABLE_NAME]
    local strength = g_i18n:getText(OhNoIAmStuck.STRENGTHS[spec.strengthIndex].textKey)

    if spec.toggleActionEventId ~= nil then
        local textKey = spec.isActive and "ohNoIAmStuck_disable" or "ohNoIAmStuck_enable"
        g_inputBinding:setActionEventText(spec.toggleActionEventId, string.format(g_i18n:getText(textKey), strength))
    end

    if spec.strengthActionEventId ~= nil then
        g_inputBinding:setActionEventText(spec.strengthActionEventId, string.format(g_i18n:getText("ohNoIAmStuck_strength"), strength))
    end
end

function OhNoIAmStuck.actionEventToggle(self, actionName, inputValue, callbackState, isAnalog)
    local spec = self[OhNoIAmStuck.SPEC_TABLE_NAME]
    self:setOhNoIAmStuckState(not spec.isActive, spec.strengthIndex)
end

function OhNoIAmStuck.actionEventStrength(self, actionName, inputValue, callbackState, isAnalog)
    local spec = self[OhNoIAmStuck.SPEC_TABLE_NAME]
    local strengthIndex = spec.strengthIndex % #OhNoIAmStuck.STRENGTHS + 1
    self:setOhNoIAmStuckState(spec.isActive, strengthIndex)
end

-- Adds the ohNoIAmStuck specialization to every drivable, motorized vehicle type.

local modName = g_currentModName
local specName = modName .. ".ohNoIAmStuck"

local function addOhNoIAmStuckSpecialization(typeManager)
    if typeManager.typeName ~= "vehicle" then
        return
    end

    local numAdded = 0
    for typeName, typeEntry in pairs(typeManager:getTypes()) do
        if typeEntry.specializationsByName["drivable"] ~= nil
            and typeEntry.specializationsByName["motorized"] ~= nil
            and typeEntry.specializationsByName["wheels"] ~= nil
            and typeEntry.specializationsByName[specName] == nil then
            typeManager:addSpecialization(typeName, specName)
            numAdded = numAdded + 1
        end
    end

    print(string.format("[OhNoIAmStuck] Added to %d vehicle types", numAdded))
end

TypeManager.finalizeTypes = Utils.prependedFunction(TypeManager.finalizeTypes, addOhNoIAmStuckSpecialization)

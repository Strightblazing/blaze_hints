-- Shared helpers (client + server): coords and where things sit on world scenes
Util = {}

function Util.Vec(c)
    local t = type(c)
    if t ~= 'table' and t ~= 'vector3' and t ~= 'vector4' then return end
    if not c.x or not c.y or not c.z then return end
    return vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0)
end

function Util.Heading(c)
    if type(c) ~= 'table' and type(c) ~= 'vector4' then return 0.0 end
    return (tonumber(c.w) or tonumber(c.heading) or 0.0) + 0.0
end

--- A point offset { right, forward, up } from coords c, turned by its heading
function Util.Offset(c, right, forward, up)
    local h = math.rad(Util.Heading(c))
    local cs, sn = math.cos(h), math.sin(h)
    return vector3(c.x + right * cs - forward * sn, c.y + right * sn + forward * cs, c.z + (up or 0.0))
end

--- Scene coords: its own, else the step's
function Util.SceneCoords(scene, step)
    if type(scene) ~= 'table' then return end
    if Util.Vec(scene.coords) then return scene.coords end
    if step and Util.Vec(step.coords) then return step.coords end
end

--- Where an inspect point / stash sits on a scene
function Util.SceneSpot(scene, step)
    local c = Util.SceneCoords(scene, step)
    if not c then return end
    local preset = Config.ScenePresets[scene.preset]
    local o = preset and preset.spot or { 0.0, 0.0, 0.0 }
    return Util.Offset(c, o[1], o[2], o[3])
end

function Util.HasScene(step)
    return type(step) == 'table' and type(step.scene) == 'table' and Config.ScenePresets[step.scene.preset] ~= nil
end

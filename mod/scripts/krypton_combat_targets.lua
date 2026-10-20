local Targets = {}

-- Shared by heat vision, frost-breath freezing and Rao's Edge splash damage.
-- Explicit melee hits still follow the game's normal targeting rules.
Targets.EXCLUDE_TAGS = {
    "INLIMBO", "player", "playerghost", "companion", "wall", "structure",
    "FX", "notarget", "invisible", "player_aligned", "domesticated",
}

function Targets.IsProtected(target)
    if target == nil or not target:IsValid() then return true end
    for _, tag in ipairs(Targets.EXCLUDE_TAGS) do
        if target:HasTag(tag) then return true end
    end
    return target.components.follower ~= nil and target.components.follower.leader ~= nil
end

return Targets

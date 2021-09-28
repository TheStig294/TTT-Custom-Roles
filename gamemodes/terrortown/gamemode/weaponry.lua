include("weaponry_shd.lua") -- inits WEPS tbl

---- Weapon system, pickup limits, etc

local IsEquipment = WEPS.IsEquipment

-- Prevent players from picking up multiple weapons of the same type etc
function GM:PlayerCanPickupWeapon(ply, wep)
    if not IsValid(wep) or not IsValid(ply) then return end
    if ply:IsSpec() then return false end

    -- Disallow picking up for ammo
    if ply:HasWeapon(wep:GetClass()) then
        return false
    elseif not ply:GetHypnotist() and wep:GetClass() == "weapon_hyp_brainwash" then
        return false
    elseif not ply:GetBodysnatcher() and wep:GetClass() == "weapon_bod_bodysnatch" then
        return false
    elseif not ply:GetKiller() and (wep:GetClass() == "weapon_kil_knife" or wep:GetClass() == "weapon_kil_crowbar") then
        return false
    elseif not ply:GetVampire() and wep:GetClass() == "weapon_vam_fangs" then
        return false
    elseif not ply:GetZombie() and wep:GetClass() == "weapon_zom_claws" then
        return false
    elseif not ply:CanCarryWeapon(wep) then
        return false
    elseif IsEquipment(wep) and wep.IsDropped and (not ply:KeyDown(IN_USE)) then
        return false
    elseif GetConVar("ttt_zombie_prime_only_weapons"):GetBool() and ply:GetZombie() and not ply:GetZombiePrime() and wep:GetClass() ~= "weapon_zom_claws" and GetRoundState() == ROUND_ACTIVE then
        return false
    end

    local tr = util.TraceEntity({ start = wep:GetPos(), endpos = ply:GetShootPos(), mask = MASK_SOLID }, wep)
    if tr.Fraction == 1.0 or tr.Entity == ply then
        wep:SetPos(ply:GetShootPos())
    end

    return true
end

-- Cache role -> default-weapons table
local loadout_weapons = nil
local function GetLoadoutWeapons(r)
    if not loadout_weapons then
        local tbl = {}
        -- Initialize the table for every role
        for wrole = 0, ROLE_MAX do
            tbl[wrole] = {}
            if wrole >= ROLE_EXTERNAL_START and ROLE_LOADOUT_ITEMS[wrole] then
                for _, v in pairs(ROLE_LOADOUT_ITEMS[wrole]) do
                    if weapons.GetStored(v) then
                        table.insert(tbl[wrole], v)
                    end
                end
            end
        end

        for _, w in pairs(weapons.GetList()) do
            local weap_class = WEPS.GetClass(w)
            if weap_class == "weapon_ttt_unarmed" or weap_class == "weapon_zm_carry" or weap_class == "weapon_zm_improvised" then
                for wrole = 0, ROLE_MAX do
                    table.insert(tbl[wrole], weap_class)
                end
            elseif w and istable(w.InLoadoutFor) then
                for _, wrole in pairs(w.InLoadoutFor) do
                    table.insert(tbl[wrole], weap_class)
                end
            end
        end

        loadout_weapons = tbl
    end

    return loadout_weapons[r]
end

-- Give player loadout weapons he should have for his role that he does not have
-- yet
local function GiveLoadoutWeapons(ply)
    local r = GetRoundState() == ROUND_PREP and ROLE_INNOCENT or ply:GetRole()
    local weps = GetLoadoutWeapons(r)
    if not weps then return end

    for _, cls in pairs(weps) do
        if not ply:HasWeapon(cls) and ply:CanCarryType(WEPS.TypeForWeapon(cls)) then
            ply:Give(cls)
        end
    end
end

local function HasLoadoutWeapons(ply)
    if ply:IsSpec() then return true end

    local r = GetRoundState() == ROUND_PREP and ROLE_INNOCENT or ply:GetRole()
    local weps = GetLoadoutWeapons(r)
    if not weps then return true end

    for _, cls in pairs(weps) do
        if not ply:HasWeapon(cls) and ply:CanCarryType(WEPS.TypeForWeapon(cls)) then
            return false
        end
    end

    return true
end

-- Give loadout items.
local function GiveLoadoutItems(ply)
    local loadout_items = {}
    local role = ply:GetRole()

    local items = EquipmentItems[role]
    if items then
        for _, item in pairs(items) do
            if item.loadout and item.id then
                table.insert(loadout_items, item.id)
            end
        end
    end

    local ext_items = ROLE_LOADOUT_ITEMS[role]
    if ext_items then
        for _, item in pairs(ext_items) do
            if not weapons.GetStored(item) then
                local equip = GetEquipmentItemByName(item)
                if equip ~= nil then
                    table.insert(loadout_items, equip.id)
                end
            end
        end
    end

    for _, id in pairs(loadout_items) do
        ply:GiveEquipmentItem(id)

        hook.Call("TTTOrderedEquipment", GAMEMODE, ply, id, true)
        ply:AddBought(id)

        net.Start("TTT_BoughtItem")
        net.WriteBit(true)
        net.WriteInt(id, 32)
        net.Send(ply)
    end
end

-- Quick hack to limit hats to models that fit them well
local Hattables = { "phoenix.mdl", "arctic.mdl", "Group01", "monk.mdl" }
local function CanWearHat(ply)
    local path = string.Explode("/", ply:GetModel())
    if #path == 1 then path = string.Explode("\\", path) end

    return table.HasValue(Hattables, path[3])
end

CreateConVar("ttt_detective_hats", "1")
-- Just hats right now
local function GiveLoadoutSpecial(ply)
    if ply:IsActiveDetectiveTeam() and GetConVar("ttt_detective_hats"):GetBool() and CanWearHat(ply) then

        if not IsValid(ply.hat) then
            local hat = ents.Create("ttt_hat_deerstalker")
            if not IsValid(hat) then return end

            hat:SetPos(ply:GetPos() + Vector(0, 0, 70))
            hat:SetAngles(ply:GetAngles())

            hat:SetParent(ply)

            ply.hat = hat

            hat:Spawn()
        end
    else
        SafeRemoveEntity(ply.hat)

        ply.hat = nil
    end
end

-- Sometimes, in cramped map locations, giving players weapons fails. A timer
-- calling this function is used to get them the weapons anyway as soon as
-- possible.
local function LateLoadout(id)
    local ply = Entity(id)
    if not IsPlayer(ply) then
        timer.Remove("lateloadout" .. id)
        return
    end

    if not HasLoadoutWeapons(ply) then
        GiveLoadoutWeapons(ply)

        if HasLoadoutWeapons(ply) then
            timer.Remove("lateloadout" .. id)
        end
    end
end

-- Note that this is called both when a player spawns and when a round starts
function GM:PlayerLoadout(ply)
    if IsValid(ply) and (not ply:IsSpec()) then
        -- clear out equipment flags
        ply:ResetEquipment()

        -- Don't actually give out the loadout except for while the round is running
        if GetRoundState() == ROUND_ACTIVE then
            -- give default items
            GiveLoadoutItems(ply)

            -- hand out weaponry
            GiveLoadoutWeapons(ply)

            GiveLoadoutSpecial(ply)

            if not HasLoadoutWeapons(ply) then
                MsgN("Could not spawn all loadout weapons for " .. ply:Nick() .. ", will retry.")
                timer.Create("lateloadout" .. ply:EntIndex(), 1, 0,
                        function() LateLoadout(ply:EntIndex()) end)
            end
        end
    end
end

function GM:UpdatePlayerLoadouts()
    for _, ply in ipairs(player.GetAll()) do
        hook.Call("PlayerLoadout", GAMEMODE, ply)
    end
end

---- Weapon dropping

function WEPS.DropNotifiedWeapon(ply, wep, death_drop)
    if IsValid(ply) and IsValid(wep) then
        -- Hack to tell the weapon it's about to be dropped and should do what it
        -- must right now
        if wep.PreDrop then
            wep:PreDrop(death_drop)
        end

        -- PreDrop might destroy weapon
        if not IsValid(wep) then return end

        -- Tag this weapon as dropped, so that if it's a special weapon we do not
        -- auto-pickup when nearby.
        wep.IsDropped = true

        -- After dropping a weapon, always switch to holstered, so that traitors
        -- will never accidentally pull out a traitor weapon.
        --
        -- Perform this *before* the drop in order to abuse the fact that this
        -- holsters the weapon, which in turn aborts any reload that's in
        -- progress. We don't want a dropped weapon to be in a reloading state
        -- because the relevant timer is reset when picking it up, making the
        -- reload happen instantly. This allows one to dodge the delay by dropping
        -- during reload. All of this is a workaround for not having access to
        -- CBaseWeapon::AbortReload() (and that not being handled in
        -- CBaseWeapon::Drop in the first place).
        ply:SelectWeapon("weapon_ttt_unarmed")

        ply:DropWeapon(wep)

        wep:PhysWake()
    end
end

local function DropActiveWeapon(ply)
    if not IsValid(ply) then return end

    local wep = ply:GetActiveWeapon()

    if not IsValid(wep) then return end

    if wep.AllowDrop == false then
        return
    end

    local tr = util.QuickTrace(ply:GetShootPos(), ply:GetAimVector() * 32, ply)

    if tr.HitWorld then
        LANG.Msg(ply, "drop_no_room")
        return
    end

    ply:AnimPerformGesture(ACT_GMOD_GESTURE_ITEM_PLACE)

    WEPS.DropNotifiedWeapon(ply, wep)
end
concommand.Add("ttt_dropweapon", DropActiveWeapon)

local function DropActiveAmmo(ply)
    if not IsValid(ply) then return end

    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return end

    if not wep.AmmoEnt then return end

    local amt = wep:Clip1()
    if amt < 1 or amt <= (wep.Primary.ClipSize * 0.25) then
        LANG.Msg(ply, "drop_no_ammo")
        return
    end

    local pos, ang = ply:GetShootPos(), ply:EyeAngles()
    local dir = (ang:Forward() * 32) + (ang:Right() * 6) + (ang:Up() * -5)

    local tr = util.QuickTrace(pos, dir, ply)
    if tr.HitWorld then return end

    wep:SetClip1(0)

    ply:AnimPerformGesture(ACT_GMOD_GESTURE_ITEM_GIVE)

    local box = ents.Create(wep.AmmoEnt)
    if not IsValid(box) then return end

    box:SetPos(pos + dir)
    box:SetOwner(ply)
    box:Spawn()

    box:PhysWake()

    local phys = box:GetPhysicsObject()
    if IsValid(phys) then
        phys:ApplyForceCenter(ang:Forward() * 1000)
        phys:ApplyForceOffset(VectorRand(), vector_origin)
    end

    box.AmmoAmount = amt

    timer.Simple(2, function()
        if IsValid(box) then
            box:SetOwner(nil)
        end
    end)
end
concommand.Add("ttt_dropammo", DropActiveAmmo)


-- Give a weapon to a player. If the initial attempt fails due to heisenbugs in
-- the map, keep trying until the player has moved to a better spot where it
-- does work.
local function GiveEquipmentWeapon(sid, cls)
    -- Referring to players by SteamID because a player may disconnect while his
    -- unique timer still runs, in which case we want to be able to stop it. For
    -- that we need its name, and hence his SteamID.
    local ply = player.GetBySteamID64(sid)
    local tmr = "give_equipment" .. sid

    if (not IsValid(ply)) or (not ply:IsShopRole(true)) then
        timer.Remove(tmr)
        return
    end

    -- giving attempt, will fail if we're in a crazy spot in the map or perhaps
    -- other glitchy cases
    local w = ply:Give(cls)

    if (not IsValid(w)) or (not ply:HasWeapon(cls)) then
        if not timer.Exists(tmr) then
            timer.Create(tmr, 1, 0, function() GiveEquipmentWeapon(sid, cls) end)
        end

        -- we will be retrying
    else
        -- can stop retrying, if we were
        timer.Remove(tmr)

        if w.WasBought then
            -- some weapons give extra ammo after being bought, etc
            w:WasBought(ply)
        end
    end
end

local function HasPendingOrder(ply)
    return timer.Exists("give_equipment" .. tostring(ply:SteamID64()))
end

function GM:TTTCanOrderEquipment(ply, id, is_item)
    --- return true to allow buying of an equipment item, false to disallow
    return true
end

-- Equipment buying
local function OrderEquipment(ply, cmd, args)
    if not IsValid(ply) or #args ~= 1 then return end

    if not ply:IsActiveShopRole() then return end

    -- no credits, can't happen when buying through menu as button will be off
    if ply:GetCredits() < 1 then return end

    -- it's an item if the arg is an id instead of an ent name
    local id = args[1]
    local is_item = tonumber(id)

    if not hook.Run("TTTCanOrderEquipment", ply, id, is_item) then return end

    -- we use weapons.GetStored to save time on an unnecessary copy, we will not
    -- be modifying it
    local swep_table = (not is_item) and weapons.GetStored(id) or nil

    local role = ply:GetRole()

    local rolemode = GetGlobalInt("ttt_" .. ROLE_STRINGS_RAW[role] .. "_shop_mode", SHOP_SYNC_MODE_NONE)
    local traitorsync = GetGlobalBool("ttt_" .. ROLE_STRINGS_RAW[role] .. "_shop_sync", false) and TRAITOR_ROLES[role]
    local sync_traitor_weapons = traitorsync or (rolemode > SHOP_SYNC_MODE_NONE)

    local promoted = ply:IsDetectiveLike() and role ~= ROLE_DETECTIVE
    local sync_detective_like = promoted and (role == ROLE_DEPUTY or role == ROLE_IMPERSONATOR)
    local detectivesync = GetGlobalBool("ttt_" .. ROLE_STRINGS_RAW[role] .. "_shop_sync", false) and DETECTIVE_ROLES[role]
    local sync_detective_weapons = detectivesync or sync_detective_like or (rolemode > SHOP_SYNC_MODE_NONE)

    -- If this role has a table of additional weapons and that table includes this weapon
    -- and this weapon is not currently buyable by the role then mark this weapon as buyable
    if swep_table then
        -- some weapons can only be bought once per player per round, this used to be
        -- defined in a table here, but is now in the SWEP's table
        if swep_table.LimitedStock and ply:HasBought(id) then
            LANG.Msg(ply, "buy_no_stock")
            return
        end

        -- Pre-load the Traitor weapons so that any that have their CanBuy modified will also apply to the enabled allied role(s)
        if sync_traitor_weapons then
            WEPS.HandleCanBuyOverrides(swep_table, ROLE_TRAITOR, true, sync_traitor_weapons, sync_detective_weapons)
        end

        -- Pre-load the Detective weapons so that any that have their CanBuy modified will also apply to the enabled allied role(s)
        if sync_detective_weapons then
            WEPS.HandleCanBuyOverrides(swep_table, ROLE_DETECTIVE, true, sync_traitor_weapons, sync_detective_weapons)
        end

        -- Add the loaded weapons for this role
        WEPS.HandleCanBuyOverrides(swep_table, role, false, sync_traitor_weapons, sync_detective_weapons)
    end

    -- Don't give roles their items if delayed shop is enabled
    local should_give = not ply:ShouldDelayShopPurchase()
    local received = false
    if is_item then
        id = tonumber(id)

        -- item whitelist check
        local allowed = GetEquipmentItem(role, id)
        -- Check for the syncing options
        if not allowed then
            if rolemode > SHOP_SYNC_MODE_NONE then
                -- Traitor OR Detective
                if rolemode == SHOP_SYNC_MODE_UNION then
                    allowed = GetEquipmentItem(ROLE_TRAITOR, id) or GetEquipmentItem(ROLE_DETECTIVE, id)
                -- Traitor AND Detective
                elseif rolemode == SHOP_SYNC_MODE_INTERSECT then
                    allowed = GetEquipmentItem(ROLE_TRAITOR, id) and GetEquipmentItem(ROLE_DETECTIVE, id)
                -- Detective only
                elseif rolemode == SHOP_SYNC_MODE_DETECTIVE then
                    allowed = GetEquipmentItem(ROLE_DETECTIVE, id)
                -- Traitor only
                elseif rolemode == SHOP_SYNC_MODE_TRAITOR then
                    allowed = GetEquipmentItem(ROLE_TRAITOR, id)
                end
            end
        end

        -- Traitor -> Special Traitor
        if not allowed and sync_traitor_weapons then
            allowed = GetEquipmentItem(ROLE_TRAITOR, id)
        end

        -- Detective -> Detective-like
        if not allowed and promoted then
            allowed = GetEquipmentItem(ROLE_DETECTIVE, id)
        end

        -- If it's not allowed, check the extra buyable equipment
        if not allowed then
            for _, v in ipairs(WEPS.BuyableWeapons[role]) do
                -- If this isn't a weapon, get its information from one of the roles and compare that to the ID we have
                if not weapons.GetStored(v) then
                    local equip = GetEquipmentItemByName(v)
                    if equip ~= nil and equip.id == id then
                        allowed = true
                        break
                    end
                end
            end
        end

        -- Lastly, if it is allowed check the exclude equipment list
        if allowed then
            for _, v in ipairs(WEPS.ExcludeWeapons[role]) do
                -- If this isn't a weapon, get its information from one of the roles and compare that to the ID we have
                if not weapons.GetStored(v) then
                    local equip = GetEquipmentItemByName(v)
                    if equip ~= nil and equip.id == id then
                        allowed = false
                        break
                    end
                end
            end
        end

        if not allowed then
            print(ply, "tried to buy item not buyable for his class:", id)
            return
        end

        -- ownership check and finalise
        if id and EQUIP_NONE < id then
            if not ply:HasEquipmentItem(id) then
                if should_give then
                    ply:GiveEquipmentItem(id)
                end

                received = true
            end
        end
    elseif swep_table then
        -- weapon whitelist check
        if not table.HasValue(swep_table.CanBuy, role) then
            print(ply, "tried to buy weapon his role is not permitted to buy")
            return
        end

        -- if we have a pending order because we are in a confined space, don't
        -- start a new one
        if HasPendingOrder(ply) then
            LANG.Msg(ply, "buy_pending")
            return
        end

        -- no longer restricted to only WEAPON_EQUIP weapons, just anything that
        -- is whitelisted and carryable
        if ply:CanCarryWeapon(swep_table) then
            if should_give then
                GiveEquipmentWeapon(ply:SteamID64(), id)
            end

            received = true
        end
    end

    if received then
        ply:SubtractCredits(1)
        if should_give then
            LANG.Msg(ply, "buy_received")
        else
            LANG.Msg(ply, "buy_received_delay")
        end

        ply:AddBought(id)

        timer.Simple(0.5,
                function()
                    if not IsValid(ply) then return end
                    net.Start("TTT_BoughtItem")
                    net.WriteBit(is_item)
                    if is_item then
                        net.WriteUInt(id, 32)
                    else
                        net.WriteString(id)
                    end
                    net.Send(ply)
                end)

        hook.Call("TTTOrderedEquipment", GAMEMODE, ply, id, is_item)
    end
end
concommand.Add("ttt_order_equipment", OrderEquipment)

concommand.Add("ttt_order_for_someone", function(ply, cmd, args)
    local target_name = args[1]
    local target = nil
    for _, v in pairs(player.GetAll()) do
        if target_name == v:Nick() then
            target = v
            break
        end
    end

    if not IsValid(target) then return end
    local new_args = {}
    new_args[1] = args[2]

    OrderEquipment(target, cmd, new_args)
end, nil, nil, FCVAR_CHEAT)

function GM:TTTToggleDisguiser(ply, state)
    -- Can be used to prevent players from using this button.
    -- return true to prevent it.
end

local function SetDisguise(ply, cmd, args)
    if not IsValid(ply) then return end

    if ply:HasEquipmentItem(EQUIP_DISGUISE) then
        local state = #args == 1 and tobool(args[1])
        if hook.Run("TTTToggleDisguiser", ply, state) then return end

        ply:SetNWBool("disguised", state)
        local SetMDL = FindMetaTable("Entity").SetModel
        -- Change the player's model to a random one when they disguise and back to their previous when they undisguise
        if state then
            ply.oldmodel = ply:GetModel()
            local randommodel = GetRandomPlayerModel()
            SetMDL(ply, randommodel)
        elseif ply.oldmodel then
            SetMDL(ply, ply.oldmodel)
            ply.oldmodel = nil
        end

        LANG.Msg(ply, state and "disg_turned_on" or "disg_turned_off")
    end
end
concommand.Add("ttt_set_disguise", SetDisguise)

local function CheatCredits(ply)
    if IsValid(ply) then
        ply:AddCredits(10)
    end
end
concommand.Add("ttt_cheat_credits", CheatCredits, nil, nil, FCVAR_CHEAT)

local function TransferCredits(ply, cmd, args)
    if (not IsValid(ply)) or (not ply:IsActiveSpecial()) then return end
    if #args ~= 2 then return end

    local sid = tostring(args[1])
    local credits = tonumber(args[2])
    if sid and credits then
        local target = player.GetBySteamID64(sid)
        if (not IsValid(target)) or (not target:IsActiveSpecial()) or not ply:IsSameTeam(target) or (target == ply) then
            LANG.Msg(ply, "xfer_no_recip")
            return
        end

        if ply:GetCredits() < credits then
            LANG.Msg(ply, "xfer_no_credits")
            return
        end

        credits = math.Clamp(credits, 0, ply:GetCredits())
        if credits == 0 then return end

        ply:SubtractCredits(credits)
        target:AddCredits(credits)

        LANG.Msg(ply, "xfer_success", { player = target:Nick() })
        LANG.Msg(target, "xfer_received", { player = ply:Nick(), num = credits })
    end
end
concommand.Add("ttt_transfer_credits", TransferCredits)

local function FakeTransferCredits(ply, cmd, args)
    if (not IsValid(ply)) or (not ply:IsActiveSpecial()) then return end
    if #args ~= 1 then return end

    local sid = tostring(args[1])
    local credits = tonumber(args[2])
    if credits then
        local target = player.GetBySteamID64(sid)
        if (not IsValid(target)) or (target == ply) then
            LANG.Msg(ply, "xfer_no_recip")
            return
        end

        if ply:GetCredits() < credits then
            LANG.Msg(ply, "xfer_no_credits")
            return
        end

        credits = math.Clamp(credits, 0, ply:GetCredits())
        if credits == 0 then return end

        ply:SubtractCredits(credits)

        LANG.Msg(ply, "xfer_success", { player = target:Nick() })
    end
end
concommand.Add("ttt_fake_transfer_credits", FakeTransferCredits)

local function BotTransferCredits(ply, cmd, args)
    if (not IsValid(ply)) or (not ply:IsActiveSpecial()) then return end
    if #args ~= 2 then return end

    local name = args[1]
    local credits = tonumber(args[2])
    if name and credits then
        if ply:GetCredits() < credits then
            LANG.Msg(ply, "xfer_no_credits")
            return
        end

        credits = math.Clamp(credits, 0, ply:GetCredits())
        if credits == 0 then return end

        ply:SubtractCredits(credits)

        LANG.Msg(ply, "xfer_success", { player = name })
    end
end
concommand.Add("ttt_bot_transfer_credits", BotTransferCredits)

-- Protect against non-TTT weapons that may break the HUD
function GM:WeaponEquip(wep, ply)
    if IsValid(wep) then
        -- only remove if they lack critical stuff
        if not wep.Kind then
            wep:Remove()
            ErrorNoHalt("Equipped weapon " .. wep:GetClass() .. " is not compatible with TTT\n")
        end

        if wep.CanBuy and not wep.AutoSpawnable then
            if not wep.BoughtBuy then
                wep.BoughtBuy = ply
            elseif ply:IsBeggar() and (wep.BoughtBuy:IsTraitorTeam() or wep.BoughtBuy:IsInnocentTeam()) then
                local role
                local beggarMode
                if wep.BoughtBuy:IsTraitorTeam() then
                    role = ROLE_TRAITOR
                    beggarMode = GetConVar("ttt_beggar_reveal_traitor"):GetInt()
                else
                    role = ROLE_INNOCENT
                    beggarMode = GetConVar("ttt_beggar_reveal_innocent"):GetInt()
                end

                ply:SetRole(role)
                ply:SetNWBool("WasBeggar", true)
                ply:PrintMessage(HUD_PRINTTALK, "You have joined the " .. ROLE_STRINGS[role] .. " team")
                ply:PrintMessage(HUD_PRINTCENTER, "You have joined the " .. ROLE_STRINGS[role] .. " team")
                timer.Simple(0.5, function() SendFullStateUpdate() end) -- Slight delay to avoid flickering from beggar to the new role and back to beggar

                for _, v in ipairs(player.GetAll()) do
                    if beggarMode == ANNOUNCE_REVEAL_ALL or (v:IsActiveTraitorTeam() and beggarMode == ANNOUNCE_REVEAL_TRAITORS) or (not v:IsActiveTraitorTeam() and beggarMode == ANNOUNCE_REVEAL_INNOCENTS) then
                        v:PrintMessage(HUD_PRINTTALK, "The beggar has joined the " .. ROLE_STRINGS[role] .. " team")
                        v:PrintMessage(HUD_PRINTCENTER, "The beggar has joined the " .. ROLE_STRINGS[role] .. " team")
                    end
                end

                net.Start("TTT_BeggarConverted")
                net.WriteString(ply:Nick())
                net.WriteString(wep.BoughtBuy:Nick())
                net.WriteString(ROLE_STRINGS_EXT[role])
                net.WriteString(ply:SteamID64())
                net.Broadcast()
            end
        end
    end
end

-- non-cheat developer commands can reveal precaching the first time equipment
-- is bought, so trigger it at the start of a round instead
function WEPS.ForcePrecache()
    for _, w in ipairs(weapons.GetList()) do
        if w.WorldModel then
            util.PrecacheModel(w.WorldModel)
        end
        if w.ViewModel then
            util.PrecacheModel(w.ViewModel)
        end
    end
end

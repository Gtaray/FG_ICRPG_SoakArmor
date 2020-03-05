-- 
-- Please see the license.html file included with this distribution for 
-- attribution and copyright information.
--

OOB_MSGTYPE_APPLYDMG = "applydmg";

function onInit() 
    OOBManager.registerOOBMsgHandler(OOB_MSGTYPE_APPLYDMG, handleApplyDamage);
end

------------------------------------------------------
-- Handling setting SOAK amount when PC takes damage
------------------------------------------------------
function handleApplyDamage(msgOOB)
    -- run the effort handler first
    if not msgOOB.sTargetType then return; end
    local rSource = ActorManager.getActor(msgOOB.sSourceType, msgOOB.sSourceNode);
    local rTarget = ActorManager.getActor(msgOOB.sTargetType, msgOOB.sTargetNode);

	if rTarget then
		rTarget.nOrder = msgOOB.nTargetOrder;
    end
    local nDmg = tonumber(msgOOB.nTotal) or 0;
    local bHeal = string.match(msgOOB.sDamage, "%[HEAL%]") or nDmg < 0;

    -- Don't set SOAK when healed
    if not bHeal then
        local nSoak, nOverflow = calculateSoak(rSource, rTarget, msgOOB.sDamage, nDmg)
        setSoakAmount(rTarget, nSoak, nOverflow);
    end
    ActionEffort.handleApplyDamage(msgOOB)
end

function calculateSoak(rSource, rTarget, sDesc, nDmg)
    local sTargetType, sTargetNode = ActorManager.getTypeAndNode(rTarget);
    if sTargetType ~= "pc" then return; end
    if not sTargetNode then return; end
    if not nDmg or nDmg < 0 then return; end


    local aNotifications = {};
    local nTotalHP, nWounds;
    nTotalHP = DB.getValue(sTargetNode, "health.hp", 0);
    nWounds = DB.getValue(sTargetNode, "health.wounds", 0);

    local nAdjustedDmg,_,nRemainder = ActionEffort.calculateDamage(rTarget, rSource, sDesc, nDmg, nTotalHP, nWounds, aNotifications);
    return nAdjustedDmg, nRemainder;
end

-- if there is a remainder (i.e. if a character was reduced to 0 hp), we need to calculate the
-- amount of damage that brought the character TO 0 hp. This is important, since soaking damage
-- that would have otherwise brought you to 0 not only needs to account for the damage overflow,
-- but undoing that damage needs to take into account the overflow
-- EXMAPLE: If a PC is at 8 HP and takes 5 damage, SOAKING can't just heal 5, as that results in
-- an end total of 5 WOUNDS, not 8.
function setSoakAmount(rActor, nAmount, nOverflow)
    local sActorType, nodeActor = ActorManager.getTypeAndNode(rActor);
    if sActorType ~= "pc" then return; end
    if not nodeActor then return; end
    if not nAmount or nAmount < 0 then return; end
    DB.setValue(nodeActor, "defense.armor.soak", "number", nAmount);
    DB.setValue(nodeActor, "defense.armor.overflow", "number", nOverflow);
end

-----------------------------------------------------------------------
-- Handling applying SOAK when the soak button is clicked
-----------------------------------------------------------------------
function applySoak(rActor)
    local sActorType, nodeActor = ActorManager.getTypeAndNode(rActor);
    if not nodeActor then return; end

    local nSoak = DB.getValue(nodeActor, "defense.armor.soak", 0);
    local nOverflow = DB.getValue(nodeActor, "defense.armor.overflow", 0);

    -- If soak is less than damage, print a message in chat, but don't actually reduce armor
    -- since there's no reason to soak this amount.
    if nSoak <= nOverflow then
        ChatManager.SystemMessage("You must soat at least " .. (nOverflow + 1) .. " damage.");
        return;
    else
        if nSoak > 0 then
            -- Adjusted SOAK is the amount to heal the PC
            local nAdjustedSoak = nSoak - nOverflow;
            local nWounds = DB.getValue(nodeActor, "health.wounds", 0);
            local nArmorDmg = DB.getValue(nodeActor, "defense.armor.damage", 0);
            local nArmorBase = DB.getValue(nodeActor, "defense.armor.base", 0);
            local nArmorLoot = DB.getValue(nodeActor, "defense.armor.loot", 0);
            local nArmorTotal = nArmorBase + nArmorLoot;
            if nArmorDmg + nSoak > nArmorTotal then
                ChatManager.SystemMessage("Not enough ARMOR to soak " .. nSoak .. " damage.");
                return;
            end

            -- if the soak amount is greature than our wounds, change it
            if nAdjustedSoak > nWounds then
                nAdjustedSoak = nWounds;
            end
            if nAdjustedSoak > nArmorTotal then
                nAdjustedSoak = nArmorTotal;
            end
            nWounds = nWounds - nAdjustedSoak;
            nArmorDmg = nArmorDmg + nSoak;

            messageSoak(rActor, nAdjustedSoak, false);
            
            -- Update health and armor dmg in DB
            DB.setValue(nodeActor, "health.wounds", "number", nWounds);
            DB.setValue(nodeActor, "defense.armor.damage", "number", nArmorDmg);

            -- Update conditions to reflect changes
            updateConditions(rActor);
            -- Reset SOAK
            setSoakAmount(rActor, 0, 0);
        end
    end
end

function updateConditions(rActor)
    local sActorType, nodeActor = ActorManager.getTypeAndNode(rActor);
    if not nodeActor then return; end
    local nTotalHP, nWounds;
    nTotalHP = DB.getValue(nodeActor, "health.hp", 0);
    nWounds = DB.getValue(nodeActor, "health.wounds", 0);

    if EffectManagerICRPG.hasCondition(rActor, "Stable") then
        EffectManager.removeEffect(ActorManager.getCTNode(rActor), "Stable");
    end
    if EffectManagerICRPG.hasCondition(rActor, "Dead") then
        EffectManager.removeEffect(ActorManager.getCTNode(rActor), "Dead");
    end
    if nWounds < nTotalHP then
		if EffectManagerICRPG.hasCondition(rActor, "Dying") then
			EffectManager.removeEffect(ActorManager.getCTNode(rActor), "Dying");
		end
	else
		if not EffectManagerICRPG.hasCondition(rActor, "Dying") then
			EffectManager.addEffect("", "", ActorManager.getCTNode(rActor), { sName = "Dying", nDuration = 0 }, true);
		end
	end
end

function messageSoak(rActor, sTotal, bSecret, sExtra)
    if not rActor then
		return;
    end
    
    local rMessage = ChatManager.createBaseMessage(rActor, nil);
    rMessage.icon = "soak"
    rMessage.text = "[SOAK: " .. sTotal .. "]";

    Comm.deliverChatMessage(rMessage);
end
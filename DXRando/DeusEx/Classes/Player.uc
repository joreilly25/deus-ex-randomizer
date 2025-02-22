class DXRPlayer injects Human;

var DXRando dxr;
var DXRLoadouts loadout;
var bool bOnLadder;
var transient string nextMap;

function ClientMessage(coerce string msg, optional Name type, optional bool bBeep)
{
    Super.ClientMessage(msg, type, bBeep);
    if( dxr == None ) foreach AllActors(class'DXRando', dxr) { break; }
    class'DXRTelemetry'.static.SendLog(dxr, self, "INFO", msg);

    if(bBeep) {
        // we don't want to override more important log sounds like Sound'LogSkillPoints'
        if(DeusExRootWindow(rootWindow).hud.msgLog.logSoundToPlay == None)
            DeusExRootWindow(rootWindow).hud.msgLog.PlayLogSound(Sound'Menu_Focus');
    }
}

event ClientTravel( string URL, ETravelType TravelType, bool bItems )
{
    nextMap = URL;
    Super.ClientTravel(URL, TravelType, bItems);
}

function DXRBase DXRFindModule(class<DXRBase> class)
{
    local DXRBase m;
    if( dxr == None ) foreach AllActors(class'DXRando', dxr) { break; }
    if( dxr != None ) m = dxr.FindModule(class);
    return m;
}

function PostIntro()
{
    if( flagbase.GetInt('Rando_newgameplus_loops') > 0 ) {
        bStartNewGameAfterIntro = true;
    }
    Super.PostIntro();
}

// just wrap some stuff in an if statement for flag Rando_newgameplus_loops
exec function StartNewGame(String startMap)
{
    if (DeusExRootWindow(rootWindow) != None)
        DeusExRootWindow(rootWindow).ClearWindowStack();

    // Set a flag designating that we're traveling,
    // so MissionScript can check and not call FirstFrame() for this map.
    flagBase.SetBool('PlayerTraveling', True, True, 0);

    if( flagbase.GetInt('Rando_newgameplus_loops') == 0 ) {
        SaveSkillPoints();
        ResetPlayer();
    }
    DeleteSaveGameFiles();

    bStartingNewGame = True;

    // Send the player to the specified map!
    if (startMap == "")
        Level.Game.SendPlayer(Self, "01_NYC_UNATCOIsland");		// TODO: Must be stored somewhere!
    else
        Level.Game.SendPlayer(Self, startMap);
}

exec function QuickSave()
{
    if( class'DXRAutosave'.static.AllowManualSaves(self) ) Super.QuickSave();
    else ClientMessage("Manual saving is not allowed in this game mode! Good Luck!",, true);
}

function bool AddInventory( inventory NewItem )
{
    if( loadout == None ) loadout = DXRLoadouts(DXRFindModule(class'DXRLoadouts'));
    if ( loadout != None && loadout.ban(self, NewItem) ) return true;

    return Super.AddInventory(NewItem);
}

// copied a lot from DeusExPlayer DeleteInventory
function bool HideInventory(inventory item)
{
    local DeusExRootWindow root;
    local PersonaScreenInventory winInv;

    item.bDisplayableInv = false;

    // If the item was inHand, clear the inHand
    if (inHand == item)
    {
        SetInHand(None);
        SetInHandPending(None);
    }

    // Make sure the item is removed from the inventory grid
    RemoveItemFromSlot(item);

    root = DeusExRootWindow(rootWindow);

    if (root != None)
    {
        // If the inventory screen is active, we need to send notification
        // that the item is being removed
        winInv = PersonaScreenInventory(root.GetTopWindow());
        if (winInv != None)
            winInv.InventoryDeleted(item);

        // Remove the item from the object belt
        if (root != None)
            root.DeleteInventory(item);
      else //In multiplayer, we often don't have a root window when creating corpse, so hand delete
      {
         item.bInObjectBelt = false;
         item.beltPos = -1;
      }
    }
}

#ifdef transcended
function DeusExNote AddNote( optional String strNote, optional Bool bUserNote, optional bool bShowInLog, optional String strSource)
#else
function DeusExNote AddNote( optional String strNote, optional Bool bUserNote, optional bool bShowInLog )
#endif
{
    local DeusExLevelInfo info;
    local DeusExNote newNote;
#ifdef transcended
    newNote = Super.AddNote(strNote, bUserNote, bShowInLog, strSource);
#else
    newNote = Super.AddNote(strNote, bUserNote, bShowInLog);

    info = GetLevelInfo();
    if (info != None) {
        newNote.mission = info.MissionNumber;
        newNote.level_name = Caps(info.mapName);
        log("AddNote: new note mission: "$newNote.mission$", level name: "$newNote.level_name);
    }
#endif

    return newNote;
}

function float GetCurrentGroundSpeed()
{
    local float augValue, speed;

    // Remove this later and find who's causing this to Access None MB
    if ( AugmentationSystem == None )
        return 0;

    augValue = AugmentationSystem.GetAugLevelValue(class'AugSpeed');
    if (augValue == -1.0)
        augValue = AugmentationSystem.GetAugLevelValue(class'AugNinja');

    if (augValue == -1.0)
        augValue = 1.0;

    if ( Level.NetMode != NM_Standalone )
        speed = Self.mpGroundSpeed * augValue;
    else
        speed = Default.GroundSpeed * augValue;

    return speed;
}

function DoJump( optional float F )
{
    local DeusExWeapon w;
    local float scaleFactor, augLevel;

    if ((CarriedDecoration != None) && (CarriedDecoration.Mass > 20))
        return;
    else if (bForceDuck || IsLeaning())
        return;

    if (Physics == PHYS_Walking)
    {
        if ( Role == ROLE_Authority )
            PlaySound(JumpSound, SLOT_None, 1.5, true, 1200, 1.0 - 0.2*FRand() );
        if ( (Level.Game != None) && (Level.Game.Difficulty > 0) )
            MakeNoise(0.1 * Level.Game.Difficulty);
        PlayInAir();

        Velocity.Z = JumpZ;

        if ( Level.NetMode != NM_Standalone )
        {
         if (AugmentationSystem == None)
            augLevel = -1.0;
         else			
            augLevel = AugmentationSystem.GetAugLevelValue(class'AugSpeed');
            if( augLevel == -1.0 )
                augLevel = AugmentationSystem.GetAugLevelValue(class'AugNinja');
            w = DeusExWeapon(InHand);
            if ((augLevel != -1.0) && ( w != None ) && ( w.Mass > 30.0))
            {
                scaleFactor = 1.0 - FClamp( ((w.Mass - 30.0)/55.0), 0.0, 0.5 );
                Velocity.Z *= scaleFactor;
            }
        }
        
        // reduce the jump velocity if you are crouching
//		if (bIsCrouching)
//			Velocity.Z *= 0.9;

        if ( Base != Level )
            Velocity.Z += Base.Velocity.Z;
        SetPhysics(PHYS_Falling);
        if ( bCountJumps && (Role == ROLE_Authority) )
            Inventory.OwnerJumped();
        
        class'DXRStats'.static.AddJump(self);
    }
}

function Landed(vector HitNormal)
{
    local vector legLocation;
    local int augLevel;
    local float augReduce, dmg;

    //Note - physics changes type to PHYS_Walking by default for landed pawns
    PlayLanded(Velocity.Z);
    if (Velocity.Z < -1.4 * JumpZ)
    {
        MakeNoise(-0.5 * Velocity.Z/(FMax(JumpZ, 150.0)));
        if ((Velocity.Z < -700) && (ReducedDamageType != 'All'))
            if ( Role == ROLE_Authority )
            {
                // check our jump augmentation and reduce falling damage if we have it
                // jump augmentation doesn't exist anymore - use Speed instaed
                // reduce an absolute amount of damage instead of a relative amount
                augReduce = 0;
                if (AugmentationSystem != None)
                {
                    augLevel = AugmentationSystem.GetClassLevel(class'AugSpeed');
                    if( augLevel == -1.0 )
                        augLevel = AugmentationSystem.GetClassLevel(class'AugNinja');
                    if (augLevel >= 0)
                        augReduce = 15 * (augLevel+1);
                }

                dmg = Max((-0.16 * (Velocity.Z + 700)) - augReduce, 0);
                legLocation = Location + vect(-1,0,-1);			// damage left leg
                TakeDamage(dmg, None, legLocation, vect(0,0,0), 'fell');

                legLocation = Location + vect(1,0,-1);			// damage right leg
                TakeDamage(dmg, None, legLocation, vect(0,0,0), 'fell');

                dmg = Max((-0.06 * (Velocity.Z + 700)) - augReduce, 0);
                legLocation = Location + vect(0,0,1);			// damage torso
                TakeDamage(dmg, None, legLocation, vect(0,0,0), 'fell');
            }
    }
    else if ( (Level.Game != None) && (Level.Game.Difficulty > 1) && (Velocity.Z > 0.5 * JumpZ) )
        MakeNoise(0.1 * Level.Game.Difficulty);				
    bJustLanded = true;
}

function float AdjustCritSpots(float Damage, name damageType, vector hitLocation)
{
    local vector offset;
    local float headOffsetZ, headOffsetY, armOffset;

    // EMP attacks drain BE energy
    if (damageType == 'EMP')
        return Damage;

    // use the hitlocation to determine where the pawn is hit
    // transform the worldspace hitlocation into objectspace
    // in objectspace, remember X is front to back
    // Y is side to side, and Z is top to bottom
    offset = (hitLocation - Location) << Rotation;

    // calculate our hit extents
    headOffsetZ = CollisionHeight * 0.78;
    headOffsetY = CollisionRadius * 0.35;
    armOffset = CollisionRadius * 0.35;

    // We decided to just have 3 hit locations in multiplayer MBCODE
    if (( Level.NetMode == NM_DedicatedServer ) || ( Level.NetMode == NM_ListenServer ))
    {
        // leave it vanilla
        return Damage;
    }

    // Normal damage code path for single player
    if (offset.z > headOffsetZ)     // head
    {
        // narrow the head region
        if ((Abs(offset.x) < headOffsetY) || (Abs(offset.y) < headOffsetY))
        {
            // do 1.6x damage instead of the 2x damage in DeusExPlayer.uc::TakeDamage()
            return Damage * 0.8;
        }
    }
    else if (offset.z < 0.0)        // legs
    {
    }
    else                            // arms and torso
    {
        if (offset.y > armOffset)
        {
            // right arm
        }
        else if (offset.y < -armOffset)
        {
            // left arm
        }
        else
        {
            // and finally, the torso! do 1.3x damage instead of the 2x damage in DeusExPlayer.uc::TakeDamage()
            return Damage * 0.65;
        }
    }

    return Damage;
}

// ----------------------------------------------------------------------
// DXReduceDamage()
//
// Calculates reduced damage from augmentations and from inventory items
// Also calculates a scalar damage reduction based on the mission number
// ----------------------------------------------------------------------
function bool DXReduceDamage(int Damage, name damageType, vector hitLocation, out int adjustedDamage, bool bCheckOnly)
{
    local float newDamage, oldDamage;
    local float augLevel, skillLevel;
    local float pct;
    local HazMatSuit suit;
    local BallisticArmor armor;
    local bool bReduced;
    local float damageMult;

    bReduced = False;
    newDamage = Float(Damage);
    newDamage = AdjustCritSpots(newDamage, damageType, hitLocation);
    oldDamage = newDamage;

    if ((damageType == 'TearGas') || (damageType == 'PoisonGas') || (damageType == 'Radiation') ||
        (damageType == 'HalonGas')  || (damageType == 'PoisonEffect') || (damageType == 'Poison') 
        /*|| damageType == 'Flamed' || damageType == 'Burned'*/ )
    {
        if (AugmentationSystem != None)
            augLevel = AugmentationSystem.GetAugLevelValue(class'AugEnviro');

        if (augLevel >= 0.0)
            newDamage *= augLevel;

        // get rid of poison if we're maxed out
        if (newDamage ~= 0.0)
        {
            StopPoison();
            drugEffectTimer -= 4;	// stop the drunk effect
            if (drugEffectTimer < 0)
                drugEffectTimer = 0;
        }

        if (UsingChargedPickup(class'HazMatSuit'))
        {
            skillLevel = SkillSystem.GetSkillLevelValue(class'SkillEnviro');
            newDamage *= 0.75 * skillLevel;
        }
        else // passive enviro skill still gives some damage reduction
        {
            skillLevel = SkillSystem.GetSkillLevelValue(class'SkillEnviro');
            newDamage *= (skillLevel + 1)/2;
        }
    }

    if ((damageType == 'Shot') || (damageType == 'Sabot') || (damageType == 'Exploded') || (damageType == 'AutoShot'))
    {
        // go through the actor list looking for owned BallisticArmor
        // since they aren't in the inventory anymore after they are used
        if (UsingChargedPickup(class'BallisticArmor'))
        {
            skillLevel = SkillSystem.GetSkillLevelValue(class'SkillEnviro');
            newDamage *= 0.5 * skillLevel;
        }
    }

    if (damageType == 'HalonGas')
    {
        if (bOnFire && !bCheckOnly)
            ExtinguishFire();
    }

    if ((damageType == 'Shot') || (damageType == 'AutoShot'))
    {
        if (AugmentationSystem != None)
            augLevel = AugmentationSystem.GetAugLevelValue(class'AugBallistic');

        if (augLevel >= 0.0)
            newDamage *= augLevel;
    }

    if (damageType == 'EMP')
    {
        if (AugmentationSystem != None)
            augLevel = AugmentationSystem.GetAugLevelValue(class'AugEMP');

        if (augLevel >= 0.0)
            newDamage *= augLevel;
    }

    if ((damageType == 'Burned') || (damageType == 'Flamed') ||
        (damageType == 'Exploded') || (damageType == 'Shocked'))
    {
        if (AugmentationSystem != None)
            augLevel = AugmentationSystem.GetAugLevelValue(class'AugShield');

        if (augLevel >= 0.0)
            newDamage *= augLevel;

        if (UsingChargedPickup(class'HazMatSuit'))
        {
            skillLevel = SkillSystem.GetSkillLevelValue(class'SkillEnviro');
            newDamage *= 0.75 * skillLevel;
        }
        else // passive enviro skill still gives some damage reduction
        {
            skillLevel = SkillSystem.GetSkillLevelValue(class'SkillEnviro');
            newDamage *= (skillLevel + 2)/3;
        }
    }

    //Apply damage multiplier
    //This gets tweaked from DXRandoCrowdControlLink, but will normally just be 1.0
    damageMult = GetDamageMultiplier();
    if (damageMult!=0) {
        newDamage*=damageMult;
    }


    //
    // Reduce or increase the damage based on the combat difficulty setting, do this before SetDamagePercent for the UI display
    // because we don't want to show 100% damage reduction but then do the minimum of 1 damage
    if ((damageType == 'Shot') || (damageType == 'AutoShot') ||
        damageType == 'Flamed' || damageType == 'Burned')
    {
        newDamage *= CombatDifficulty;
        oldDamage *= CombatDifficulty;

        // always take at least one point of damage
        if ((newDamage <= 1) && (Damage > 0))
            newDamage = 1;
        if ((oldDamage <= 1) && (Damage > 0))
            oldDamage = 1;
    }

    //make sure to factor the rounding into the percentage
    pct = 1.0 - ( Float(Int(newDamage)) / Float(Int(oldDamage)) );
    if (pct != 1.0)
    {
        if (!bCheckOnly)
        {
            SetDamagePercent(pct);
            ClientFlash(0.01, vect(0, 0, 50));
        }
        bReduced = True;
    }
    else
    {
        if (!bCheckOnly)
            SetDamagePercent(0.0);
    }

    adjustedDamage = Int(newDamage);

    return bReduced;
}

function float GetDamageMultiplier()
{
    local DataStorage datastorage;
    datastorage = class'DataStorage'.static.GetObj(self);
    return float(datastorage.GetConfigKey('cc_damageMult'));
}

function CatchFire( Pawn burner )
{
    local bool doSetTimer;
    if (bOnFire==false && Region.Zone.bWaterZone==false)
        doSetTimer = true;

    Super.CatchFire(burner);

    // set the burn timer, tick the burn every 4 seconds instead of 1 so that the player can actually survive it
    if(doSetTimer)
        SetTimer(4.0, True);
}

event WalkTexture( Texture Texture, vector StepLocation, vector StepNormal )
{
    if ( Texture!=None && Texture.Outer!=None && Texture.Outer.Name=='Ladder' ) {
        bOnLadder = True;
    }
    else
        bOnLadder = False;
}

function Died(pawn Killer, name damageType, vector HitLocation)
{
    class'DXRStats'.static.AddDeath(self);
    Super.Died(Killer,damageType,HitLocation);
}

exec function CrowdControlAnon()
{
    local DXRCrowdControl cc;
    local DXRFlags f;

    foreach AllActors(class'DXRCrowdControl',cc)
    {
        cc.link.anon = True;
    }
    foreach AllActors(class'DXRFlags',f)
    {
        f.crowdcontrol = 2;
        f.f.SetInt('Rando_crowdcontrol',2,,999);
    }

    ClientMessage("Now hiding Crowd Control names");

}

exec function CrowdControlNames()
{
    local DXRCrowdControl cc;
    local DXRFlags f;
    
    foreach AllActors(class'DXRCrowdControl',cc)
    {
        cc.link.anon = False;
    }
    foreach AllActors(class'DXRFlags',f)
    {
        f.crowdcontrol = 1;
        f.f.SetInt('Rando_crowdcontrol',1,,999);
    }
    ClientMessage("Now showing Crowd Control names");
}

exec function CheatsOn()
{
    bCheatsEnabled = true;
    ClientMessage("Cheats Enabled");
}

exec function CheatsOff()
{
    bCheatsEnabled = false;
    ClientMessage("Cheats Disabled");

}

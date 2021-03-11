//=============================================================================
// DXRandoCrowdControlLink.
//=============================================================================
class DXRandoCrowdControlLink extends TcpLink transient;

var string crowd_control_addr;

var DXRCrowdControl ccModule;

var transient DXRando dxr;
var int ListenPort;
var IpAddr addr;

var int ticker;
var int lavaTick;

var bool anon;

var int reconnectTimer;

var string pendingMsg;

const Success = 0;
const Failed = 1;
const NotAvail = 2;
const TempFail = 3;

const CrowdControlPort = 43384;

const MoveSpeedMultiplier = 10;
const MoveSpeedDivisor = 0.25;
const DefaultGroundSpeed = 320;

//HK Canal freezer room has friction=1, but that doesn't
//feel slippery enough to me
const IceFriction = 0.25;
const NormalFriction = 8;
var vector NormalGravity;
var vector FloatGrav;
var vector MoonGrav;

const ReconDefault = 5;
const MatrixTimeDefault = 60;
const EmpDefault = 15;
const JumpTimeDefault = 60;
const SpeedTimeDefault = 60;
const LamThrowerTimeDefault = 60;
const IceTimeDefault = 60;
const BehindTimeDefault = 60;
const DifficultyTimeDefault = 60;
const FloatyTimeDefault = 60;
const FloorLavaTimeDefault = 60;
const InvertMouseTimeDefault = 60;
const InvertMovementTimeDefault = 60;

struct ZoneFriction
{
    var name zonename;
    var float friction;
};
var transient ZoneFriction zone_frictions[128];

struct ZoneGravity
{
    var name zonename;
    var vector gravity;
};
var transient ZoneGravity zone_gravities[128];

//JSON parsing states
const KeyState = 1;
const ValState = 2;
const ArrayState = 3;
const ArrayDoneState = 4;

struct JsonElement
{
    var string key;
    var string value[5];
    var int valCount;
};

struct JsonMsg
{
    var JsonElement e[20];
    var int count;
};

function string StripQuotes (string msg) {
    if (Mid(msg,0,1)==Chr(34)) {
        if (Mid(msg,Len(Msg)-1,1)==Chr(34)) {
            return Mid(msg,1,Len(msg)-2);
        }
    }        
    return msg;
}

function string JsonStripSpaces(string msg) {
    local int i;
    local string c;
    local string buf;
    local bool inQuotes;
    
    inQuotes = False;
    
    for (i = 0; i < Len(msg) ; i++) {
        c = Mid(msg,i,1); //Grab a single character
        
        if (c==" " && !inQuotes) {
            continue;  //Don't add spaces to the buffer if we're outside quotes
        } else if (c==Chr(34)) {
            inQuotes = !inQuotes;
        }
        
        buf = buf $ c;
    }    
    
    return buf;
}

//Returns the appropriate character for whatever is after
//the backslash, eg \c
function string JsonGetEscapedChar(string c) {
    switch(c){
        case "b":
            return Chr(8); //Backspace
        case "f":
            return Chr(12); //Form feed
        case "n":
            return Chr(10); //New line
        case "r":
            return Chr(13); //Carriage return
        case "t":
            return Chr(9); //Tab
        case Chr(34): //Quotes
        case Chr(92): //Backslash
            return c;
        default:
            return "";
    }
}

function JsonMsg ParseJson (string msg) {
    
    local bool msgDone;
    local int i;
    local string c;
    local string buf;
    
    local int parsestate;
    local bool inquotes;
    local bool escape;
    
    local JsonMsg j;
    
    local bool elemDone;
    
    elemDone = False;
    
    parsestate = KeyState;
    inquotes = False;
    escape = False;
    msgDone = False;
    buf = "";

    //Strip any spaces outside of strings to standardize the input a bit
    msg = JsonStripSpaces(msg);
    
    for (i = 0; i < Len(msg) && !msgDone ; i++) {
        c = Mid(msg,i,1); //Grab a single character
        
        if (!inQuotes) {
            switch (c) {
                case ":":
                case ",":
                  //Wrap up the current string that was being handled
                  //PlayerMessage(buf);
                  if (parsestate == KeyState) {
                      j.e[j.count].key = StripQuotes(buf);
                      parsestate = ValState;
                  } else if (parsestate == ValState) {
                      //j.e[j.count].value[j.e[j.count].valCount]=StripQuotes(buf);
                      j.e[j.count].value[j.e[j.count].valCount]=buf;
                      j.e[j.count].valCount++;
                      parsestate = KeyState;
                      elemDone = True;
                  } else if (parsestate == ArrayState) {
                      //j.e[j.count].value[j.e[j.count].valCount]=StripQuotes(buf);
                      j.e[j.count].value[j.e[j.count].valCount]=buf;
                      j.e[j.count].valCount++;
                  } else if (parsestate == ArrayDoneState){
                      parseState = KeyState;
                  }
                case "{":
                    buf = "";
                    break;
                
                case "}":
                    //PlayerMessage(buf);
                    if (parsestate == ValState) {
                      //j.e[j.count].value[j.e[j.count].valCount]=StripQuotes(buf);
                      j.e[j.count].value[j.e[j.count].valCount]=buf;
                      j.e[j.count].valCount++;
                      parsestate = KeyState;
                      elemDone = True;
                    }
                    msgDone = True;
                    break;
                
                case "]":
                    if (parsestate == ArrayState) {
                        //j.e[j.count].value[j.e[j.count].valCount]=StripQuotes(buf);
                        j.e[j.count].value[j.e[j.count].valCount]=buf;
                        j.e[j.count].valCount++;
                        elemDone = True;
                        parsestate = ArrayDoneState;
                    } else {
                        buf = buf $ c;
                    }
                    break;
                case "[":
                    if (parsestate == ValState){
                        parsestate = ArrayState;
                    } else {
                        buf = buf $ c;
                    }
                    break;
                case Chr(34): //Quotes
                    inQuotes = !inQuotes;
                    break;
                default:
                    //Build up the buffer
                    buf = buf $ c;
                    break;
                
            }
        } else {
            switch(c) {
                case Chr(34): //Quotes
                    if (escape) {
                        escape = False;
                        buf = buf $ JsonGetEscapedChar(c);                       
                    } else {
                        inQuotes = !inQuotes;
                    }
                    break;
                case Chr(92): //Backslash, escape character time
                    if (escape) {
                        //If there has already been one, then we need to turn it into the right char
                        escape = False;
                        buf = buf $ JsonGetEscapedChar(c);
                    } else {
                        escape = True;
                    }
                    break;
                default:
                    //Build up the buffer
                    if (escape) {
                        escape = False;
                        buf = buf $ JsonGetEscapedChar(c);
                    } else {
                        buf = buf $ c;
                    }
                    break;                
            }
        }
        
        if (elemDone) {
          //PlayerMessage("Key: "$j.e[j.count].key$ "   Val: "$j.e[j.count].value[0]);
          j.count++;
          elemDone = False;          
        }
    }
    
    return j;
    
}

function Init( DXRando tdxr, DXRCrowdControl cc, string addr, bool anonymous)
{
    dxr = tdxr;   
    ccModule = cc;
    crowd_control_addr = addr; 
    anon = anonymous;
    
    //Initialize the pending message buffer
    pendingMsg = "";
    
    //Initialize the ticker
    ticker = 0;
    
    lavaTick = 0;


    Resolve(crowd_control_addr);

    reconnectTimer = ReconDefault;
    SetTimer(0.1,True);

}


//Gets called on every level entry
//Some effects need to be reapplied on each level entry (eg. ice physics)
//Make sure to do that here
function InitOnEnter() {
    local inventory anItem;
    
    if (getTimer('cc_MatrixModeTimer') > 0) {
        StartMatrixMode();
    } else {
        StopMatrixMode(True);
    }
    
    dxr.Player.bWarrenEMPField = isTimerActive('cc_EmpTimer');

    if (isTimerActive('cc_SpeedTimer')) {
        dxr.Player.Default.GroundSpeed = DefaultGroundSpeed * dxr.Player.FlagBase.GetInt('cc_moveSpeedModifier');        
    } else {
        dxr.Player.Default.GroundSpeed = DefaultGroundSpeed;        
    }
    
    if (isTimerActive('cc_lamthrowerTimer')) {
        anItem = dxr.Player.FindInventoryType(class'WeaponFlamethrower');
        if (anItem!=None) {
            MakeLamThrower(anItem);
        }
    } else {
        UndoLamThrowers();        
    }
    
    SetIcePhysics(isTimerActive('cc_iceTimer'));
    
    SetFloatyPhysics(isTimerActive('cc_floatyTimer'));
    
    dxr.Player.bBehindView=isTimerActive('cc_behindTimer');
    
    if (0==dxr.Player.FlagBase.GetFloat('cc_damageMult')) {
        dxr.Player.FlagBase.SetFloat('cc_damageMult',1.0);
    }
    if (!isTimerActive('cc_DifficultyTimer')) {
        dxr.Player.FlagBase.SetFloat('cc_damageMult',1.0);
    }
    
    if (isTimerActive('cc_invertMouseTimer')) {
        dxr.Player.bInvertMouse = !dxr.Player.FlagBase.GetBool('cc_InvertMouseDef');
    }
    
    if (isTimerActive('cc_invertMovementTimer')) {
        invertMovementControls();
    }
    
    

}

//Effects should revert to default before exiting a level
//so that they can be cleanly re-applied next time you enter
function CleanupOnExit() {
    StopMatrixMode(True);  //matrix
    dxr.Player.bWarrenEMPField = false;  //emp
    dxr.Player.JumpZ = dxr.Player.Default.JumpZ;  //disable_jump
    dxr.Player.Default.GroundSpeed = DefaultGroundSpeed;  //gotta_go_fast and gotta_go_slow
    UndoLamThrowers(); //lamthrower
    SetIcePhysics(False); //ice_physics
    dxr.Player.bBehindView = False; //third_person
    SetFloatyPhysics(False);
    if (isTimerActive('cc_invertMouseTimer')) {
        dxr.Player.bInvertMouse = dxr.Player.FlagBase.GetBool('cc_InvertMouseDef');
    }

    if (isTimerActive('cc_invertMovementTimer')) {
        invertMovementControls();
    }

}

function StartMatrixMode() {
    if (dxr.Player.Sprite == None)
    {
        dxr.Player.Matrix();
    }
}

function StopMatrixMode(optional bool silent) {
    if (dxr.Player.Sprite!=None) {
        dxr.Player.Matrix();
    }

    if (!silent) {
        PlayerMessage("Your powers fade...");
    }

}

function int getTimer(name timerName) {
    return dxr.Player.FlagBase.GetInt(timerName);
}

function bool isTimerActive(name timerName) {
    return (dxr.Player.FlagBase.GetInt(timerName) > 0);
}

function setTimerFlag(name timerName,int time) {
    dxr.Player.FlagBase.SetInt(timerName,time);
}

//Timers only decrement while playing
function bool decrementTimer(name timerName) {
    local int time;
    time = dxr.Player.FlagBase.GetInt(timerName);
    if (time>0 && InGame()) {
        time -= 1;
        dxr.Player.FlagBase.SetInt(timerName,time);
        
        return (time == 0);
    }
    return false;
}

function Timer() {
    
    ticker++;
    if (IsConnected()) {
        ManualReceiveBinary();
    }

    //Lava floor logic
    if (isTimerActive('cc_floorLavaTimer') && InGame()){
        floorIsLava();
    }


    if (ticker%10 != 0) {
        return;
    }
    //Everything below here runs once a second

    if (!IsConnected()) {
        reconnectTimer-=1;
        if (reconnectTimer <= 0){
            Resolve(crowd_control_addr);
        }
    } 

    //Matrix Mode Timer
    if (decrementTimer('cc_MatrixModeTimer')) {
        StopMatrixMode();
    }

    //EMP Field timer
    if (decrementTimer('cc_EmpTimer')) {
            dxr.Player.bWarrenEMPField = false;
            PlayerMessage("EMP Field has disappeared...");        
    }

    if (isTimerActive('cc_JumpTimer')) {
        dxr.Player.JumpZ = 0;        
    }
    if (decrementTimer('cc_JumpTimer')) {
        dxr.Player.JumpZ = dxr.Player.Default.JumpZ;
        PlayerMessage("Your knees feel fine again.");
    }

    if (isTimerActive('cc_SpeedTimer')) {
        dxr.Player.Default.GroundSpeed = DefaultGroundSpeed * dxr.Player.FlagBase.GetInt('cc_moveSpeedModifier');        
    }
    if (decrementTimer('cc_SpeedTimer')) {
        dxr.Player.Default.GroundSpeed = DefaultGroundSpeed;
        PlayerMessage("Back to normal speed!");
    }

    if (decrementTimer('cc_lamthrowerTimer')) {
        UndoLamThrowers();
        PlayerMessage("Your flamethrower is boring again");

    }
    
    if (decrementTimer('cc_iceTimer')) {
        SetIcePhysics(False);
        PlayerMessage("The ground thaws");
    }
    
    if (decrementTimer('cc_behindTimer')) {
        dxr.Player.bBehindView=False;
        PlayerMessage("You re-enter your body");
    }
    
    if (decrementTimer('cc_DifficultyTimer')){
        dxr.Player.FlagBase.SetFloat('cc_damageMult',1.0);        
        PlayerMessage("Your body returns to its normal toughness");
    }
    
    if (decrementTimer('cc_floatyTimer')) {
        SetFloatyPhysics(False);
        PlayerMessage("You feel weighed down again");
    }
    
    if (decrementTimer('cc_floorLavaTimer')) {
        PlayerMessage("The floor returns to normal temperatures");
    }
    
    if (decrementTimer('cc_invertMouseTimer')) {
        PlayerMessage("Your mouse controls return to normal");
        dxr.Player.bInvertMouse = dxr.Player.FlagBase.GetBool('cc_InvertMouseDef');
    }

    if (decrementTimer('cc_invertMovementTimer')) {
        PlayerMessage("Your movement controls return to normal");
        invertMovementControls();
    }

}

function bool isCrowdControl( string msg) {
    local string tmp;
    //Validate if it looks json-like
    if (InStr(msg,"{")!=0){
        //PlayerMessage("Message doesn't start with curly");
        return False;
    }
    
    if (InStr(msg,"}")!=Len(msg)-1){
        //PlayerMessage("Message doesn't end with curly");
        return False;    
    }
    
    //Check to see if it looks like it has the right fields in it
    
    //id field
    if (InStr(msg,"id")==-1){
        return False;
    }
    
    //code field
    if (InStr(msg,"code")==-1){
        return False;
    }    
    //viewer field
    if (InStr(msg,"viewer")==-1){
        return False;
    }   
    //type field
    if (InStr(msg,"type")==-1){
        return False;
    }
    
    //Check to see if there are multiple messages stuck together
    //By removing the outermost curly brackets, we can check to
    //see if there are any more inside them (indicating one was
    //closed and another one was opened within the same message
    tmp = Mid(msg,1,Len(msg)-2);
    //PlayerMessage("Removed outer curlies: "$tmp);
    //Check for extra curly braces inside the outermost ones
    if (InStr(tmp,"{")!=-1){
        //PlayerMessage("Has extra internal open curly!");
        return False;
    }
    
    if (InStr(tmp,"}")!=-1){
        //PlayerMessage("Has extra internal close curly!");
        return False;    
    }

    return True;
}

function sendReply(int id, int status) {
    local string resp;
    local byte respbyte[255];
    local int i;
    
    resp = "{\"id\":"$id$",\"status\":"$status$"}"; 
    
    for (i=0;i<Len(resp);i++){
        respbyte[i]=Asc(Mid(resp,i,1));
    }
    
    //PlayerMessage(resp);
    SendBinary(Len(resp)+1,respbyte);
}

function bool IsGrenade(inventory i) {
    return (i.IsA('WeaponLAM') || i.IsA('WeaponGasGrenade') || i.IsA ('WeaponEMPGrenade') || i.IsA('WeaponNanoVirusGrenade'));
}

function GiveItem(class<Inventory> c) {
    class'DXRActorsBase'.static.GiveItem(dxr.Player, c);
}

function SkillPointsRemove(int numPoints) {
    dxr.Player.SkillPointsAvail -= numPoints;
    dxr.Player.SkillPointsTotal -= numPoints;

    if ((DeusExRootWindow(dxr.Player.rootWindow) != None) &&
        (DeusExRootWindow(dxr.Player.rootWindow).hud != None) && 
        (DeusExRootWindow(dxr.Player.rootWindow).hud.msgLog != None))
    {
        PlayerMessage(Sprintf(dxr.Player.SkillPointsAward, -numPoints));
        DeusExRootWindow(dxr.Player.rootWindow).hud.msgLog.PlayLogSound(Sound'LogSkillPoints');
    }
}

function UndoLamThrowers () {
    local WeaponFlamethrower f;
    foreach AllActors(class'WeaponFlamethrower', f)
    {
        f.ProjectileClass = f.Default.ProjectileClass;
        f.beltDescription = f.Default.beltDescription;
    }
}

function MakeLamThrower (inventory anItem) {
    local WeaponFlamethrower f;

    //Just in case we somehow pass something else in here...
    if (anItem.IsA('WeaponFlamethrower') == False) {
        return;
    }

    f = WeaponFlamethrower(anItem);
    f.ProjectileClass = class'LAM';
    f.beltDescription = "LAMTHWR";
}

function Class<Augmentation> getAugClass(string param) {
    switch(param) {
        case "aqualung":
            return class'AugAqualung';
        case "ballistic":
            return class'AugBallistic';
        case "cloak":
            return class'AugCloak';
        case "combat":
            return class'AugCombat';
        case "defense":
            return class'AugDefense';
        case "drone":
            return class'AugDrone';
        case "emp":
            return class'AugEmp';
        case "enviro":
            return class'AugEnviro';
        case "healing":
            return class'AugHealing';
        case "heartlung":
            return class'AugHeartLung';
        case "muscle":
            return class'AugMuscle';
        case "power":
            return class'AugPower';
        case "radartrans":
            return class'AugRadarTrans';
        case "shield":
            return class'AugShield';
        case "speed":
            return class'AugSpeed';
        case "stealth":
            return class'AugStealth';
        case "target":
            return class'AugTarget';
        case "vision":
            return class'AugVision';
        default:
            return None;
        
    }
}

//"Why not just use "GivePlayerAugmentation", you ask.
//While it works well to give the player an aug they don't
//have, it won't actually upgrade their augs if they don't 
//already have an aug upgrade canister in their inventory.
//This can also return better status messages for crowd control
function int GiveAug(Class<Augmentation> giveClass, string viewer) {
    local Augmentation anAug;
    local bool wasActive;
    
    // Checks to see if the player already has it.  If so, we want to 
    // increase the level
    anAug = dxr.Player.AugmentationSystem.FindAugmentation(giveClass);
    
    if (anAug == None) {
        PlayerMessage(viewer@"tried to give you an aug that doesn't exist?");
        return Failed; //Shouldn't happen
    }
    
    if (anAug.bHasIt)
    {
        //Upgrade scenario
        if (!(anAug.CurrentLevel < anAug.MaxLevel)) {
            PlayerMessage(viewer@"wanted to upgrade "$anAug.AugmentationName$" but it cannot be upgraded any further");
            return Failed;
        }
        wasActive = anAug.bIsActive;
        if (anAug.bIsActive) {
           anAug.Deactivate();
        }
        
        anAug.CurrentLevel++;
        
        //Since this upgrade wasn't player initiated, it would be nice to reactivate it again for them
        if (wasActive) {
            anAug.Activate();
        }
        
        PlayerMessage(viewer@"upgraded "$anAug.AugmentationName$" to level "$anAug.CurrentLevel+1);
        return Success;
    }
    
    if(dxr.Player.AugmentationSystem.AreSlotsFull(anAug)) {
        PlayerMessage(viewer@"wanted to give you "$anAug.AugmentationName$" but there is no room");
        return Failed;
    }
    
    anAug.bHasIt = True;
    
    if (anAug.bAlwaysActive)
    {
        anAug.bIsActive = True;
        anAug.GotoState('Active');
    }
    else
    {
        anAug.bIsActive = False;
    }   
    
    // Manage our AugLocs[] array
    dxr.Player.AugmentationSystem.AugLocs[anAug.AugmentationLocation].augCount++;
    
    // Assign hot key to new aug 
    // (must be after before augCount is incremented!)
    anAug.HotKeyNum = dxr.Player.AugmentationSystem.AugLocs[anAug.AugmentationLocation].augCount + dxr.Player.AugmentationSystem.AugLocs[anAug.AugmentationLocation].KeyBase;


    if ((!anAug.bAlwaysActive) && (dxr.Player.bHUDShowAllAugs))
        dxr.Player.AddAugmentationDisplay(anAug);   
    PlayerMessage(viewer@"gave you the "$anAug.AugmentationName$" augmentation");
    return Success;
}

function int AddCredits(int amount,string viewer) {
    //Reject requests to remove credits if the player doesn't have any
    if (dxr.Player.Credits == 0  && amount<0) {
        return Failed;
    }
    
    dxr.Player.Credits += amount;
    
    if (amount>0) {
        PlayerMessage(viewer@"gave you "$amount$" credits!");
    } else {
        PlayerMessage(viewer@"took away "$(-amount)$" credits!");        
    }
    
    if (dxr.Player.Credits < 0) {
        dxr.Player.Credits = 0;
    }
    return Success;
}

//This just doesn't normally exist
function int RemoveAug(Class<Augmentation> giveClass, string viewer) {
    local Augmentation anAug;
    local bool wasActive;
    
    // Checks to see if the player already has it, so we can decrease the level,
    // or remove it all together
    anAug = dxr.Player.AugmentationSystem.FindAugmentation(giveClass);
    
    if (anAug == None) {
       PlayerMessage(viewer@"tried to remove an aug that doesn't exist?");
       return Failed; //Shouldn't happen
    }
    
    if (!anAug.bHasIt)
    {
        PlayerMessage(viewer@"wanted to remove "$anAug.AugmentationName$" but you didn't have it");
        return Failed;      
    }
    
    if (anAug.CurrentLevel > 0) {
        //Downgrade scenario, has aug above base level
        
        wasActive = anAug.bIsActive;
        if (anAug.bIsActive) {
           anAug.Deactivate();
        }
        
        anAug.CurrentLevel--;
        
        //Since this downgrade wasn't player initiated, it would be nice to reactivate it again for them        
        if (wasActive) {
            anAug.Activate();
        }
        
        PlayerMessage(viewer@"downgraded "$anAug.AugmentationName$" to level "$anAug.CurrentLevel+1);
        return Success;
    }
    
    anAug.Deactivate();
    anAug.bHasIt = False;
    
    // Manage our AugLocs[] array
    dxr.Player.AugmentationSystem.AugLocs[anAug.AugmentationLocation].augCount--;
    
    //Icon lookup is BY HOTKEY, so make sure to remove the icon before the hotkey
    dxr.Player.RemoveAugmentationDisplay(anAug);
    // Assign hot key back to default
    anAug.HotKeyNum = anAug.Default.HotKeyNum;

    

    PlayerMessage(viewer@"removed your "$anAug.AugmentationName$" augmentation");
    return Success;
}


function float GetDefaultZoneFriction(ZoneInfo z)
{
    local int i;
    for(i=0; i<ArrayCount(zone_frictions); i++) {
        if( z.name == zone_frictions[i].zonename )
            return zone_frictions[i].friction;
    }
    return NormalFriction;
}

function SaveDefaultZoneFriction(ZoneInfo z)
{
    local int i;
    if( z.ZoneGroundFriction ~= NormalFriction ) return;
    for(i=0; i<ArrayCount(zone_frictions); i++) {
        if( zone_frictions[i].zonename == '' || z.name == zone_frictions[i].zonename ) {
            zone_frictions[i].zonename = z.name;
            zone_frictions[i].friction = z.ZoneGroundFriction;
            return;
        }
    }
}

function vector GetDefaultZoneGravity(ZoneInfo z)
{
    local int i;
    for(i=0; i<ArrayCount(zone_gravities); i++) {
        if( z.name == zone_gravities[i].zonename )
            return zone_gravities[i].gravity;
        if( zone_gravities[i].zonename == '' )
            break;
    }
    return NormalGravity;
}

function SaveDefaultZoneGravity(ZoneInfo z)
{
    local int i;
    if( z.ZoneGravity.X ~= NormalGravity.X && z.ZoneGravity.Y ~= NormalGravity.Y && z.ZoneGravity.Z ~= NormalGravity.Z ) return;
    for(i=0; i<ArrayCount(zone_gravities); i++) {
        if( z.name == zone_gravities[i].zonename )
            return;
        if( zone_gravities[i].zonename == '' ) {
            zone_gravities[i].zonename = z.name;
            zone_gravities[i].gravity = z.ZoneGravity;
            return;
        }
    }
}

function SetFloatyPhysics(bool enabled) {
    local ZoneInfo Z;
    ForEach AllActors(class'ZoneInfo', Z)
    {
        log("SetFloatyPhysics "$Z$" gravity: "$Z.ZoneGravity);
        if (enabled) {
            SaveDefaultZoneGravity(Z);
            Z.ZoneGravity = FloatGrav;
        }
        else if ( (!enabled) && Z.ZoneGravity == FloatGrav ) {
            Z.ZoneGravity = GetDefaultZoneGravity(Z);
        }
    }
}

function SetMoonPhysics(bool enabled) {
    local ZoneInfo Z;
    ForEach AllActors(class'ZoneInfo', Z)
    {
        log("SetFloatyPhysics "$Z$" gravity: "$Z.ZoneGravity);
        if (enabled) {
            SaveDefaultZoneGravity(Z);
            Z.ZoneGravity = MoonGrav;
        }
        else if ( (!enabled) && Z.ZoneGravity == MoonGrav ) {
            Z.ZoneGravity = GetDefaultZoneGravity(Z);
        }
    }
}

function SetIcePhysics(bool enabled) {
    local ZoneInfo Z;
    ForEach AllActors(class'ZoneInfo', Z) {
        if (enabled) {
            SaveDefaultZoneFriction(Z);
            Z.ZoneGroundFriction = IceFriction;
        }
        else if ( (!enabled) && Z.ZoneGroundFriction == IceFriction ) {
            Z.ZoneGroundFriction = GetDefaultZoneFriction(Z);
        }
    }
}


//Returns true when you aren't in a menu, or in the intro, etc.
function bool InGame() {
    if (None == DeusExRootWindow(dxr.Player.rootWindow)) {
        return False;
    }
    
    if (None == DeusExRootWindow(dxr.Player.rootWindow).hud) {
        return False;
    }
    
    if (!DeusExRootWindow(dxr.Player.rootWindow).hud.isVisible()){
        return False;
    }
    
    return True;
}


function int doCrowdControlEvent(string code, string param[5], string viewer, int type) {
    local vector v;
    local inventory anItem;
    local int i;
    local bool result;
    local Actor a;
    v.X=0;
    v.Y=0;
    v.Z=0;
    
    switch(code) {
        case "poison":
            if (!InGame()) {
                return TempFail;
            }
        
            dxr.Player.StartPoison(dxr.Player,5);
            PlayerMessage(viewer@"poisoned you!");
            break;

        case "kill":
            dxr.Player.Died(dxr.Player,'CrowdControl',v);
            PlayerMessage(viewer@"set off your killswitch!");
            dxr.Player.MultiplayerDeathMsg(dxr.Player,False,True,viewer,"triggering your kill switch");
            break;

        case "drop_grenade":
             
             //Don't drop grenades if you're in the menu
             if (!InGame()) {
                 return TempFail;
             }
             
             //Don't drop grenades if you're in a conversation - It screws things up
             if (dxr.Player.InConversation()) {
                 return TempFail;
             }
        
            //Spawned ThrownProjectiles won't beep if they don't have an owner,
            //so make sure to set one here (the player)
            switch(param[0]){
                case("g_lam"):
                    a = Spawn(Class'LAM',dxr.Player,,dxr.Player.Location);
                    PlayerMessage(viewer@"dropped a LAM at your feet!");
                    break;
                case("g_emp"):
                    a = Spawn(Class'EMPGrenade',dxr.Player,,dxr.Player.Location);
                    PlayerMessage(viewer@"dropped an EMP grenade at your feet!");
                    break;
                case("g_gas"):
                    a = Spawn(Class'GasGrenade',dxr.Player,,dxr.Player.Location);
                    PlayerMessage(viewer@"dropped a gas grenade at your feet!");
                    break;
                case("g_scrambler"):
                    a = Spawn(Class'NanoVirusGrenade',dxr.Player,,dxr.Player.Location);
                    PlayerMessage(viewer@"dropped a scramble grenade at your feet!");
                    break;
                default:
                    return Failed;
            }
            a.Velocity.X=0;
            a.Velocity.Y=0;
            a.Velocity.Z=0;
            break;

        case "glass_legs":
            dxr.Player.HealthLegLeft=1;
            dxr.Player.HealthLegRight=1;
            dxr.Player.GenerateTotalHealth();
            PlayerMessage(viewer@"gave you glass legs!");
            break;

        case "give_health":
            if (dxr.Player.Health == 100) {
                return TempFail;
            }
            dxr.Player.HealPlayer(Int(param[0]),False);
            PlayerMessage(viewer@"gave you "$param[0]$" health!");
            break;

        case "set_fire":
            dxr.Player.CatchFire(dxr.Player);
            PlayerMessage(viewer@"set you on fire!");
            break;

        case "give_medkit":
            GiveItem(class'MedKit');
            PlayerMessage(viewer@"gave you a medkit");
            break;

        case "full_heal":
            if (dxr.Player.Health == 100) {
                return TempFail;
            }
            dxr.Player.RestoreAllHealth();
            PlayerMessage(viewer@"fully healed you!");
            break;

        case "disable_jump":
            if (dxr.Player.JumpZ == 0) {
                return TempFail;
            }

            dxr.Player.JumpZ = 0;
            setTimerFlag('cc_JumpTimer',JumpTimeDefault);
            PlayerMessage(viewer@"made your knees lock up.");
            break;

        case "gotta_go_fast":
            if (DefaultGroundSpeed != dxr.Player.Default.GroundSpeed) {
                return TempFail;
            }
            dxr.Player.FlagBase.SetInt('cc_moveSpeedModifier',MoveSpeedMultiplier);
            dxr.Player.Default.GroundSpeed = DefaultGroundSpeed * moveSpeedMultiplier;
            setTimerFlag('cc_SpeedTimer',SpeedTimeDefault);
            PlayerMessage(viewer@"made you fast like Sonic!");
            break;

        case "gotta_go_slow":
            if (DefaultGroundSpeed != dxr.Player.Default.GroundSpeed) {
                return TempFail;
            }
            dxr.Player.FlagBase.SetInt('cc_moveSpeedModifier',MoveSpeedDivisor);
            dxr.Player.Default.GroundSpeed = DefaultGroundSpeed * moveSpeedDivisor;
            setTimerFlag('cc_SpeedTimer',SpeedTimeDefault);
            PlayerMessage(viewer@"made you slow like a snail!");
            break;
        case "drunk_mode":
            if (dxr.Player.drugEffectTimer<30.0) {
                dxr.Player.drugEffectTimer+=60.0;
            } else {
                return TempFail;
            }
            PlayerMessage(viewer@"got you tipsy!");
            break;

        case "drop_selected_item":
            if (dxr.Player.InHand == None) {
                return TempFail;
            }
            result = dxr.Player.DropItem();
            if (result == False) {
                return TempFail;
            }
            PlayerMessage(viewer@"made you fumble your item");
            break;

        case "emp_field":
            dxr.Player.bWarrenEMPField = true;
            setTimerFlag('cc_EmpTimer',EmpDefault);
            PlayerMessage(viewer@"made electronics allergic to you");
            break;

        case "matrix":
            if (dxr.Player.Sprite!=None) {
                //Matrix Mode already enabled
                return TempFail;
            }
            StartMatrixMode();
            setTimerFlag('cc_MatrixModeTimer',MatrixTimeDefault);
            PlayerMessage(viewer@"thinks you are The One...");
            break;
            
        case "third_person":
            if (isTimerActive('cc_behindTimer')) {
                return TempFail;
            }
            dxr.Player.bBehindView=True;
            setTimerFlag('cc_behindTimer',BehindTimeDefault);
            PlayerMessage(viewer@"gave you an out of body experience");
            break;

        case "give_energy":
            
            if (dxr.Player.Energy == dxr.Player.EnergyMax) {
                return TempFail;
            }
            //Copied from BioelectricCell

            //PlayerMessage("Recharged 10 points");
            dxr.Player.PlaySound(sound'BioElectricHiss', SLOT_None,,, 256);

            dxr.Player.Energy += Int(param[0]);
            if (dxr.Player.Energy > dxr.Player.EnergyMax)
                dxr.Player.Energy = dxr.Player.EnergyMax;

            PlayerMessage(viewer@"gave you "$param[0]$" energy!");
            break;

       case "give_biocell":
            GiveItem(class'BioelectricCell');
            PlayerMessage(viewer@"gave you a bioelectric cell!");
            break;

        case "give_skillpoints":
            i = Int(param[0])*100;
            PlayerMessage(viewer@"gave you "$i$" skill points");
            dxr.Player.SkillPointsAdd(i);
            break;

        case "remove_skillpoints":
            i = Int(param[0])*100;
            PlayerMessage(viewer@"took away "$i$" skill points");
            SkillPointsRemove(i);
            break;
            
        case "add_credits":
            return AddCredits(Int(param[0])*100,viewer);
            break;
        case "remove_credits":
            return AddCredits(-Int(param[0])*100,viewer);
            break;

        case "lamthrower":
            if (isTimerActive('cc_lamthrowerTimer')) {
                return TempFail;
            }
            
            anItem = dxr.Player.FindInventoryType(class'WeaponFlamethrower');
            if (anItem==None) {
                return TempFail;
            }

            MakeLamThrower(anItem);
            setTimerFlag('cc_lamthrowerTimer',LamThrowerTimeDefault);
            PlayerMessage(viewer@"turned your flamethrower into a LAM Thrower!");
            break;

        case "give_grenade":
            PlayerMessage(viewer@"Gave you a grenade");
            switch(param[0]){
                case("g_lam"):
                    GiveItem(Class'WeaponLAM');
                    break;
                case("g_emp"):
                    GiveItem(Class'WeaponEMPGrenade');
                    break;
                case("g_gas"):
                    GiveItem(Class'WeaponGasGrenade');
                    break;
                case("g_scrambler"):
                    GiveItem(Class'WeaponNanoVirusGrenade');
                    break;
                default:
                    return Failed;
            }
            break;
            
        case "give_weapon":
            PlayerMessage(viewer@"Gave you a weapon");

            switch(param[0]){
                case "flamethrower":
                    GiveItem(class'WeaponFlamethrower');
                    break;
                case "gep":
                    GiveItem(class'WeaponGEPGun');
                    break;
                case "dts":
                    GiveItem(class'WeaponNanoSword');
                    break;
                case "plasma":
                    GiveItem(class'WeaponPlasmaRifle');
                    break;
                case "law":
                    GiveItem(class'WeaponLAW');
                    break;
                case "sniper":
                    GiveItem(class'WeaponRifle');
                    break;
                case "assaultgun":
                    GiveItem(class'WeaponAssaultGun');
                    break;
                case "assaultshotgun":
                    GiveItem(class'WeaponAssaultShotgun');
                    break;
                case "baton":
                    GiveItem(class'WeaponBaton');
                    break;
                case "knife":
                    GiveItem(class'WeaponCombatKnife');
                    break;
                case "crowbar":
                    GiveItem(class'WeaponCrowbar');
                    break;
                case "crossbow":
                    GiveItem(class'WeaponMiniCrossbow');
                    break;
                case "pepperspray":
                    GiveItem(class'WeaponPepperGun');
                    break;
                case "pistol":
                    GiveItem(class'WeaponPistol');
                    break;
                case "stealthpistol":
                    GiveItem(class'WeaponStealthPistol');
                    break;
                case "prod":
                    GiveItem(class'WeaponProd');
                    break;
                case "sawedoff":
                    GiveItem(class'WeaponSawedOffShotgun');
                    break;
                case "shuriken":
                    GiveItem(class'WeaponShuriken');
                    break;
                case "sword":
                    GiveItem(class'WeaponSword');
                    break;
                
                default:
                    return Failed;
            }
            break;

        case "give_ps40":
            PlayerMessage(viewer@"Gave you a PS40");

            GiveItem(class'WeaponHideAGun');
            break;

        case "up_aug":
            return GiveAug(getAugClass(param[0]),viewer);         
        
        case "down_aug":
            return RemoveAug(getAugClass(param[0]),viewer);        
        
        case "dmg_double":
            if (isTimerActive('cc_DifficultyTimer')) {
                return TempFail;
            }
            dxr.Player.FlagBase.SetFloat('cc_damageMult',2.0);
           
            PlayerMessage(viewer@"made your body extra squishy");
            setTimerFlag('cc_DifficultyTimer',DifficultyTimeDefault);
            break;
        case "dmg_half":
            if (isTimerActive('cc_DifficultyTimer')) {
                return TempFail;
            }
            dxr.Player.FlagBase.SetFloat('cc_damageMult',0.5);
            PlayerMessage(viewer@"made your body extra tough!");
            setTimerFlag('cc_DifficultyTimer',DifficultyTimeDefault);
            break;
        
        case "ice_physics":
            if (isTimerActive('cc_iceTimer')) {
                return TempFail;
            }
            PlayerMessage(viewer@"made the ground freeze!");
            SetIcePhysics(True);
            setTimerFlag('cc_iceTimer',IceTimeDefault);

            break;      
        
        case "ask_a_question":
            if (!InGame()) {
                return TempFail;
            }
            AskRandomQuestion(viewer);
            break;

        case "nudge":
            if (!InGame()) {
                return TempFail;
            }

            doNudge(viewer);
            break;
            
        case "swap_player_position":
            if (!InGame()) {
                return TempFail;
            }
            if (swapPlayer(viewer) == false) {
                return Failed;
            }
            break;
            
        case "floaty_physics":
            if (isTimerActive('cc_floatyTimer')) {
                return TempFail;
            }
            PlayerMessage(viewer@"made you feel light as a feather");
            SetFloatyPhysics(True);
            setTimerFlag('cc_floatyTimer',FloatyTimeDefault);

            break;   
        
        case "give_ammo":
            return GiveAmmo(viewer,param[0],Int(param[1]));
            break;
        
        case "floor_is_lava":
            if (!InGame()) {
                return TempFail;
            }
            if (isTimerActive('cc_floorLavaTimer')){
                return TempFail;
            }
            PlayerMessage(viewer@"turned the floor into lava!");
            lavaTick = 0;
            setTimerFlag('cc_floorLavaTimer',FloorLavaTimeDefault);
            
            break;
            
        case "invert_mouse":
            if (!InGame()) {
                return TempFail;
            }
            if (isTimerActive('cc_invertMouseTimer')){
                return TempFail;
            }
            PlayerMessage(viewer@"inverted your mouse!");
            dxr.Player.FlagBase.SetBool('cc_InvertMouseDef',dxr.Player.bInvertMouse);

            dxr.Player.bInvertMouse = !dxr.Player.bInvertMouse;
            setTimerFlag('cc_invertMouseTimer',InvertMouseTimeDefault);

            break;
            
        case "invert_movement":
            if (!InGame()) {
                return TempFail;
            }
            if (isTimerActive('cc_invertMovementTimer')){
                return TempFail;
            }
            PlayerMessage(viewer@"inverted your movement controls!");
            
            invertMovementControls();

            setTimerFlag('cc_invertMovementTimer',InvertMovementTimeDefault);
            break;
        
        default:
            return NotAvail;
    }
    return Success;
}

function invertMovementControls() {
    local string fwdInputs[5];
    local string backInputs[5];
    local string leftInputs[5];
    local string rightInputs[5];
    
    local int numFwd;
    local int numBack;
    local int numLeft;
    local int numRight;
    
    local string KeyName;
    local string Alias;
    
    local int i;
    
    for (i=0;i<255;i++) {
        KeyName = dxr.Player.ConsoleCommand("KEYNAME "$i);
        if (KeyName!="") {
            Alias = dxr.Player.ConsoleCommand("KEYBINDING "$KeyName);
            //PlayerMessage("Alias is "$Alias);
            switch(Alias){
                case "MoveForward":
                    fwdInputs[numFwd] = KeyName;
                    numFwd++;
                    break;
                case "MoveBackward":
                    backInputs[numBack] = KeyName;
                    numBack++;
                    break;
                case "StrafeLeft":
                    leftInputs[numLeft] = KeyName;
                    numLeft++;
                    break;
                case "StrafeRight":
                    rightInputs[numRight] = KeyName;
                    numRight++;
                    break;
            }
        }
    }
    
    for (i=0;i<numFwd;i++){
        dxr.Player.ConsoleCommand("SET InputExt "$fwdInputs[i]$" MoveBackward");
    }
    for (i=0;i<numBack;i++){
        dxr.Player.ConsoleCommand("SET InputExt "$backInputs[i]$" MoveForward");
    }
    for (i=0;i<numRight;i++){
        dxr.Player.ConsoleCommand("SET InputExt "$rightInputs[i]$" StrafeLeft");
    }
    for (i=0;i<numLeft;i++){
        dxr.Player.ConsoleCommand("SET InputExt "$leftInputs[i]$" StrafeRight");
    }    
    
}

function floorIsLava() {
    local vector v;
    local vector loc;
    loc.X = dxr.Player.Location.X;
    loc.Y = dxr.Player.Location.Y;
    loc.Z = dxr.Player.Location.Z - 1;
    if ((dxr.Player.Base.IsA('LevelInfo') ||
         dxr.Player.Base.IsA('Mover')) &&
         Human(dxr.Player).bOnLadder==False)        {
        lavaTick++;   
        //PlayerMessage("Standing on Lava! "$lavaTick);        
    } else {
        lavaTick = 0;
        //PlayerMessage("Not Lava "$dxr.Player.Base);
        return;
    }
    
    if ((lavaTick % 10)==0) { //If you stand on lava for 1 second
        dxr.Player.TakeDamage(10,dxr.Player,loc,v,'Burned');
    }
    
    if ((lavaTick % 50)==0) { //if you stand in lava for 5 seconds
        dxr.Player.CatchFire(dxr.Player);
    }
}

function int GiveAmmo(string viewer, string ammotype, int amount) {
    local int i;
    local class<DeusExAmmo> ammo;
    
    local string outMsg;
    
    outMsg = viewer@"gave you"@amount;
    
    if (amount == 1) {
        outMsg = outMsg@"case of";
    } else {
        outMsg = outMsg@"cases of";
    }
    
    ammo = class<DeusExAmmo>(ccModule.GetClassFromString(ammotype,class'DeusExAmmo'));
    
    outMsg = outMsg@ammo.Default.ItemName;
    
    if (ammo == None) {
        return NotAvail;
    }
    
    for (i=0;i<amount;i++) {
        GiveItem(ammo);   
    }
    PlayerMessage(outMsg);
    return Success;
}

function ScriptedPawn findOtherHuman() {
    local int num;
    local ScriptedPawn p;
    local ScriptedPawn humans[512];
    
    num = 0;
    
    foreach AllActors(class'ScriptedPawn',p) {
        if (class'DXRActorsBase'.static.IsHuman(p) && p!=dxr.Player && !p.bHidden && !p.bStatic && p.bInWorld && p.Orders!='Sitting') {
            humans[num++] = p;
        }
    }

    if( num == 0 ) return None;
    return humans[ Rand(num) ];
}

function bool swapPlayer(string viewer) {
    local Actor a;
    
    a = findOtherHuman();
    
    if (a == None) {
        return false;
    }
    
    ccModule.Swap(dxr.Player,a);
    dxr.Player.ViewRotation = dxr.Player.Rotation;
    PlayerMessage(viewer@"thought you would look better if you were where"@a.tag@"was");
    
    return true;
}

function doNudge(string viewer) {
    local Rotator r;
    local vector newAccel;
    
    newAccel.X = Rand(201)-100;
    newAccel.Y = Rand(201)-100;
    //newAccel.Z = Rand(31);
    
    //Not super happy with how this looks,
    //Since you sort of just teleport to the new position
    dxr.Player.MoveSmooth(newAccel);
    
    //Play an oof sound
    dxr.Player.PlaySound(Sound'DeusExSounds.Player.MalePainSmall');
    
    PlayerMessage(viewer@"nudged you a little bit");

}

function AskRandomQuestion(String viewer) {
    
    local string question;
    local string answers[3];
    local int numAnswers;
    
    ccModule.getRandomQuestion(question,numAnswers,answers[0],answers[1],answers[2]);
    
    ccModule.CreateCustomMessageBox(viewer$" asks...",question,numAnswers,answers,ccModule,1,True);
    
}


function handleMessage( string msg) {
  
    local int id,type;
    local string code,viewer;
    local string param[5];
    
    local int result;
    
    local JsonMsg jmsg;
    local string val;
    local int i,j;

    if (isCrowdControl(msg)) {
        jmsg=ParseJson(msg);
        
        for (i=0;i<jmsg.count;i++) {
            if (jmsg.e[i].valCount>0) {
                val = jmsg.e[i].value[0];
                //PlayerMessage("Key: "$jmsg.e[i].key);
                switch (jmsg.e[i].key) {
                    case "code":
                        code = val;
                        break;
                    case "viewer":
                        viewer = val;
                        break;
                    case "id":
                        id = Int(val);
                        break;
                    case "type":
                        type = Int(val);
                        break;
                    case "parameters":
                        for (j=0;j<5;j++) {
                            param[j] = jmsg.e[i].value[j];
                        }
                        break;
                }
            }
        }
        
        //Streamers may not want names to show up in game
        //so that they can avoid troll names, etc
        if (anon) {
            viewer = "Crowd Control";
        }
        result = doCrowdControlEvent(code,param,viewer,type);
        
        sendReply(id,result);
        
    } else {
        err("Got a weird message: "$msg);
    }

}

//I cannot believe I had to manually write my own version of ReceivedBinary
function ManualReceiveBinary() {
    local byte B[255]; //I have to use a 255 length array even if I only want to read 1
    local int count,i;
    //PlayerMessage("Manually reading, have "$DataPending$" bytes pending");
    
    if (DataPending!=0) {
        count = ReadBinary(255,B);
        for (i = 0; i < count; i++) {
            if (B[i] == 0) {
                if (Len(pendingMsg)>0){
                    //PlayerMessage(pendingMsg);
                    handleMessage(pendingMsg);
                }
                pendingMsg="";
            } else {
                pendingMsg = pendingMsg $ Chr(B[i]);
                //PlayerMessage("ReceivedBinary: " $ B[i]);
            }
        }
    }
    
}

event ReceivedText ( string Text ) {
    //Text mode seems to just drop anything past a null terminator
    //so if multiple messages are received back to back before
    //we get around to reading it, any past the first may be
    //discarded entirely
    handleMessage(Text);
}

//In the context of crowd control, this behaves the same as ReceivedText
//This is because there are no linebreaks in the messages, they are just
//null terminated
event ReceivedLine ( string Text ) {
    handleMessage(Text);
}


//This seems to just receive crazy garbage and is completely broken.
event ReceivedBinary(int count, byte B[255]) {
    local int i;
    for (i = 0; i < count; i++) {
        //log("Got character val "$i+1$" = "$B[i]);
        if (B[i] == 0) {
            //handleMessage(pendingMsg);
            if (Len(pendingMsg)>0){
            //PlayerMessage("got message (maybe): "$pendingMsg);
            }
            pendingMsg="";
        } else {
            pendingMsg = pendingMsg $ Chr(B[i]);
            //PlayerMessage("ReceivedBinary: " $ B[i]);
        }
    }
    PlayerMessage("Count was "$count);
}

event Opened(){
    PlayerMessage("Crowd Control connection opened");
}

event Closed(){
    PlayerMessage("Crowd Control connection closed");
    ListenPort = 0;
    reconnectTimer = ReconDefault;
}

event Destroyed(){
    Close();
    Super.Destroyed();
}

function Resolved( IpAddr Addr )
{
    if (ListenPort == 0) {
        ListenPort=BindPort();
        if (ListenPort==0){
            err("Failed to bind port for Crowd Control");
            reconnectTimer = ReconDefault;
            return;
        }   
    }

    Addr.port=CrowdControlPort;
    if (False==Open(Addr)){
        err("Could not connect to Crowd Control client");
        reconnectTimer = ReconDefault;
        return;

    }

    //Using manual binary reading, which is handled by ManualReceiveBinary()
    //This means that we can handle if multiple crowd control messages come in
    //between reads.
    LinkMode=MODE_Binary;
    ReceiveMode = RMODE_Manual;

}
function ResolveFailed()
{
    err("Could not resolve Crowd Control address");
    reconnectTimer = ReconDefault;
}

function PlayerMessage(string msg)
{
    log(Self$": "$msg);
    class'DXRTelemetry'.static.SendLog(dxr, Self, "INFO", msg);
    dxr.Player.ClientMessage(msg);
}

function err(string msg)
{
    log(Self$": ERROR: "$msg);
    class'DXRTelemetry'.static.SendLog(dxr, Self, "ERROR", msg);
    dxr.Player.ClientMessage(msg);
}

function info(string msg)
{
    log(Self$": INFO: "$msg);
    class'DXRTelemetry'.static.SendLog(dxr, Self, "INFO", msg);
}

function RunTests(DXRCrowdControl m)
{
    local int i;
    local string msg;
    local string params[5];

    msg="";
    m.testbool( isCrowdControl(msg), false, "isCrowdControl "$msg);

    msg="{}";
    m.testbool( isCrowdControl(msg), false, "isCrowdControl "$msg);

    TestMsg(m, 123, 1, "kill", "die4ever", params);
    TestMsg(m, 123, 1, "test with spaces", "die4ever", params);
    TestMsg(m, 123, 1, "test:with:colons", "die4ever", params);
    TestMsg(m, 123, 1, "test,with,commas", "die4ever", params);
    params[0] = "parameter test";
    TestMsg(m, 123, 1, "kill", "die4ever", params);
    params[0] = "g_scrambler";
    TestMsg(m, 123, 1, "drop_grenade", "die4ever", params);
    params[0] = "g_scrambler";
    params[1] = "10";
    TestMsg(m, 123, 1, "drop_grenade", "die4ever", params);
    
    //Need to do more work to validate escaped characters
    //TestMsg(m, 123, 1, "test\\\\with\\\\escaped\\\\backslashes", "die4ever", ""); //Note that we have to double escape so that the end result is a single escaped backslash
}

function TestMsg(DXRCrowdControl m, int id, int type, string code, string viewer, string params[5])
{
    local int i, p, matches, num_params;
    local string msg, val, params_string;
    local JsonMsg jmsg;

    for(i=0; i < ArrayCount(params); i++) {
        if( params[i] != "" ) num_params++;
    }

    if( num_params > 1 ) {
        params_string = "[";
        for(i=0; i < ArrayCount(params); i++) {
            if( params[i] != "" )
                params_string = params_string $ params[i] $ ",";
        }
        params_string = Left(params_string, Len(params_string)-1);//trim trailing comma
        params_string = params_string $ "]";
    }
    else if ( num_params <= 1 )
        params_string = "\""$params[0]$"\"";

    msg="{\"id\":\""$id$"\",\"code\":\""$code$"\",\"viewer\":\""$viewer$"\",\"type\":\""$type$"\",\"parameters\":"$params_string$"}";

    m.testbool( isCrowdControl(msg), true, "isCrowdControl: "$msg);

    jmsg=ParseJson(msg);
    for (i=0;i<jmsg.count;i++) {
        if (jmsg.e[i].valCount>0) {
            val = jmsg.e[i].value[0];
            switch (jmsg.e[i].key) {
                case "code":
                    m.teststring(val, code, "code");
                    matches++;
                    break;
                case "viewer":
                    m.teststring(val, viewer, "viewer");
                    matches++;
                    break;
                case "id":
                    m.testint(Int(val), id, "id");
                    matches++;
                    break;
                case "type":
                    m.testint(Int(val), type, "type");
                    matches++;
                    break;
                case "parameters":
                    for(p=0; p<ArrayCount(params); p++) {
                        m.teststring(jmsg.e[i].value[p], params[p], "param "$p);
                    }
                    matches++;
                    break;
            }
        }
    }

    m.testint(matches, 5, "5 matches for msg: "$msg);
}

defaultproperties
{
    NormalGravity=vect(0,0,-950)
    FloatGrav=vect(0,0,0.15)
    MoonGrav=vect(0,0,-300)
}

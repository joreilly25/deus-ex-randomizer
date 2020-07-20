class DXRActorsBase extends DXRBase;

function SwapAll(name classname)
{
    local Actor a, b;
    local int num, i, slot;

    SetSeed( "SwapAll " $ classname );
    num=0;
    foreach AllActors(class'Actor', a )
    {
        if( SkipActor(a, classname) ) continue;
        num++;
    }

    foreach AllActors(class'Actor', a )
    {
        if( SkipActor(a, classname) ) continue;

        i=0;
        slot=rng(num-1);
        foreach AllActors(class'Actor', b )
        {
            if( SkipActor(b, classname) ) continue;

            if(i==slot) {
                Swap(a, b);
                break;
            }
            i++;
        }
    }
}

function vector AbsEach(vector v)
{// not a real thing in math? but it's convenient
    v.X = abs(v.X);
    v.Y = abs(v.Y);
    v.Z = abs(v.Z);
    return v;
}

function bool AnyGreater(vector a, vector b)
{
    return a.X > b.X || a.Y > b.Y || a.Z > b.Z;
}

function bool CarriedItem(Actor a)
{// I need to check Engine.Inventory.bCarriedItem
    return a.Owner != None && a.Owner.IsA('Pawn');
}

function bool SkipActorBase(Actor a)
{
    if( (a.Owner != None) || a.bStatic || a.bHidden || a.bMovable==False )
        return true;
    if( a.Base != None )
        return a.Base.IsA('ScriptedPawn');
    return false;
}

function bool SkipActor(Actor a, name classname)
{
    return SkipActorBase(a) || ( ! a.IsA(classname) ) || a.IsA('BarrelAmbrosia') || a.IsA('BarrelVirus') || a.IsA('NanoKey');
}

function Swap(Actor a, Actor b)
{
    local vector newloc;
    local rotator newrot;
    local bool asuccess, bsuccess;
    local Actor abase, bbase;
    local bool AbCollideActors, AbBlockActors, AbBlockPlayers, BbCollideActors, BbBlockActors, BbBlockPlayers;
    local EPhysics aphysics, bphysics;

    if( a == b ) return;

    l("swapping "$ActorToString(a)$" and "$ActorToString(b));

    // https://docs.unrealengine.com/udk/Two/ActorVariables.html#Advanced
    // native(262) final function SetCollision( optional bool NewColActors, optional bool NewBlockActors, optional bool NewBlockPlayers );
    AbCollideActors = a.bCollideActors;
    AbBlockActors = a.bBlockActors;
    AbBlockPlayers = a.bBlockPlayers;
    BbCollideActors = b.bCollideActors;
    BbBlockActors = b.bBlockActors;
    BbBlockPlayers = b.bBlockPlayers;
    a.SetCollision(false, false, false);
    b.SetCollision(false, false, false);

    newloc = b.Location + (a.CollisionHeight - b.CollisionHeight) * vect(0,0,1);
    newrot = b.Rotation;

    bsuccess = b.SetLocation(a.Location + (b.CollisionHeight - a.CollisionHeight) * vect(0,0,1) );
    b.SetRotation(a.Rotation);

    if( bsuccess == false )
        l("failed to move " $ ActorToString(b) $ " into location of " $ ActorToString(a) );

    asuccess = a.SetLocation(newloc);
    a.SetRotation(newrot);

    if( asuccess == false )
        l("failed to move " $ ActorToString(a) $ " into location of " $ ActorToString(b) );

    aphysics = a.Physics;
    bphysics = b.Physics;
    abase = a.Base;
    bbase = b.Base;

    if(asuccess)
    {
        a.SetPhysics(bphysics);
        if(abase != bbase) a.SetBase(bbase);
    }
    if(bsuccess)
    {
        b.SetPhysics(aphysics);
        if(abase != bbase) b.SetBase(abase);
    }

    a.SetCollision(AbCollideActors, AbBlockActors, AbBlockPlayers);
    b.SetCollision(BbCollideActors, BbBlockActors, BbBlockPlayers);
}

function bool DestroyActor( Actor d )
{
	// If this item is in an inventory chain, unlink it.
    local Decoration downer;

    if( d.IsA('Inventory') && d.Owner != None && d.Owner.IsA('Pawn') )
    {
        Pawn(d.Owner).DeleteInventory( Inventory(d) );
    }
    return d.Destroy();
}

function string ActorToString( Actor a )
{
    local string out;
    out = a.Class.Name$":"$a.Name$"("$a.Location$")";
    if( a.Base != None && a.Base.Class!=class'LevelInfo' )
        out = out $ "(Base:"$a.Base.Class$":"$a.Base.Name$")";
    return out;
}

function SetActorScale(Actor a, float scale)
{
    local bool AbCollideActors, AbBlockActors, AbBlockPlayers;
    local Vector newloc;
    
    AbCollideActors = a.bCollideActors;
    AbBlockActors = a.bBlockActors;
    AbBlockPlayers = a.bBlockPlayers;
    a.SetCollision(false, false, false);
    newloc = a.Location + ( (a.CollisionHeight*scale - a.CollisionHeight*a.DrawScale) * vect(0,0,1) );
    a.SetCollisionSize(a.CollisionRadius, a.CollisionHeight / a.DrawScale * scale);
    a.DrawScale = scale;
    a.SetLocation(newloc);
    a.SetCollision(AbCollideActors, AbBlockActors, AbBlockPlayers);
}

function bool PositionIsSafe(Vector oldloc, Actor test, Vector newloc)
{// https://github.com/Die4Ever/deus-ex-randomizer/wiki#smarter-key-randomization
    local Vector MinVect, MaxVect, TestPoint, distsold, diststest, distsoldtest, a, b;
    local float distold, disttest;

    test.GetBoundingBox(MinVect, MaxVect);
    TestPoint = (MinVect+MaxVect)/2;
    /*a = AbsEach(oldloc - MinVect);
    b = AbsEach(oldloc - MaxVect);
    if( a.X < b.X ) TestPoint.X = b.X;
    if( a.Y < b.Y ) TestPoint.Y = b.Y;
    if( a.Z < b.Z ) TestPoint.Z = b.Z;*/

    distold = VSize(newloc - oldloc);
    disttest = VSize(newloc - TestPoint);

    if( distold > disttest ) return False;

    distsoldtest = AbsEach(oldloc - TestPoint);
    distsold = AbsEach(newloc - oldloc) - distsoldtest;
    diststest = AbsEach(newloc - TestPoint);
    if ( AnyGreater( distsold, diststest ) ) return False;
    
    return True;
}

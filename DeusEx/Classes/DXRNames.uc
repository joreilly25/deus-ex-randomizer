class DXRNames extends DXRBase;

function FirstEntry()
{
    local ScriptedPawn p;
    local DeusExCarcass c;
    Super.FirstEntry();

    SetSeed( "DXRNames" );

    foreach AllActors(class'ScriptedPawn', p)
    {
        if( p.bImportant ) continue;
        
        p.UnfamiliarName = RandomName();
        p.FamiliarName = p.UnfamiliarName;
    }

    foreach AllActors(class'DeusExCarcass', c)
    {
        if ( c.itemName != "Dead Body" && c.itemName != "Unconscious" && c.itemName != "Animal Carcass" )
            return;
        c.itemName = c.itemName $ " (" $ RandomName() $ ")";
    }
}

function string RandomName()
{
    local string n;
    local bool vowel;
    local int length, num_vowels, num_cons, i, a;
    local string vowels, cons, s;

    vowels = "aeiouy";
    //cons = "bcdfghjklmnpqrstvwxz";
    cons = "bcdfghjklmnprstvwx";

    num_vowels = Len(vowels);
    num_cons = Len(cons);

    length = rng(4)+2;
    if( rng(2) == 0 ) vowel = true;

    for( i=0; i < length; i++ ) {
        if( vowel ) {
            vowel = false;
            a = rng(num_vowels)+1;
            s = Left(vowels, a);
            s = Right(s, 1);
            n = n $ s;
        } else {
            vowel = true;
            a = rng(num_cons)+1;
            s = Left(cons, a);
            s = Right(s, 1);
            n = n $ s;
        }
        if ( i == 0 ) n = Caps(n);
    }
    return n;
}

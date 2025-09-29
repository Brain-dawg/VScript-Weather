IncludeScript( "weather/ents/env_wind.nut" )

for (local wind; wind = Entities.FindByName( wind, "__wind*"); )
    EntFireByHandle( wind, "Kill", null, -1, null, null )

local wind = CScriptEnvWind( "__wind", {

    minwind = 50,
    maxwind = 200,
    mingust = 100,
    maxgust = 200,
    mingustdelay = 0,
    maxgustdelay = 1,
    gustduration = 5,
    gustdirchange = 50

}).self

local prop = SpawnEntityFromTable( "info_particle_system", {
    targetname = "__prop",
    effect_name = "env_rain_gutterdrip",
    origin = Vector( -746.697876, -2470.621338, 740.933960 ),
    start_active = true
})

wind.ValidateScriptScope()

WindScope <- wind.GetScriptScope()

function WindScope::WindThink() {

    // foreach ( prop, val in WindScope.WindProps ) {

    //     local type = typeof val

    //     if ( type == "float" )
    //         printf( "%s: %.8f\n", prop, NetProps.GetPropFloat( wind, prop ) )
    //     else if ( type == "int" )
    //         printf( "%s: %d\n", prop, NetProps.GetPropInt( wind, prop ) )
    //     else 
    //         printf( "%s: %s\n", prop, val.tostring() )
    // }

    local wind_speed = NetProps.GetPropFloat( wind, "m_EnvWindShared.m_flWindSpeed" )
    local max_ang    = NetProps.GetPropInt( wind, "m_EnvWindShared.m_iGustDirChange" )
    local wind_ang = QAngle( wind_speed % max_ang, 0, 0 )
    // local wind_ang = QAngle( 0, wind_speed % 360, 0 )
    local prop_ang = prop.GetAbsAngles()

    printl((wind_ang - prop_ang + Vector()).Length())

    // this wind ent is currently freaking out, ignore and delay next think
    if ( ( wind_ang - prop_ang + Vector() ).Length() > 10.0 )
        return 0.1 

    // if ( wind_ang.x > prop_ang.x + 2 )
    //     wind_ang = QAngle( prop_ang.y + 2, 0, 0 )

    // else if ( wind_ang.x < prop_ang.x - 2 )
    //     wind_ang = QAngle( prop_ang.x - 2, 0, 0 )

    printf( "%.8f: %s\n", wind_speed, wind_ang.ToKVString() )
    // prop.SetAbsAngles( wind_ang )
    prop.KeyValueFromString( "angles", wind_ang.ToKVString() )

    return -1
}

AddThinkToEnt( wind, "WindThink" )
IncludeScript( "weather/ents/env_wind.nut" )

for (local wind; wind = Entities.FindByName( wind, "__wind*"); )
    EntFireByHandle( wind, "Kill", null, -1, null, null )

local wind = CScriptEnvWind( "__wind", {

    minwind = 100,
    maxwind = 200,
    mingust = 100,
    maxgust = 200,
    mingustdelay = 0,
    maxgustdelay = 1,
    gustduration = 5,
    gustdirchange = 30

})

local wind_gutterdrip = SpawnEntityFromTable( "info_particle_system", {

    targetname = "__wind_gutterdrip",
    effect_name = "env_rain_gutterdrip",
    origin = Vector( -746.697876, -2470.621338, 750.933960 ),
    start_active = true
})

local wind_ent = wind.self

function WindTestThink() {

    local wind_speed = NetProps.GetPropFloat( wind_ent, "m_EnvWindShared.m_flWindSpeed" )
    local max_ang    = NetProps.GetPropInt( wind_ent, "m_EnvWindShared.m_iGustDirChange" )
    local wind_ang = QAngle( wind_speed % max_ang, 0, 0 )
    // local wind_ang = QAngle( 0, wind_speed % 360, 0 )
    local prop_ang = wind_gutterdrip.GetAbsAngles()
    local diff = (wind_ang - prop_ang + Vector()).Length()

    // if ( diff > 1.0 )
        // printl( diff )

    // wind speed will occasionally spike to some much higher value, then come back down to reality on subsequent ticks.
    // ignore unreasonably large jumps (10hu angle adjustment in a single tick)
    if ( diff > 10.0 )
        return 0.03 

    // prop.SetAbsAngles( wind_ang )
    wind_gutterdrip.KeyValueFromString( "angles", wind_ang.ToKVString() )

    return -1
}

wind.OnWindUpdate( WindTestThink )
wind.OnGustStart( @() printl( "Gust started" ) )
wind.OnGustEnd( @() printl( "Gust ended" ) )
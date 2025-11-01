local ROOT = getroottable()

local function Include( file ) { IncludeScript( "vs_weather/_core/" + file, ROOT ) }

Include( "constants" )
Include( "create_scope" )

___CREATE_SCOPE( "__vs_weather", "VSWeather", "VSWeatherEntity", "VSWeatherThink" )

Include( "generators" )
Include( "../CONFIG.nut" )


VSWeather.AllAreas   <- {}
VSWeather.ValidAreasForParticle <- {}
VSWeather.Events     <- {}
VSWeather.areas_collected <- false

function VSWeather::InitNav() {

    GetAllAreas( AllAreas )

    Assert( AllAreas.len(), "MAP HAS NO NAVMESH! run nav_generate before running this script" )

    GetValidAreas()
}

function VSWeather::GetValidAreas() {

    local function _GetValidAreas( name, area ) {

        // if ( area.GetPlaceName() )
            // return

        local trace = {

            start   = Vector()
            end     = Vector()
            mask    = MASK_SOLID
            hullmin = Vector()
            hullmax = Vector(1, 1, 1)
        }

        local color = [0, 255, 0, 0]

        foreach( particle_name, cfg in VSWeather.CONFIG.WeatherSystems ) {

            trace.start   = area.GetCenter() + Vector( 0, 0, cfg.travel_distance )
            trace.end     = area.GetCenter()
            trace.mask    = MASK_SOLID


            trace.hullmin = trace.start + Vector( -cfg.radius, -cfg.radius, 0 )
            trace.hullmax = trace.start + Vector( cfg.radius, cfg.radius, cfg.travel_distance )

            TraceHull( trace )

            // if a 64hu box can't see the sky from here
            // we probably can't fit any weather effects in this area


            if ( trace.hit && !(trace.surface_flags & SURF_SKY) ) {
                
                DebugDrawText( trace.start, "TRACE START!", false, 10.0 )
                DebugDrawText( trace.end, "TRACE END!", false, 10.0 )
                DebugDrawText( trace.startpos + Vector( 0, 0, 10 ), "HIT START!", false, 10.0 )
                DebugDrawText( trace.endpos + Vector( 0, 0, 10 ), "HIT END!", false, 10.0 )
                color = [255, 0, 0, 0]
            }
            else
                color = [0, 255, 0, 0]

            __DumpScope( 0, trace )
            // if ( trace.surface_flags & SURF_SKY )
            //     color = [0, 0, 255, 20]

            DebugDrawBox( area.GetCenter() - Vector( 0, 0, cfg.travel_distance ), trace.hullmin, trace.hullmax, color[0], color[1], color[2], color[3], 10.0 )

            if ( color[1] != 255 )
                continue

            // secondary line trace loop, hull trace isn't very accurate

            local start = trace.start
            // VSWeather.Generators.NonBlockingLoop( @() trace.start != trace.end, 2, function( i ) {


            //     for ( local j = 0; j < 4; j++ ) {
                    
            //         TraceLine( start, start + Vector( 0, 0, 1 ) * ( j + 1 ), null )
            //         DebugDrawLine( start, start + Vector( 0, 0, 1 ) * ( j + 1 ), color[0], color[1], color[2], false, 10.0 )

            //     }

            //     trace.start *= Vector( 1.0, 1.0, 0.9 )

            // })

            if ( !( particle_name in VSWeather.ValidAreasForParticle ) )
                VSWeather.ValidAreasForParticle[ particle_name ] <- [ area ]
            else
                VSWeather.ValidAreasForParticle[ particle_name ].append( area )

            // area.SetPlaceName( particle_name )

            // muh garbage collection
            // GetNavAreasInRadius( area.GetCenter(), cfg.radius, trace )

            // foreach ( areas in trace )
                // areas.SetPlaceName( particle_name )
        }
    }

    local function _ValidAreasYield( name, area ) { printf( "[STEP1] Valid areas: (%d / %d)\n", VSWeather.ValidAreasForParticle.len(), VSWeather.AllAreas.len() ) }

    local function _ValidAreasComplete( all_areas ) {

        printf( "\n\n[STEP1] VALID AREAS COLLECTED: %d / %d\n\n", VSWeather.ValidAreasForParticle.len(), all_areas.len() );
        VSWeather.areas_collected <- true
    }

    local valid_areas = Generators.DeferredForEach( AllAreas, 20, _GetValidAreas, _ValidAreasYield, _ValidAreasComplete )
    Generators.StartGenerator( valid_areas )
}

function VSWeather::Events::OnGameEvent_player_say( params ) {

    if ( params.text == "auto_weather" ) {

        if ( !VSWeather.areas_collected ) {

            DebugLog.LOG_PRINT( "Cannot run auto-weather yet, waiting for areas to be collected...", "INFO" )
            return
        }
    }
}

VSWeather.InitNav()
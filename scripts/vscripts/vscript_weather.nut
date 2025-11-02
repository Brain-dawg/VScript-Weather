local ROOT = getroottable()

local function Include( file ) { IncludeScript( "vs_weather/_core/" + file, ROOT ) }

Include( "constants" )
Include( "create_scope" )

___CREATE_SCOPE( "__vs_weather", "VSWeather", "VSWeatherEntity", "VSWeatherThink" )

Include( "util" )
Include( "generators" )
Include( "../CONFIG.nut" )

DebugDrawClear()

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

            if ( !( particle_name in VSWeather.ValidAreasForParticle ) )
                VSWeather.ValidAreasForParticle[ particle_name ] <- {}

            trace.start   = area.GetCenter() + Vector( 0, 0, cfg.travel_distance )
            trace.end     = area.GetCenter()

            trace.start.x = trace.start.x.tointeger()
            trace.start.y = trace.start.y.tointeger()
            trace.start.z = trace.start.z.tointeger()

            trace.end.x = trace.end.x.tointeger()
            trace.end.y = trace.end.y.tointeger()
            trace.end.z = trace.end.z.tointeger()

            trace.mask    = MASK_SOLID


            trace.hullmin = trace.start + Vector( -cfg.radius, -cfg.radius, 0 )
            trace.hullmax = trace.start + Vector( cfg.radius, cfg.radius, cfg.travel_distance )

            TraceHull( trace )

            // if a hull trace hits something other than the sky or a model
            // we probably can't fit any weather effects in this area

            color = [0, 255, 0, 0]
            if ( trace.hit && !(trace.surface_flags & SURF_SKY) && trace.surface_name != "**studio**" ) {
                
                // DebugDrawText( trace.start, "TRACE START!", false, 10.0 )
                // DebugDrawText( trace.end, "TRACE END!", false, 10.0 )
                // DebugDrawText( trace.startpos + Vector( 0, 0, 10 ), "HIT START!", false, 10.0 )
                // DebugDrawText( trace.endpos + Vector( 0, 0, 10 ), "HIT END!", false, 10.0 )
                color = [255, 0, 0, 0]
            }

            // __DumpScope( 0, trace )

            // DebugDrawBox( area.GetCenter() - Vector( 0, 0, cfg.travel_distance ), trace.hullmin, trace.hullmax, color[0], color[1], color[2], color[3], 0.1 )

            // printl( color[1] )


            if ( color[1] != 255 )
                return

            VSWeather.ValidAreasForParticle[ particle_name ][ area ] <- { origin_override = Vector() }
        }

    }

    local function _ValidAreasYield( name, area ) { 
    
        foreach ( particle_name, areas in VSWeather.ValidAreasForParticle ) {
            printf( "[%s] Valid areas: (%d / %d)\n", particle_name, areas.len(), VSWeather.AllAreas.len() ) 
        }
    }

    local function _ValidAreasComplete( all_areas ) {

        // secondary line trace loop, hull trace isn't very accurate
        // We want to step downward in Z, repeating the four cardinal "spoke" traces at each Z step, until the trace_start reaches the trace_end (ground). 
        // At each step, cast four traces in X+/-, Y+/- from current trace_start, then step trace_start.z down for next iteration.

        local directions = [

            Vector(1, 0, 0),   // +X (Forward)
            Vector(-1, 0, 0),  // -X (Backward)
            Vector(0, 1, 0),   // +Y (Right)
            Vector(0, -1, 0)   // -Y (Left)
        ];

        local z_step = 64.0; // Step size for moving downward in Z, adjust as needed

        local color = [0, 255, 255, 0]

        foreach( particle_name, areas in VSWeather.ValidAreasForParticle ) {
            
            local cfg = VSWeather.CONFIG.WeatherSystems[ particle_name ]

            VSWeather.Generators.StartGenerator( VSWeather.Generators.DeferredForEach( areas, 15, function( area, failed_first ) {

                local trace_start   = area.GetCenter() + Vector( 0, 0, cfg.travel_distance )
                local trace_end     = area.GetCenter()
                local tracing = true

                local trace = {

                    start   = trace_start
                    end     = trace_end
                    mask    = MASK_SOLID
                    startsolid = false
                }


                // For each Z slice, cast four traces outwards from center to edge of the radius in X+/- and Y+/-
                VSWeather.Generators.StartGenerator( VSWeather.Generators.NonBlockingLoop(  @() tracing, 1024, function( _ ) {

                    local spoke_end, result
                    foreach( dir in directions ) {

                        spoke_end = Vector( trace_start.x + dir.x * cfg.radius, trace_start.y + dir.y * cfg.radius, trace_start.z )
                        result = TraceLine( spoke_end, trace_start, null )
                        // printl(trace_start + " -> " + spoke_end + " -> " + result);
                            
                        color = [0, 255, 255, 0]

                        if ( area in VSWeather.ValidAreasForParticle[ particle_name ] ) {

                            // we failed a trace
                            if ( result != 1.0 ) {
                                
                                // we failed our first trace
                                // check if subsequent traces enter playable space
                                // if they do, this particle will clip through a ceiling/wall or something, delete it
                                // store the trace offset and look for subsequent traces that enter playable space
                                if ( !VSWeather.ValidAreasForParticle[ particle_name ][ area ].origin_override.LengthSqr() ) {

                                    color = [ 0, 0, 255, 0 ]
                                    VSWeather.ValidAreasForParticle[ particle_name ][ area ].origin_override = trace_start
                                    // color = [0, 255, 0, 0]
                                }

                                // we failed our second trace, stop tracing
                                else {

                                    trace.start = spoke_end
                                    trace.end   = spoke_end
                                    TraceLineEx( trace )

                                    // ignore models (rocks and stuff)
                                    if ( trace.surface_name == "**studio**" ) 
                                        color = [255, 255, 0, 0]
                                    else 
                                        color = [255, 0, 0, 0]

                                    tracing = false
                                }
                            }
                        }

                        DebugDrawLine( trace_start, spoke_end, color[0], color[1], color[2], false, !color[0] && color[1] == 255 && color[2] == 255 ? 0.5 : 15.0 )
                    }

                    // Step the start position downward in Z for next ring
                    trace_start.z = trace_start.z - z_step

                    if ( trace_start.z < trace_end.z && area in VSWeather.ValidAreasForParticle[ particle_name ] )
                        delete VSWeather.ValidAreasForParticle[ particle_name ][ area ], tracing = false

                }, _ValidAreasYield( particle_name, area ), @() tracing = false))

            }, null, function( _ ) {

                    color = [0, 255, 255, 0]

                    // local hullmin, hullmax
                    // DebugDrawClear()
                    // foreach( area, valid in VSWeather.ValidAreasForParticle[ particle_name ] ) {
                    // }

                    local areas_len = VSWeather.ValidAreasForParticle[ particle_name ].len()

                    VSWeather.Generators.StartGenerator( VSWeather.Generators.NonBlockingLoop( @() areas_len > VSWeather.CONFIG.MAX_WEATHER_SYSTEMS, 350, function( _ ) {

                        local area = VSWeather.ValidAreasForParticle[ particle_name ].keys()[RandomInt( 0, VSWeather.ValidAreasForParticle[ particle_name ].len() - 1 )]

                        if ( area in VSWeather.ValidAreasForParticle[ particle_name ] )
                            delete VSWeather.ValidAreasForParticle[ particle_name ][ area ]

                        areas_len--
                        _ValidAreasYield( particle_name, area )

                    }, null, function() {

                        printf( "\n\n[%s] VALID AREAS COLLECTED: %d / %d\n\n", particle_name, areas.len(), all_areas.len() )

                        color = [0, 255, 255, 0]

                        foreach( area, data in areas ) {

                            local offset = data.origin_override.LengthSqr() ? data.origin_override : area.GetCenter()

                            color = [ RandomInt( 100, 255 ), RandomInt( 150, 255 ), RandomInt( 200, 255 ) ]

                            foreach ( i, vector in [ Vector(), Vector( cfg.radius, cfg.radius, 0 ), Vector( -cfg.radius, cfg.radius, 0 ), Vector( cfg.radius, -cfg.radius, 0 ), Vector( -cfg.radius, -cfg.radius, 0 ) ] )  {
                                DebugDrawLine( offset + vector, offset + vector + Vector( 0, 0, cfg.travel_distance ), color[0], color[1], color[2], false, 90.0 )
                            }

                            SpawnEntityFromTable( "info_particle_system", {

                                targetname = "__vs_weather_particle_" + particle_name + "_" + area.GetID()
                                origin = offset + Vector( 0, 0, cfg.travel_distance )
                                angles = QAngle()
                                effect_name = particle_name
                                start_active = true
                            })
                            DebugDrawText( offset + Vector( 0, 0, cfg.travel_distance ), "__vs_weather_particle_" + particle_name + "_" + area.GetID(), false, 90.0 )
                        }

                        Generators.active_generators.clear()

                    } ) )

                } ) )

        }
        VSWeather.areas_collected <- true
    }

    local valid_areas = Generators.DeferredForEach( AllAreas, 150, _GetValidAreas, _ValidAreasYield, _ValidAreasComplete )
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
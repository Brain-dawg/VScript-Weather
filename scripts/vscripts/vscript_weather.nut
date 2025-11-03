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

    // first pass, basic hull trace to see if we can fit a particle system here
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

        local color_valid  = [   0, 180,  20, 50  ]
        local color_small  = [   0,  20, 180, 50  ]
        local color_edge   = [   0, 180, 180, 50  ]
        local color_warn   = [ 180, 180,  20,  50 ]
        local color_danger = [ 180,   0,  20,  50 ]

        local color = color_valid

        local center = area.GetCenter()
        foreach( particle_name, cfg in VSWeather.CONFIG.WeatherSystems ) {

            if ( !( particle_name in VSWeather.ValidAreasForParticle ) )
                VSWeather.ValidAreasForParticle[ particle_name ] <- {}

            // ignore small areas
            if ( area.GetSizeX() < 25 )
                color = color_small

            else if ( area.GetSizeY() < 25 )
                color = color_small
                
            if ( color == color_small )
                return

            trace.start   = Vector( center.x, center.y, center.z + cfg.travel_distance )
            trace.end     = center

            trace.mask    = MASK_SOLID

            trace.hullmin = trace.start + Vector( -64, -64, 0 )
            trace.hullmax = trace.start + Vector( 64, 64, cfg.travel_distance )

            TraceHull( trace )

            // if a hull trace hits something other than the sky or a model
            // we probably can't fit any weather effects in this area

            if ( trace.hit && !(trace.surface_flags & SURF_SKY) && trace.surface_name[0] != '*' ) {

                printl( trace.surface_name )
                
                // DebugDrawText( trace.start, "TRACE START!", false, 10.0 )
                // DebugDrawText( trace.end, "TRACE END!", false, 10.0 )
                // DebugDrawText( trace.startpos + Vector( 0, 0, 10 ), "HIT START!", false, 10.0 )
                // DebugDrawText( trace.endpos + Vector( 0, 0, 10 ), "HIT END!", false, 10.0 )
                color = color_warn
            }

            // __DumpScope( 0, trace )

            // DebugDrawBox( area.GetCenter() - Vector( 0, 0, cfg.travel_distance ), trace.hullmin, trace.hullmax, color[0], color[1], color[2], color[3], color == color_valid ? 1.0 : 15.0 )

            // printl( color[1] )


            if ( color != color_valid )
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

        local z_step = 16.0; // Step size for moving downward in Z, adjust as needed

        local color_valid  = [   0, 180,  20, 50  ]
        local color_small  = [   0,  20, 180, 50  ]
        local color_edge   = [   0, 180, 180, 50  ]
        local color_warn   = [ 180, 180,  20,  50 ]
        local color_danger = [ 180,   0,  20,  50 ]

        local color = color_valid

        local nearby_areas = {}

        local trace = {

            start      = Vector()
            end        = Vector()
            mask       = MASK_SOLID
            startsolid = false
        }

        local _errmsg = @( particle_name, key ) format( "KV ERROR [%s] '%s' is automatically handled by the script, do not set it manually", particle_name, key )

        foreach( particle_name, areas in VSWeather.ValidAreasForParticle ) {
            
            local cfg           = VSWeather.CONFIG.WeatherSystems[ particle_name ]
            local entity_kvs    = "keyvalues" in cfg ? cfg.keyvalues : {}

            Assert( !( "origin" in entity_kvs ), _errmsg( particle_name, "origin" ) )
            Assert( !( "effect_name" in entity_kvs ), _errmsg( particle_name, "effect_name" ) )

            local particle_info = VSWeather.ValidAreasForParticle[ particle_name ]

            local trace_start, trace_end

            VSWeather.Generators.StartGenerator( VSWeather.Generators.DeferredForEach( areas, 15, function( area, failed_first ) {

                local tracing = true
                local center  = area.GetCenter()
                trace_start   = Vector( center.x, center.y, center.z + cfg.travel_distance )
                trace_end     = center
                particle_info = VSWeather.ValidAreasForParticle[ particle_name ]

                VSWeather.Generators.StartGenerator( VSWeather.Generators.NonBlockingLoop(  @() tracing, 1023, function( _ ) {

                    if ( !(area in particle_info) )
                        return

                    local spoke_end, result1, result2
                    
                    // For each Z slice, cast four traces outwards from center to edge of the radius in X+/- and Y+/-
                    foreach( dir in directions ) {

                        spoke_end = Vector( trace_start.x + dir.x * cfg.radius, trace_start.y + dir.y * cfg.radius, trace_start.z )
                        result1 = TraceLine( trace_start, spoke_end, null )
                        result2 = TraceLine( spoke_end, trace_start, null )

                        printl( "TRACING: " + trace_start + " <-> " + spoke_end + " -> " + result1 + " <-> " + result2);
                            
                        color = color_valid

                        // we failed a trace
                        if ( result1 != 1.0 || result2 != 1.0 ) {
                            
                            // we failed our first trace
                            // check if subsequent traces enter playable space
                            // if they do, this particle will clip through a ceiling/wall or something, delete it
                            if ( !particle_info[ area ].origin_override.LengthSqr() ) {

                                color = color_warn
                                // use this trace position to override the particle system origin, then look for another trace that enters playable space
                                particle_info[ area ].origin_override = Vector( trace_start.x, trace_start.y, trace_start.z + z_step )
                                // color = [0, 255, 0, 0]
                            }
                        }

                        // we failed our second trace
                        else if ( particle_info[ area ].origin_override.LengthSqr() ) {

                            trace.start = spoke_end
                            trace.end   = spoke_end
                            TraceLineEx( trace )

                            // ignore models (rocks and stuff)
                            if ( trace.surface_name[0] != '*' ) 
                                color = color_edge
                            else 
                                color = color_danger

                            tracing = false
                        }

                        DebugDrawLine( trace_start, spoke_end, color[0], color[1], color[2], false, color == color_valid ? 10.0 : 15.0 )

                    }

                    // Step the start position downward in Z for next ring
                    trace_start.z = trace_start.z - z_step

                    if ( ( color != color_valid || trace_start.z < trace_end.z ) && area in particle_info )
                        delete particle_info[ area ], tracing = false

                }, _ValidAreasYield( particle_name, area ), @() tracing = false ) )

            }, null, function( _ ) {

                // local hullmin, hullmax
                // DebugDrawClear()
                // foreach( area, valid in VSWeather.ValidAreasForParticle[ particle_name ] ) {
                // }

                local areas_len = particle_info.len()

                if ( areas_len > VSWeather.CONFIG.MAX_WEATHER_SYSTEMS )
                    areas_len = VSWeather.CONFIG.MAX_WEATHER_SYSTEMS

                // local template = SpawnEntityFromTable( "point_script_template", { vscripts = " " } )
                local nearby_particle

                // local template_scope = template.GetScriptScope()
                // template_scope.ents <- []
                // template_scope.__EntityMakerResult <- { entities = template_scope.ents }.setdelegate({ function _newslot( _, value ) { entities.append( value ) } })

                local kvs = clone entity_kvs

                VSWeather.Generators.StartGenerator( VSWeather.Generators.NonBlockingLoop( @() areas_len, 31, function( _ ) {
                    
                    areas_len = particle_info.len()

                    if ( !areas_len )
                        return

                    local area = particle_info.keys()[RandomInt( 0, particle_info.len() - 1 )]

                    local origin_pre_offset = particle_info[ area ].origin_override

                    if ( !origin_pre_offset.LengthSqr() )
                        origin_pre_offset = area.GetCenter()

                    if ( !("targetname" in entity_kvs) )
                        kvs.targetname <- "__vs_weather_" + particle_name + "_" + area.GetID()
                    else
                        kvs.targetname = entity_kvs.targetname + "_" + area.GetID()

                    if ( !("vscripts" in kvs) )
                        kvs.vscripts <- " "

                    // foreach ( i, vector in [ Vector(), Vector( cfg.radius, cfg.radius, 0 ), Vector( -cfg.radius, cfg.radius, 0 ), Vector( cfg.radius, -cfg.radius, 0 ), Vector( -cfg.radius, -cfg.radius, 0 ) ] )  {
                    //     DebugDrawLine( offset + vector, offset + vector + Vector( 0, 0, cfg.travel_distance ), color[0], color[1], color[2], false, 30.0 )
                    // }

                    local final_origin = Vector( origin_pre_offset.x, origin_pre_offset.y, origin_pre_offset.z + cfg.travel_distance )

                    kvs.origin      <- final_origin
                    kvs.effect_name <- particle_name

                    // printl( nearby_particle )
                    // printl( "areas_len: " + areas_len + " : " + color[0] + " " + color[1] + " " + color[2] )
                    area.DebugDrawFilled( color[0], color[1], color[2], 255, 0.1, true, 0.0 )

                    // printf( "[%s] Trying spawn at %s (%d left)\n", particle_name, kvs.origin.ToKVString(), areas_len )
                    if ( nearby_particle = FindByClassnameNearest( "info_particle_system", kvs.origin, cfg.radius ) )
                        if ( GetPropString( nearby_particle, "m_iszEffectName" ) == particle_name )
                            return delete particle_info[ area ], color = color_danger

                    color = color_valid
                    // template.AddTemplate( "info_particle_system", kvs )
                    local ent = SpawnEntityFromTable( "info_particle_system", kvs )

                    if ( ent.GetOrigin() != final_origin )
                        ent.SetAbsOrigin( final_origin )

                    // DebugDrawText( origin_pre_offset + Vector( 0, 0, cfg.travel_distance ), kvs.targetname, false, 30.0 )
                    DebugDrawBox( final_origin, Vector( -10, -10, -10 ), Vector( 10, 10, 10 ), color_small[0], color_small[1], color_small[2], 0, 30.0 )
                    // DebugDrawLine( origin_pre_offset, final_origin, color_small[0], color_small[1], color_small[2], false, 30.0 )

                    // _ValidAreasYield( particle_name, area )
                    // areas_len--
                    delete particle_info[ area ]

                }, function( _ ) {
                    
                    // split particle spawns into separate point_script_templates
                    // template.AcceptInput( "ForceSpawn", null, null, null )
                    // EntFireByHandle( template, "Kill", null, -1, null, null )
                    // template = SpawnEntityFromTable( "point_script_template", { vscripts = " " } )

                    // template_scope = template.GetScriptScope()
                    // template_scope.ents <- []
                    // template_scope.__EntityMakerResult <- { entities = template_scope.ents }.setdelegate({ function _newslot( _, value ) { entities.append( value ) } })

                }, function() {

                    // template.AcceptInput( "ForceSpawn", null, null, null )
                    // EntFireByHandle( template, "Kill", null, -1, null, null )
                    printf( "\n\n[%s] DONE!\n\n", particle_name )

                    Generators.active_generators.clear()

                } ) )
            } ) )
        }
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
local ROOT = getroottable()

local function Include( file ) { IncludeScript( "vs_weather/_core/" + file, ROOT ) }

Include( "constants" )
Include( "create_scope" )

// dummy entity to scope everything to
___CREATE_SCOPE( "__vs_weather", "VSWeather", "VSWeatherEntity", "VSWeatherThink" )

Include( "debuglog")
Include( "util" )
Include( "generators" )
Include( "maplogic" )
Include( "navutils" )
Include( "../CONFIG.nut" )

DebugDrawClear()
// VSWeather.AreasToTrace <- []
// VSWeather.TraceState <- {}
VSWeather.AllAreas   <- {}
VSWeather.particle_count <- 0
VSWeather.weather_complete <- false
VSWeather.weather_editing  <- false
VSWeather.ValidAreasForParticle <- {}
VSWeather.TraceJobs    <- []
VSWeather.FailedJobs   <- []

function VSWeather::InitNav() {

    GetAllAreas( AllAreas )

    Assert( AllAreas.len(), "MAP HAS NO NAVMESH! type '.wnav' to create one" )

    // Initialize ValidAreasForParticle for each particle type
    foreach( particle_name, cfg in CONFIG.WeatherSystems )
        ValidAreasForParticle[ particle_name ] <- {}

    // TODO: is there any harm in just always checking for these?
    local important_ents = ( MapLogic.GetSpectatorCameras().keys() ).extend( MapLogic.GetCaptureAreas().keys() )
    switch ( MapLogic.GetGamemode() ) {

        case "PL":
        case "PLR":
            important_ents.extend( MapLogic.GetPayloadTracks().keys() )
        break

        case "MVM":
            important_ents.extend( MapLogic.GetBombPathMarkers().keys() )
        break
        // case "CP":
        // case "SD":
        // case "KOTH":
        // case "Arena":
        // case "CTF/CP":
        //     important_ents.extend( MapLogic.GetCaptureAreas().keys() )
        //     break
    }

    // ensure important map entities get iterated over first.
    AllAreas = important_ents.extend( AllAreas.values() )
}

// Initialize spoke trace data for each area
function VSWeather::SetupAreaParticleInfo( i, area ) {

    // NOTE: this array is a mix of CBaseEntity derived ents AND CNavAreas.
    // conveniently, GetCenter() is available on both.
    // DO NOT ASSUME THIS IS ONLY NAV AREAS!

    local area_center = area.GetCenter()

    local ignore = area instanceof CBaseEntity ? area : GetListenServerHost()
    local trace_full = {

        start   = area_center
        end     = area_center + Vector( 0, 0, INT_MAX )
        ignore  = ignore
        allsolid   = false
        startsolid = false
    }

    foreach( particle_name, particle_info in ValidAreasForParticle ) {

        if ( !(area in particle_info) ) {

            // make sure the sky is visible
            TraceLineEx( trace_full )

            if ( trace_full.surface_flags & SURF_SKY ) {

                particle_info[ area ] <- {

                    origin_override = Vector(),
                    // offset trace start position down by the fraction of the travel distance that is in the skybox
                    start_in_skybox = TraceLine( area_center, area_center + Vector( 0, 0, CONFIG.WeatherSystems[ particle_name ].travel_distance ), ignore )
                }
            }
        }
    }
}

function VSWeather::ValidAreasYield( i, area ) {

    foreach ( particle_name, particle_info in ValidAreasForParticle )
        DebugLog.LOG_PRINT( format( "[%s] Valid areas: (%d / %d)", particle_name, particle_info.len(), AllAreas.len() ), "DEBUG" )
}

// Run the spoke trace loop using NonBlockingLoop
function VSWeather::RunSpokeTraceLoop( oncomplete ) {

    DebugLog.LOG_PRINT( "Starting trace loop (prepare for lag)", "INFO" )

    // Collect all areas that need tracing and create trace jobs

    // Define colors for debug drawing
    local color_valid = [0, 255, 0]    // green
    local color_warn = [255, 255, 0]   // yellow
    local color_small = [0, 128, 255]  // blue
    local color_edge = [255, 128, 0]   // orange
    local color_danger = [255, 0, 0]   // red

    // local trace_job = {

    //     area_name     = null
    //     area          = null
    //     particle_name = null
    //     particle_info = null
    //     completed     = false
    //     trace_failed  = false
    //     cfg           = null
    //     trace_start   = null
    //     trace_end     = null
    //     hit_sky       = null // start it null and set to true or false so we don't need to trace this again
        
    //     // Define trace directions (cardinal + ordinal directions)
    //     trace_dirs = [

    //         // cardinal
    //         [ Vector(1, 0, 0),         { status = color_valid, last_result = 2.0 } ], // +X right
    //         [ Vector(-1, 0, 0),        { status = color_valid, last_result = 2.0 } ], // -X left
    //         [ Vector(0, 1, 0),         { status = color_valid, last_result = 2.0 } ], // +Y up
    //         [ Vector(0, -1, 0),        { status = color_valid, last_result = 2.0 } ], // -Y down

    //         // ordinal
    //         [ Vector(0.5, 0.5, 0),     { status = color_valid, last_result = 2.0 } ], // +X +Y
    //         [ Vector(-0.5, -0.5, 0),   { status = color_valid, last_result = 2.0 } ], // -X -Y
    //         [ Vector(-0.5, 0.5, 0),    { status = color_valid, last_result = 2.0 } ], // -X +Y
    //         [ Vector(0.5, -0.5, 0),    { status = color_valid, last_result = 2.0 } ],  // +X -Y

    //         // sub-ordinal
    //         [ Vector(0.25, 0.25, 0),   { status = color_valid, last_result = 2.0 } ],   // +X +Y
    //         [ Vector(-0.25, -0.25, 0), { status = color_valid, last_result = 2.0 } ], // -X -Y
    //         [ Vector(-0.25, 0.25, 0),  { status = color_valid, last_result = 2.0 } ],  // -X +Y
    //         [ Vector(0.25, -0.25, 0),  { status = color_valid, last_result = 2.0 } ]   // +X -Y
    //     ]
    // }

    foreach( particle_name, particle_info in ValidAreasForParticle ) {

        local cfg = CONFIG.WeatherSystems[ particle_name ]

        foreach( area, info in particle_info ) {

            // trace_job.cfg           = CONFIG.WeatherSystems[ particle_name ]
            // trace_job.area          = area
            // trace_job.area_name     = area.GetID()
            // trace_job.trace_end     = area.GetCenter()
            // trace_job.trace_start   = area.GetCenter() + Vector( 0, 0, trace_job.cfg.travel_distance )
            // trace_job.particle_name = particle_name
            // trace_job.particle_info = particle_info

            // TraceJobs.append( trace_job )

            TraceJobs.append({

                area_name     = area instanceof CBaseEntity ? GetPropInt( area, "m_iHammerID" ) : area.GetID()
                area          = area
                particle_name = particle_name
                particle_info = particle_info
                completed     = false
                trace_failed  = false
                cfg           = cfg
                trace_start   = area.GetCenter() + Vector( 0, 0, cfg.travel_distance * particle_info[ area ].start_in_skybox )
                trace_end     = area.GetCenter()
                hit_sky       = null // start it null and set to true or false so we don't need to trace this again
                
                // Define trace directions (cardinal + ordinal directions)
                trace_dirs = [

                    // cardinal
                    [ Vector(1, 0, 0),         { status = color_valid, last_result = 2.0 } ], // +X right
                    [ Vector(-1, 0, 0),        { status = color_valid, last_result = 2.0 } ], // -X left
                    [ Vector(0, 1, 0),         { status = color_valid, last_result = 2.0 } ], // +Y up
                    [ Vector(0, -1, 0),        { status = color_valid, last_result = 2.0 } ], // -Y down

                    // ordinal
                    [ Vector(0.5, 0.5, 0),     { status = color_valid, last_result = 2.0 } ], // +X +Y
                    [ Vector(-0.5, -0.5, 0),   { status = color_valid, last_result = 2.0 } ], // -X -Y
                    [ Vector(-0.5, 0.5, 0),    { status = color_valid, last_result = 2.0 } ], // -X +Y
                    [ Vector(0.5, -0.5, 0),    { status = color_valid, last_result = 2.0 } ],  // +X -Y

                    // sub-ordinal
                    [ Vector(0.25, 0.25, 0),   { status = color_valid, last_result = 2.0 } ],   // +X +Y
                    [ Vector(-0.25, -0.25, 0), { status = color_valid, last_result = 2.0 } ], // -X -Y
                    [ Vector(-0.25, 0.25, 0),  { status = color_valid, last_result = 2.0 } ],  // -X +Y
                    [ Vector(0.25, -0.25, 0),  { status = color_valid, last_result = 2.0 } ]   // +X -Y
                ]
            })
        }
    }

    local current_job_index = 0

    local z_step = 2

    local function should_continue() {

        local result = current_job_index in TraceJobs
        if ( !result )
            DebugLog.LOG_PRINT( "Done tracing! Spawning particles...", "INFO" )
        return result
    }

    local function trace_step() {

        // printl( "Tracing job " + current_job_index + " of " + trace_jobs.len() )

        if ( !(current_job_index in TraceJobs) )
            return

        local job = TraceJobs[current_job_index]

        if ( job.completed ) {

            if ( job.area in ValidAreasForParticle[job.particle_name] )
                delete ValidAreasForParticle[job.particle_name][job.area]

            return current_job_index++
        }

        // printf( "Tracing job %d/%d: area %d, particle %s\n", current_job_index + 1, trace_jobs.len(), job.area_name, job.particle_name )

        // Perform one Z-level of tracing
        if ( job.trace_start.z > job.trace_end.z ) {

            foreach( dir_status in job.trace_dirs ) {

                // __DumpScope(0, dir_status)

                local dir  = dir_status[0]
                local info = dir_status[1]

                if ( job.completed )
                    break

                local spoke_end = Vector( job.trace_start.x + dir.x * job.cfg.radius, job.trace_start.y + dir.y * job.cfg.radius, job.trace_start.z )
                local trace_result = TraceLine( job.trace_start, spoke_end, GetListenServerHost() ) + TraceLine( spoke_end, job.trace_start, GetListenServerHost() )

                // this trace hit a surface
                // traces that progressively get smaller usually mean we're hitting a rock or something on the ground
                if ( trace_result < info.last_result ) {

                    // if (result1 + result2 >= 1.75) {

                        DebugLog.LOG_PRINT( format( "TRACING %s: %s <-> %s -> %0.2f", ""+job.area, job.trace_start.ToKVString(), spoke_end.ToKVString(), trace_result ), "DEBUG" );
                        // status = color_small
                    // }

                    if ( info.status != color_warn ) {

                        // use this trace position to override the particle system origin, then look for another trace that enters playable space
                        job.particle_info[ job.area ].origin_override = Vector( job.trace_start.x, job.trace_start.y, job.trace_start.z + z_step )
                        info.status = color_warn
                    }
                    info.last_result = trace_result
                }

                // ... but a subsequent trace did not
                // we might've just punched through a ceiling

                // check if we hit a trace that's larger than the last one
                // if so, we've probably entered playable/visible space.
                // TODO: this alone causes false-negatives, leaving "dead spots" with no rain
                // better than raining inside though, right?
                else if ( info.status != color_valid && trace_result > info.last_result * CONFIG.TRACE_FORGIVENESS ) {

                    if ( (CONFIG.IGNORE_DISPLACEMENTS || CONFIG.IGNORE_PROPS) ) {

                        local trace_full = {

                            start   = job.trace_start
                            end     = spoke_end
                            ignore  = GetListenServerHost()
                            allsolid   = false
                            startsolid = false
                        }

                        TraceLineEx( trace_full )

                        if ( trace_full.surface_name == "**displacement**" && CONFIG.IGNORE_DISPLACEMENTS )
                            continue

                        else if ( ( trace_full.surface_name == "**studiomdl**" || trace_full.surface_name == "**empty**" ) && CONFIG.IGNORE_PROPS )
                            continue
                    }

                    info.status = color_danger
                    job.completed = true
                    job.trace_failed = true
                    FailedJobs.append( job )
                }
        
                // set TRACE_FUNCS very low ( < 12 ) to avoid crashing before uncommenting this
                // use host_timescale to compensate for the slowdown

                // DebugDrawLine( job.trace_start, spoke_end, info.status[0], info.status[1], info.status[2], false, info.status == color_valid ? 0.5 : 2.0 )
            }

            // Step the start position down for next trace
            job.trace_start.z -= z_step

            // If we've finished this Z level, mark as completed
            if ( job.trace_start.z <= job.trace_end.z ) {
                job.completed = true
            }
        }
        else {
            job.completed = true
        }

        // If job is completed, handle cleanup
        if ( job.completed ) {

            // Remove areas that failed validation
            // printl( job.trace_failed )
            if ( job.trace_failed )
                delete ValidAreasForParticle[job.particle_name][job.area]

            current_job_index++
        }
    }

    return Generators.NonBlockingLoop( should_continue, CONFIG.ITERS_PER_FRAME.TRACE_FUNCS, trace_step, null, oncomplete )
}

// VSWeather.Generators.NonBlockingLoop(  @() tracing, 1023, _SpokeTrace, null, @() tracing = false )

function VSWeather::InitializeSpawnParticles() {

    // Collect all valid areas from all particle types
    local all_valid_areas = {}

    foreach( particle_name, particle_info in ValidAreasForParticle )
        foreach( area, info in particle_info )
            all_valid_areas[ area ] <- { particle_name = particle_name, info = info }

    return all_valid_areas
}

function VSWeather::SpawnParticles( area, info ) {

    local particle_name = info.particle_name
    local particle_info = info.info

    // printl( "Spawning particles for " + particle_name + " -> " + particle_info.len() + " areas" )

    // Define colors for debug drawing
    local color_valid = [0, 255, 0]    // green
    local color_danger = [255, 0, 0]   // red
    local color_small = [0, 128, 255]  // blue

    local cfg = CONFIG.WeatherSystems[ particle_name ]
    local kvs = "keyvalues" in cfg ? clone cfg.keyvalues : {}

    local _errmsg = function( name, key ) { return "Particle " + name + " keyvalue '" + key + "' is set automatically.  Do not set it manually." }

    Assert( !( "origin" in kvs ), _errmsg( particle_name, "origin" ) )
    Assert( !( "effect_name" in kvs ), _errmsg( particle_name, "effect_name" ) )

    local origin_pre_offset = particle_info.origin_override
    local area_id = area instanceof CBaseEntity ? GetPropInt( area, "m_iHammerID" ) : area.GetID()

    if ( !origin_pre_offset.LengthSqr() )
        origin_pre_offset = area.GetCenter()

    if ( !("targetname" in kvs) )
        kvs.targetname <- "__vs_weather_" + particle_name + "_" + area_id
    else
        kvs.targetname = kvs.targetname + "_" + area_id

    // "vscripts" kv w/ invalid filename will still set up the script scope on spawn
    // without needing to call .ValidateScriptScope() after
    // cannot be an empty string or null, just use a space
    if ( !("vscripts" in kvs) )
        kvs.vscripts <- " "

    local final_origin = Vector( origin_pre_offset.x, origin_pre_offset.y, origin_pre_offset.z + cfg.travel_distance )

    kvs.origin      <- final_origin
    kvs.effect_name <- particle_name

    // area.DebugDrawFilled( color_valid[0], color_valid[1], color_valid[2], 255, 0.1, true, 0.0 )

    // Check for nearby particles to avoid duplicates
    local nearby_particle = FindByClassnameNearest( "info_particle_system", kvs.origin, cfg.radius )
    if ( nearby_particle && GetPropString( nearby_particle, "m_iszEffectName" ) == particle_name ) {
        DebugLog.LOG_PRINT( "Skipping duplicate particle at " + kvs.origin.ToKVString(), "DEBUG" )
        return
    }

    if ( particle_count >= CONFIG.MAX_WEATHER_SYSTEMS )
        return

    local ent = SpawnEntityFromTable( "info_particle_system", kvs )

    if ( ent.GetOrigin() != final_origin )
        ent.SetAbsOrigin( final_origin )

    DebugDrawBox( final_origin, Vector( -10, -10, -10 ), Vector( 10, 10, 10 ), color_small[0], color_small[1], color_small[2], 0, 60.0 )
    DebugDrawLine( origin_pre_offset, final_origin, color_small[0], color_small[1], color_small[2], false, 60.0 )

    DebugLog.LOG_PRINT( "Spawned particle system: " + particle_name + " at " + final_origin.ToKVString() + "(Count: " + particle_count + ")", "DEBUG" )

    particle_count++
}

// Start the generator chain
function VSWeather::Start() {

    local i = 0
    for ( local ent = Entities.First(); ent; ent = Entities.Next( ent ) )
        i++

    if ( i + CONFIG.MAX_WEATHER_SYSTEMS > MAX_EDICTS )
        return DebugLog.LOG_PRINT( format( "Not enough edicts to spawn particles.  %d + %d > %d", i, CONFIG.MAX_WEATHER_SYSTEMS, MAX_EDICTS ), "ERROR" )

    weather_complete = false

    Generators.GeneratorChain([

        [

            function(oncomplete) {

                return Generators.DeferredForEach(
                    AllAreas,
                    CONFIG.ITERS_PER_FRAME.NAV_AREAS,
                    SetupAreaParticleInfo, // initialize spoke trace for each area
                    ValidAreasYield, // yields for each iters_per_frame
                    oncomplete       // completion callback (REQUIRED for chaining)
                )
            }
        ],
        [

            function(oncomplete) {

                return RunSpokeTraceLoop( oncomplete )
            },
            @() Generators.StartGenerator( Generators.DeferredForEach( InitializeSpawnParticles(), CONFIG.ITERS_PER_FRAME.SPAWN_PARTICLES, SpawnParticles, null, @(_) weather_complete = true ) )
        ]
    ])
}

// chat commands are all prefixed with ".w"
// e.g. "edit" is ".wedit"
VSWeather.ChatCommands <- {

    function trace( _ ) { Start() }
    function start( _ ) { Start() }

    function edit( params ) {

    }

    function save( params ) {

    }

    function nav( params ) { NavUtils.CreateNav() }

    function failed( params ) {

        DebugDrawClear()
        foreach( job in FailedJobs ) {

            DebugLog.LOG_PRINT( "Failed job: " + job.area_name + " -> " + job.particle_name + " at " + job.trace_start.ToKVString(), "INFO" )

            local radius = CONFIG.WeatherSystems[ job.particle_name ].radius
            DebugDrawBox( job.trace_end + Vector( 0, 0, CONFIG.WeatherSystems[ job.particle_name ].travel_distance * 0.5 ), Vector( -radius, -radius, -radius ), Vector( radius, radius, radius ), 255, 0, 0, 0, 60.0 )
        }
    }
}.setdelegate( VSWeather )

if ( "Events" in VSWeather )
    delete VSWeather.Events

VSWeather.Events <- {}.setdelegate( VSWeather )

function VSWeather::Events::OnGameEvent_player_say( params ) {

    local text = params.text

    if ( text[0] != '.' || !(1 in text) || text[1] != 'w' )
        return

    local cmd = text.slice( 2 )

    if ( !(cmd in ChatCommands) ) {

        DebugLog.LOG_PRINT( "Unknown command: " + text, "INFO" )
        return
    }

    // if ( !weather_complete ) {

    //     DebugLog.LOG_PRINT( "Weather is not complete yet.", "INFO" )
    //     return
    // }

    ChatCommands[ cmd ]( params )
}
__CollectGameEventCallbacks( VSWeather.Events )

VSWeather.InitNav()
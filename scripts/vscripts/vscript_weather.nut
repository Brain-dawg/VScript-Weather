local ROOT = getroottable()

local function Include( file ) { IncludeScript( "vs_weather/_core/" + file, ROOT ) }

Include( "constants" )
Include( "create_scope" )

// dummy entity to scope everything to
___CREATE_SCOPE( "__vs_weather", "VSWeather", "VSWeatherEntity", "VSWeatherThink" )

Include( "debuglog")
Include( "util" )
Include( "generators" )
Include( "../CONFIG.nut" )

DebugDrawClear()
// VSWeather.AreasToTrace <- []
// VSWeather.TraceState <- {}
VSWeather.AllAreas   <- {}
VSWeather.particle_count <- 0
VSWeather.weather_complete <- false
VSWeather.weather_editing  <- false
VSWeather.ValidAreasForParticle <- {}
VSWeather.TraceJobs <- []
// VSWeather.PendingTraceJobs <- []

function VSWeather::InitNav() {

    GetAllAreas( AllAreas )

    Assert( AllAreas.len(), "MAP HAS NO NAVMESH! run nav_generate before running this script" )

    // Initialize ValidAreasForParticle for each particle type
    foreach( particle_name, cfg in CONFIG.WeatherSystems )
        ValidAreasForParticle[ particle_name ] <- {}

    // local newareas = array( areas_len )
    // local rnd = RandomInt( 0, areas_len - 1 )

    // shuffle the areas
    // probably a better way to do this
    // foreach ( area in AllAreas ) {

    //     while ( newareas[ rnd ] ) {

    //         rnd = RandomInt( 0, areas_len - 1 )
    //     }

    //     newareas[ rnd ] = area
    // }

    // AllAreas = newareas
}

// Initialize spoke trace data for each area
function VSWeather::InitNavParticleInfo( i, area ) {

    // printl( "Initializing spoke trace for area: " + area_name )

    // Process each particle type and initialize data structures
    foreach( particle_name, particle_info in ValidAreasForParticle ) {
        // Initialize particle info for this area if it doesn't exist
        if ( !(area in particle_info) )
            particle_info[ area ] <- { origin_override = Vector() }
    }
}

function VSWeather::ValidAreasYield( i, area ) {

    foreach ( particle_name, particle_info in ValidAreasForParticle )
        VSWeather.DebugLog.LOG_PRINT( format( "[%s] Valid areas: (%d / %d)", particle_name, particle_info.len(), AllAreas.len() ), "DEBUG" )
}

// Run the spoke trace loop using NonBlockingLoop
function VSWeather::RunSpokeTraceLoop( oncomplete ) {

    VSWeather.DebugLog.LOG_PRINT( "Starting trace loop (prepare for lag)", "INFO" )

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

                area_name     = area.GetID()
                area          = area
                particle_name = particle_name
                particle_info = particle_info
                completed     = false
                trace_failed  = false
                cfg           = cfg
                trace_start   = area.GetCenter() + Vector( 0, 0, cfg.travel_distance )
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
            VSWeather.DebugLog.LOG_PRINT( "Done tracing! Spawning particles...", "INFO" )
        return result
    }

    local function trace_step() {

        // printl( "Tracing job " + current_job_index + " of " + trace_jobs.len() )

        if ( !(current_job_index in TraceJobs) )
            return

        local job = TraceJobs[current_job_index]

        // first trace straight up to make sure the sky is visible
        local trace_full = {

            start   = job.trace_end
            end     = job.trace_start + Vector( 0, 0, INT_MAX )
            hullmin = Vector( -10, -10, -10 )
            hullmax = Vector( 10, 10, 10 )
            ignore  = GetListenServerHost()
            allsolid   = false
            startsolid = false
        }

        // TODO: move this to ValidAreasForParticle collection
        // no point doing TraceLineEx in the main loop when we can do that on script init.
        if ( job.hit_sky == null ) {

            TraceLineEx( trace_full )

            job.hit_sky = trace_full.surface_flags & SURF_SKY
            // printl( "trace_full.surface_flags: " + trace_full.surface_flags + " " + job.hit_sky )
            job.completed = !job.hit_sky

            // printl( "job.hit_sky: " + job.hit_sky + " " + !job.completed )
        }

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
                local trace_result = TraceLine( job.trace_start, spoke_end, null ) + TraceLine( spoke_end, job.trace_start, null )

                // this trace hit a surface
                // traces that progressively get smaller usually mean we're hitting a rock or something on the ground
                // we can safely ignore these and have rain fall through them
                if ( trace_result < info.last_result - CONFIG.TRACE_FORGIVENESS ) {

                    // if (result1 + result2 >= 1.75) {

                        // printf( "TRACING: %s <-> %s -> %0.2f\n", job.trace_start.ToKVString(), spoke_end.ToKVString(), result1 + result2 );
                        // status = color_small
                    // }

                    if ( info.status != color_warn ) {

                        // use this trace position to override the particle system origin, then look for another trace that enters playable space
                        job.particle_info[ job.area ].origin_override = Vector( job.trace_start.x, job.trace_start.y, job.trace_start.z + z_step )
                        info.status = color_warn
                        info.last_result = trace_result
                    }
                }

                // ... but a subsequent trace did not
                // we might've just punched through a ceiling

                // check if we hit a trace that's larger than the last one
                // if so, we've probably entered playable/visible space.
                // TODO: this alone causes false-negatives, leaving "dead spots" with no rain
                // better than raining inside though, right?
                else if ( trace_result <= 2.0 - CONFIG.TRACE_FORGIVENESS ) {


                    if ( (CONFIG.IGNORE_DISPLACEMENTS || CONFIG.IGNORE_PROPS) ) {

                        trace_full.start = job.trace_start
                        trace_full.end = spoke_end
                        TraceLineEx( trace_full )

                        if ( trace_full.surface_name == "**displacement**" && CONFIG.IGNORE_DISPLACEMENTS )
                            continue

                        else if ( ( trace_full.surface_name == "**studiomdl**" || trace_full.surface_name == "**empty**" ) && CONFIG.IGNORE_PROPS )
                            continue
                    }
                        info.status = color_danger
                        job.trace_failed = true
                        job.completed = true
                }
        
                // set TRACE_FUNCS very low ( < 6 ) to avoid crashing before uncommenting this
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

    foreach( particle_name, particle_info in ValidAreasForParticle ) {

        foreach( area, info in particle_info )
            all_valid_areas[ area ] <- { particle_name = particle_name, info = info }
    }

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

    if ( !origin_pre_offset.LengthSqr() )
        origin_pre_offset = area.GetCenter()

    if ( !("targetname" in kvs) )
        kvs.targetname <- "__vs_weather_" + particle_name + "_" + area.GetID()
    else
        kvs.targetname = kvs.targetname + "_" + area.GetID()

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

    DebugLog.LOG_PRINT( "Spawned particle system: " + particle_name + " at " + final_origin.ToKVString(), "DEBUG" )

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

    Generators.GeneratorChain({

        GetValidAreas = [

            function(oncomplete) {

                return Generators.DeferredForEach(
                    AllAreas,
                    CONFIG.ITERS_PER_FRAME.NAV_AREAS,
                    InitNavParticleInfo, // initialize spoke trace for each area
                    ValidAreasYield, // yields for each iters_per_frame
                    oncomplete       // completion callback (REQUIRED for chaining)
                )
            }

        ]
        SpokeTrace = [

            function(oncomplete) {

                return RunSpokeTraceLoop( oncomplete )
            },
            @() Generators.StartGenerator( Generators.DeferredForEach( InitializeSpawnParticles(), CONFIG.ITERS_PER_FRAME.SPAWN_PARTICLES, SpawnParticles, null, @(_) weather_complete = true ) )
        ]
        // SpawnParticles = [

        //     function(oncomplete) {

        //         return VSWeather.Generators.DeferredForEach(
        //             VSWeather._InitializeSpawnParticles(),
        //             100,
        //             VSWeather._SpawnParticles,
        //             null,        // no yield callback
        //             oncomplete   // completion callback (REQUIRED for chaining)
        //         )
        //     }
        // ]
    })
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
}.setdelegate( VSWeather )

if ( "Events" in VSWeather )
    delete VSWeather.Events

VSWeather.Events <- {}.setdelegate( VSWeather )
function VSWeather::Events::OnGameEvent_player_say( params ) {

    local text = params.text

    if ( text[0] != '.' || !(1 in text) || text[1] != 'w' )
        return

    local cmd = text.slice( 2 )

    if ( !weather_complete && cmd != "start" && cmd != "trace" ) {

        DebugLog.LOG_PRINT( "Weather is not complete yet.", "INFO" )
        return
    }

    else if ( !(cmd in ChatCommands) ) {

        DebugLog.LOG_PRINT( "Unknown command: " + text, "INFO" )
        return
    }

    ChatCommands[ cmd ]( params )
}
__CollectGameEventCallbacks( VSWeather.Events )

VSWeather.InitNav()
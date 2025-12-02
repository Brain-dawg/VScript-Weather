local ROOT = getroottable()

local function Include( file ) { IncludeScript( "vs_weather/_core/" + file, ROOT ) }

Include( "constants" )
Include( "create_scope" )

// dummy entity to scope everything to
___CREATE_SCOPE( "__vs_weather", "VSWeather", "VSWeatherEntity", "VSWeatherThink" )

Include( "util" )
Include( "generators" )
Include( "../CONFIG.nut" )

DebugDrawClear()

VSWeather.AllAreas   <- {}
VSWeather.ValidAreasForParticle <- {}
VSWeather.Events     <- {}
VSWeather.weather_complete <- false
VSWeather.weather_editing  <- false
VSWeather.particle_count <- 0

function VSWeather::InitNav() {

    GetAllAreas( AllAreas )

    Assert( AllAreas.len(), "MAP HAS NO NAVMESH! run nav_generate before running this script" )

    // Initialize ValidAreasForParticle for each particle type
    foreach( particle_name, cfg in CONFIG.WeatherSystems ) {
        ValidAreasForParticle[ particle_name ] <- {}
    }

    // Start the generator chain
    Generators.GeneratorChain({

        GetValidAreas = [

            function(oncomplete) {

                return Generators.DeferredForEach(
                    AllAreas,
                    CONFIG.ITERS_PER_FRAME.TRACE_JOB_INIT,
                    InitializeSpokeTrace, // initialize spoke trace for each area
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

// Initialize spoke trace data for each area
function VSWeather::InitializeSpokeTrace( area_name, area ) {

    printl( "Initializing spoke trace for area: " + area_name )

    // Process each particle type and initialize data structures
    foreach( particle_name, particle_info in ValidAreasForParticle ) {
        // Initialize particle info for this area if it doesn't exist
        if ( !(area in particle_info) )
            particle_info[ area ] <- { origin_override = Vector() }
    }
}

// Store areas that need spoke tracing
VSWeather.AreasToTrace <- []

// Store tracing state
VSWeather.TraceState <- {}

// Run the spoke trace loop using NonBlockingLoop
function VSWeather::RunSpokeTraceLoop( oncomplete ) {

    printl( "Starting spoke trace loop" )

    // Collect all areas that need tracing and create trace jobs
    local trace_jobs = []

    foreach( particle_name, particle_info in ValidAreasForParticle ) {

        foreach( area, info in particle_info ) {

            trace_jobs.append({
                area_name     = area.GetID(),
                area          = area,
                particle_name = particle_name,
                particle_info = particle_info,
                completed     = false,
                color         = [0, 255, 0],
                cfg           = CONFIG.WeatherSystems[ particle_name ],
                trace_start   = area.GetCenter() + Vector( 0, 0, CONFIG.WeatherSystems[ particle_name ].travel_distance ),
                trace_end     = area.GetCenter(),
                hit_sky       = null, // start it null and set to true or false so we don't need to trace this again
            })
        }
    }

    local current_job_index = 0

    // Define colors for debug drawing
    local color_valid = [0, 255, 0]    // green
    local color_warn = [255, 255, 0]   // yellow
    local color_edge = [255, 128, 0]   // orange
    local color_danger = [255, 0, 0]   // red

    // Define trace directions (4 cardinal directions + 4 diagonal directions)
    local directions = [
        Vector(1, 0, 0),       // +X right
        Vector(0.5, 0.5, 0),   // +X +Y
        Vector(-1, 0, 0),      // -X left
        Vector(-0.5, -0.5, 0), // -X -Y
        Vector(0, 1, 0),       // +Y up
        Vector(0, -1, 0),      // -Y down
        Vector(-0.5, 0.5, 0),  // -X +Y
        Vector(0.5, -0.5, 0)   // +X -Y
    ]

    local z_step = 100

    local function should_continue() {

        local result = current_job_index in trace_jobs
        if ( !result )
            print( "\n\nDone tracing! Spawning particles...\n\n" )
        return result
    }

    local function trace_step() {

        // printl( "Tracing job " + current_job_index + " of " + trace_jobs.len() )

        if ( !(current_job_index in trace_jobs) )
            return

        local job = trace_jobs[current_job_index]

        // first trace straight up to make sure the sky is visible
        local trace = {

            start   = job.trace_start
            end     = job.trace_start + Vector( 0, 0, INT_MAX )
            hullmin = Vector( -10, -10, -10 )
            hullmax = Vector( 10, 10, 10 )
            ignore  = GetListenServerHost()
        }

        if ( job.hit_sky == null ) {

            TraceLineEx( trace )

            job.hit_sky = trace.surface_props & SURF_SKY

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

            foreach( dir in directions ) {

                if ( job.completed )
                    break

                local spoke_end = Vector( job.trace_start.x + dir.x * job.cfg.radius, job.trace_start.y + dir.y * job.cfg.radius, job.trace_start.z )
                local result1 = TraceLine( job.trace_start, spoke_end, null )
                local result2 = TraceLine( spoke_end, job.trace_start, null )

                // printf( "TRACING: %s <-> %s -> %d\n", job.trace_start.ToKVString(), spoke_end.ToKVString(), result1 + result2 );

                // first trace hit a surface
                if ( result1 + result2 < 2 ) {

                    // we failed our first trace
                    // check if subsequent traces enter playable space
                    // if they do, this particle will clip through a ceiling/wall or something, delete it
                    if ( !job.particle_info[ job.area ].origin_override.Length() ) {

                        job.color = color_warn
                        // use this trace position to override the particle system origin, then look for another trace that enters playable space
                        job.particle_info[ job.area ].origin_override = Vector( job.trace_start.x, job.trace_start.y, job.trace_start.z + z_step )
                    }
                }

                // ... but a subsequent trace did not
                else if ( job.particle_info[ job.area ].origin_override.Length() ) {

                    trace.start = spoke_end
                    trace.end = spoke_end
                    trace.hullmin = Vector( -10, -10, -10 )
                    trace.hullmax = Vector( 10, 10, 10 )
                    // TraceLineEx( trace )
                    TraceHull( trace )
                    if ( trace.surface_name == "**displacement**" )
                        printl( "trace.surface_name: " + trace.surface_name + " : " + trace.surface_flags + " : " + trace.surface_props )

                    if ( trace.surface_name[0] == '*' && trace.surface_name != "**displacement**" )                   
                        // ignore rocks and stuff     
                       job.color = color_edge
                    else
                        // trace entered playable space.  Stop tracing
                        job.color = color_danger, job.completed = true

                }

                if ( job.color[0] )
                    DebugDrawLine( job.trace_start, spoke_end, job.color[0], job.color[1], job.color[2], false, job.completed ? 30.0 : 0.5 )
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
            // printl( job.color == color_danger )
            if ( job.color == color_danger )
                delete ValidAreasForParticle[job.particle_name][job.area]

            current_job_index++
        }
    }

    return Generators.NonBlockingLoop( should_continue, CONFIG.ITERS_PER_FRAME.TRACE_JOB_RUN, trace_step, null, oncomplete )
}

// VSWeather.Generators.NonBlockingLoop(  @() tracing, 1023, _SpokeTrace, null, @() tracing = false )

function VSWeather::ValidAreasYield( area_name, area ) {

    foreach ( particle_name, particle_info in ValidAreasForParticle )
        printf( "[%s] Valid areas: (%d / %d)\n", particle_name, particle_info.len(), AllAreas.len() )
}

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

    if ( !("vscripts" in kvs) )
        kvs.vscripts <- " "

    local final_origin = Vector( origin_pre_offset.x, origin_pre_offset.y, origin_pre_offset.z + cfg.travel_distance )

    kvs.origin      <- final_origin
    kvs.effect_name <- particle_name

    // area.DebugDrawFilled( color_valid[0], color_valid[1], color_valid[2], 255, 0.1, true, 0.0 )

    // Check for nearby particles to avoid duplicates
    local nearby_particle = FindByClassnameNearest( "info_particle_system", kvs.origin, cfg.radius )
    if ( nearby_particle && GetPropString( nearby_particle, "m_iszEffectName" ) == particle_name ) {
        // printl( "Skipping duplicate particle at " + kvs.origin.ToKVString() )
        return
    }

    if ( particle_count >= CONFIG.MAX_WEATHER_SYSTEMS )
        return

    particle_count++

    local ent = SpawnEntityFromTable( "info_particle_system", kvs )

    if ( ent.GetOrigin() != final_origin )
        ent.SetAbsOrigin( final_origin )

    DebugDrawBox( final_origin, Vector( -10, -10, -10 ), Vector( 10, 10, 10 ), color_small[0], color_small[1], color_small[2], 0, 60.0 )
    DebugDrawLine( origin_pre_offset, final_origin, color_small[0], color_small[1], color_small[2], false, 60.0 )

    // printl( "Spawned particle system: " + particle_name + " at " + final_origin.ToKVString() )
}

function VSWeather::Events::OnGameEvent_player_say( params ) {

    if ( params.text == ".weather_edit" ) {

        if ( !VSWeather.weather_complete ) {

            DebugLog.LOG_PRINT( "Weather is not complete yet.", "INFO" )
            return
        }
    }
}

VSWeather.InitNav()
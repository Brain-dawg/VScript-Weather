// see vs_weather/CONFIG.nut for configuration options and how-to-use

local ROOT = getroottable()

// little silly to call ChatCommands this way but whatever it works.
if ( "VSWeather" in ROOT && "ChatCommands" in VSWeather )
    return VSWeather.ChatCommands.reset( null, null )

local function Include( file ) { IncludeScript( "vs_weather/_core/" + file, ROOT ) }

Include( "constants" )
Include( "create_scope" )

// dummy entity to scope everything to
___CREATE_SCOPE( "__vs_weather", "VSWeather", "VSWeatherEntity", "VSWeatherThink" )

Include( "../CONFIG.nut" )
Include( "debuglog" )
Include( "util" )
Include( "generators" )
Include( "maplogic" )
Include( "navutils" )

DebugDrawClear()
VSWeather.TraceJobs             <- []
VSWeather.FailedJobs            <- []
VSWeather.SpawnedParticles      <- []

VSWeather.AllAreas              <- {}
VSWeather.ValidAreasForParticle <- {}
VSWeather.Events                <- {}
VSWeather.ChatCommands          <- {}

VSWeather.particle_count        <- 0
VSWeather.weather_editing       <- false
VSWeather.weather_complete      <- false

local trace_cfg = VSWeather.CONFIG.TRACING

VSWeather.do_expensive_trace <- trace_cfg.IGNORE_DISPLACEMENTS
                                || trace_cfg.IGNORE_PROPS
                                || trace_cfg.IGNORE_TRANSLUCENT
                                || (trace_cfg.IGNORE_THESE_TEXTURES || {}).len()
                                || (trace_cfg.IGNORE_THESE_SURFACE_PROPS || {}).len()

VSWeather.do_ent_avoid_trace <- (trace_cfg.AVOID_THESE_ENTS || {}).len()


function VSWeather::collectgarbage() { ::collectgarbage() }
function VSWeather::InitNav() {

    AllAreas.clear()
    GetAllAreas( AllAreas )

    if ( !AllAreas.len() )
        return DebugLog.LOG_PRINT( "MAP HAS NO NAVMESH! type '.wnav create' to create one", "FATAL" )

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

    // TODO: figure out a better snap-to-floor approach
    // for now just grab the nearest nav area

    important_ents.apply( @( ent ) GetNearestNavArea( ent.GetOrigin(), 512, true, true ) || ent )

    // ensure important map entities get iterated over first.
    AllAreas = important_ents.extend( AllAreas.values() )

    local corners = array( AllAreas.len() * NUM_CORNERS, null )

    if ( trace_cfg.ALL_NAV_CORNERS_SLOW ) {

        // convert to vectors + area corners

        local idx = 0
        foreach( i, area in AllAreas ) {

            AllAreas[i] = area.GetCenter()

            if ( !( area instanceof CTFNavArea ) )
                continue

            for (local j = 0; j < NUM_CORNERS; j++) {

                idx = i * NUM_CORNERS + j
                corners[idx] = area.GetCorner( j )
            }
        }

        AllAreas = AllAreas.extend( corners.filter( @( _, corner ) corner ) )
    }

}

// Pre-check nav areas for skybox visibility and distance
function VSWeather::SetupAreaParticleInfo( i, area, test_mode = false ) {

    // NOTE: this array is a mix of CBaseEntity derived ents AND CNavAreas.
    // conveniently, GetCenter() is available on both.
    // DO NOT ASSUME THIS IS ONLY NAV AREAS!

    local area_center = typeof area == "Vector" ? area : area.GetCenter()
    local ignore = area instanceof CBaseEntity ? area : LOCALPLAYER

    local trace_full = {

        start   = area_center
        end     = area_center + Vector( 0, 0, INT_MAX )
        mask    = trace_cfg.TRACE_MASK
        ignore  = ignore
        hullmin = Vector()
        hullmax = Vector()
        allsolid   = false
        startsolid = false
    }

    foreach( particle_name, particle_info in ValidAreasForParticle ) {

        local cfg = CONFIG.WeatherSystems[ particle_name ]
        local radius = cfg.radius / 2
        local distance = cfg.travel_distance / 2

        // DebugDrawBox( area_center, Vector( -radius, -radius, -distance ), Vector( radius, radius, distance ), 255, 0, 0, 0, 10.0 )


        if ( !(area_center in particle_info) || test_mode ) {

            // make sure the sky is visible
            TraceLineEx( trace_full )

            if ( !(trace_full.surface_flags & SURF_SKY ) )
                continue

            particle_info[ area_center ] <- {

                origin_override = Vector(),
                // offset trace start position down by the fraction of the travel distance that is in the skybox.
                start_in_skybox = TraceLine( area_center, area_center + Vector( 0, 0, CONFIG.WeatherSystems[ particle_name ].travel_distance ), ignore )
            }
        }
    }
}

function VSWeather::ValidAreasYield( i, area ) {

    foreach ( particle_name, particle_info in ValidAreasForParticle )
        DebugLog.LOG_PRINT( format( "[%s] Valid areas: (%d / %d)", particle_name, particle_info.len(), AllAreas.len() ), "DEBUG" )
}

// Run the spoke trace loop using NonBlockingLoop
function VSWeather::RunSpokeTraceLoop( oncomplete, test_mode = false ) {

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

    local i = 0
    foreach( particle_name, particle_info in ValidAreasForParticle ) {

        local cfg = CONFIG.WeatherSystems[ particle_name ]

        local area_center

        // TODO: does not scale indefinitely with nav area size
        // hits SQQuerySuspend on large navs with ALL_NAV_CORNERS_SLOW = true
        // move all this stuff to a generator

        // in the meantime we will use the worst hack ever: catching SQQuerySuspend and just ignoring it
        try {

            foreach( area, info in particle_info ) {

                // trace_job.cfg           = CONFIG.WeatherSystems[ particle_name ]
                // trace_job.area          = area
                // trace_job.area_name     = typeof area == "Vector" ? area.ToKVString() : area.GetCenter().ToKVString()
                // trace_job.trace_end     = area.GetCenter()
                // trace_job.trace_start   = area.GetCenter() + Vector( 0, 0, trace_job.cfg.travel_distance )
                // trace_job.particle_name = particle_name
                // trace_job.particle_info = particle_info

                // TraceJobs.append( trace_job )

                area_center = area instanceof Vector ? area : area.GetCenter()

                TraceJobs[i] = {

                    // area_name     = area_center.ToKVString()
                    area          = area
                    particle_name = particle_name
                    particle_info = particle_info
                    completed     = false
                    trace_failed  = false
                    cfg           = cfg
                    trace_start   = area_center + Vector( 0, 0, cfg.travel_distance * particle_info[ area ].start_in_skybox )
                    trace_end     = area_center

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
                }
                i++
            }

        } catch ( e ) { 
            return RunSpokeTraceLoop( oncomplete, test_mode )
        }
    }

    // local last_print_index  = 0
    local current_job_index = 0
    local z_step = 2
    local should_continue = true

    local trace_full = {

        start   = null
        end     = null
        mask    = trace_cfg.TRACE_MASK
        ignore  = LOCALPLAYER
        enthit  = First()
        allsolid   = false
        startsolid = false
    }

    local function trace_step() {

        should_continue = current_job_index in TraceJobs
        
        if ( !should_continue )
            return

        local job = TraceJobs[current_job_index]

        if ( !job )
            return should_continue = false
    
        if ( job.completed ) {

            if ( job.area in ValidAreasForParticle[job.particle_name] )
                delete ValidAreasForParticle[job.particle_name][job.area]

            return current_job_index++
        }

        // printf( "Tracing job %d/%d: area %d, particle %s\n", current_job_index + 1, trace_jobs.len(), job.area_name, job.particle_name )


        // Perform one Z-level of tracing
        if ( job.trace_start.z > job.trace_end.z ) {

            foreach( dir_status in job.trace_dirs ) {

                local dir  = dir_status[0]
                local info = dir_status[1]

                if ( job.completed ) break

                local spoke_end = Vector( job.trace_start.x + dir.x * job.cfg.radius, job.trace_start.y + dir.y * job.cfg.radius, job.trace_start.z )
                local trace_result = TraceLine( job.trace_start, spoke_end, LOCALPLAYER ) + TraceLine( spoke_end, job.trace_start, LOCALPLAYER )

                // this trace hit a surface
                // traces that progressively get smaller usually mean we're hitting a rock or something on the ground
                if ( trace_result < info.last_result ) {

                    if ( do_expensive_trace ) {

                        trace_full.start = job.trace_start
                        trace_full.end   = spoke_end

                        TraceLineEx( trace_full )

                        local surface_name = trace_full.surface_name.tolower()

                        if ( surface_name[0] == '*' ) {

                            if ( trace_cfg.IGNORE_DISPLACEMENTS && surface_name == "**displacement**" )
                                continue

                            else if ( trace_cfg.IGNORE_PROPS && ( surface_name == "**studiomdl**" || surface_name == "**empty**" ) )
                                continue
                        }

                        if ( trace_cfg.IGNORE_TRANSLUCENT && trace_full.surface_flags & SURF_TRANS )
                            continue

                        if ( surface_name in trace_cfg.IGNORE_THESE_TEXTURES && trace_cfg.IGNORE_THESE_TEXTURES[surface_name] )
                            continue

                        local surface_prop = trace_full.surface_props
                        local surface_prop_name = surface_prop in SURFACEPROPS ? SURFACEPROPS[surface_prop] : "UNKNOWN"

                        if ( surface_prop_name in trace_cfg.IGNORE_THESE_SURFACE_PROPS && trace_cfg.IGNORE_THESE_SURFACE_PROPS[surface_prop_name] )
                            continue
                    }

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
                job.trace_failed = info.status != color_valid && trace_result > info.last_result * trace_cfg.TRACE_FORGIVENESS

                // now check if we hit an avoidable entity, always fail this
                if ( do_ent_avoid_trace && !job.trace_failed ) {

                    trace_full.start <- job.trace_start
                    trace_full.end   <- spoke_end
                    TraceLineEx( trace_full )

                    local enthit = trace_full.enthit
                    local enthit_name = enthit.GetName()
                    local enthit_class = enthit.GetClassname()

                    if ( enthit != First() ) {

                        if ( enthit_name in trace_cfg.AVOID_THESE_ENTS && trace_cfg.AVOID_THESE_ENTS[enthit_name] )
                            job.trace_failed = true

                        else if ( enthit_class in trace_cfg.AVOID_THESE_ENTS && trace_cfg.AVOID_THESE_ENTS[enthit_class] )
                            job.trace_failed = true

                        if ( job.trace_failed )
                            job.particle_info[ job.area ].origin_override = Vector( job.trace_start.x, job.trace_start.y, job.trace_start.z + z_step )
                    }
                }

                if ( job.trace_failed ) {

                    info.status = color_danger
                    job.completed = true
                    FailedJobs.append( job )
                }

                // set TRACE_FUNCS very low ( < 12 ) to avoid crashing before uncommenting this
                // use host_timescale to compensate for the slowdown

                if ( test_mode )
                    DebugDrawLine( job.trace_start, spoke_end, info.status[0], info.status[1], info.status[2], false, 2.0 )
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

            // if ( current_job_index - last_print_index > 1999 ) {

            //     DebugLog.LOG_PRINT( "Tracing " + current_job_index + " of " + TraceJobs.len(), "DEBUG" )
            //     last_print_index = current_job_index
            // }
            current_job_index++

            // if ( test_mode ) {

            //     local radius = job.cfg.radius / 2
            //     local distance = job.cfg.travel_distance / 2

            //     DebugDrawBox( job.trace_start, Vector( -radius, -radius, -job.cfg.travel_distance / 2 ), Vector( radius, radius, job.cfg.travel_distance / 2 ), 255, 0, 0, 0, 10.0 )
            // }
        }
        should_continue = current_job_index in TraceJobs
    }

    if ( test_mode )
        return Generators.StartGenerator( Generators.NonBlockingLoop( @() should_continue, CONFIG.ITERS_PER_FRAME.TRACE_FUNCS, trace_step, null, oncomplete ) )

    return Generators.NonBlockingLoop( @() should_continue, CONFIG.ITERS_PER_FRAME.TRACE_FUNCS, trace_step, null, oncomplete )
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
    local area_center = typeof area == "Vector" ? area : area.GetCenter()
    local area_id = area_center.ToKVString()

    if ( !origin_pre_offset.LengthSqr() )
        origin_pre_offset = area_center

    if ( !("targetname" in kvs) )
        kvs.targetname <- "__vs_weather_" + particle_name + "_" + area_id
    else if ( CONFIG.MISC.UNIQUE_TARGETNAMES )
        kvs.targetname = kvs.targetname + "_" + area_id

    // "vscripts" kv w/ invalid filename will still set up the script scope on spawn
    // without needing to call .ValidateScriptScope() later
    // cannot be an empty string or null, just use a space
    local defaults = {
        angles   = "0 0 0"
        vscripts = " "
    }

    foreach ( kv, def in defaults )
        if ( !(kv in kvs) )
            kvs.kv <- def

    local final_origin = Vector( origin_pre_offset.x, origin_pre_offset.y, origin_pre_offset.z + cfg.travel_distance )

    kvs.origin      <- final_origin
    kvs.effect_name <- particle_name

    // area.DebugDrawFilled( color_valid[0], color_valid[1], color_valid[2], 255, 0.1, true, 0.0 )

    // Check for nearby particles to avoid duplicates
    local nearby_particle = FindByClassnameNearest( "info_particle_system", kvs.origin, cfg.radius * cfg.overlap_mult )
    if ( nearby_particle && GetPropString( nearby_particle, "m_iszEffectName" ) == particle_name ) {
        DebugLog.LOG_PRINT( "Skipping duplicate particle at " + kvs.origin.ToKVString(), "DEBUG" )
        return
    }

    if ( particle_count >= CONFIG.MISC.MAX_WEATHER_SYSTEMS )
        return

    local ent = SpawnEntityFromTable( "info_particle_system", kvs )

    // kvs.id <- GetPropInt( ent, "m_iHammerID" )
    kvs.classname <- "info_particle_system"

    SpawnedParticles.append( kvs )

    if ( ent.GetOrigin() != final_origin )
        ent.SetAbsOrigin( final_origin )

    DebugDrawBox( final_origin, Vector( -10, -10, -10 ), Vector( 10, 10, 10 ), color_small[0], color_small[1], color_small[2], 0, 9999.0 )
    DebugDrawLine( origin_pre_offset, final_origin, color_small[0], color_small[1], color_small[2], false, 9999.0 )

    DebugLog.LOG_PRINT( "Spawned particle system at " + final_origin.ToKVString() + "(Count: " + particle_count + ")", "DEBUG" )

    particle_count++
}

function VSWeather::EntityKVToInstanceString( kvs ) {

    local output = "\nentity\n{"

    foreach( key, value in kvs ) {

        switch ( typeof value ) {

            case "bool":
                value = value ? "1" : "0"
            break

            case "Vector":
            case "QAngle":
                value = value.ToKVString()
            break
        }

    output += format( @"
    ""%s"" ""%s""", key.tostring(), value.tostring() )
    }
    output += @"
    editor
    {
        ""color"" ""0 128 255""
        ""visgroupshown"" ""1""
        ""visgroupautoshown"" ""1""
    }"
    return output + "\n}"
}

// Start the generator chain
function VSWeather::Start() {

    local i = 0
    for ( local ent = Entities.First(); ent; ent = Entities.Next( ent ) )
        i++

    if ( i + CONFIG.MISC.MAX_WEATHER_SYSTEMS > MAX_EDICTS )
        return DebugLog.LOG_PRINT( format( "Not enough edicts to spawn particles.  %d + %d > %d", i, CONFIG.MISC.MAX_WEATHER_SYSTEMS, MAX_EDICTS ), "ERROR" )

    weather_complete = false

    AllAreas = AllAreas.filter( @( _, area ) area && ( typeof area == "Vector" || area.IsValid() ) )

    // SpawnEntityFromTable( "env_fog_controller", {
    //     targetname = "__vs_weather_fog"
    //     farz = 1
    //     fogstart = 1
    //     fogend = 1
    //     fogenable = 1
    //     fogcolor = "0 0 0"
    // })

    // EntFire( "player", "SetFogController", "__vs_weather_fog" )
    // kill some entities that may be running think functions and eating our perf budget
    foreach( ent in ["phys_bone*", "info_particle_system", "tf_wea*", "tf_viewmodel", "item_*", "env_smokestack", "env_sprite", "func_dust*"] )
        EntFire( ent, "Kill" )

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
            },
            @(_) TraceJobs = array( ValidAreasForParticle.len() * AllAreas.len(), null )
        ],
        [
            function(oncomplete) {

                return RunSpokeTraceLoop( oncomplete )
            },

            function() {
            
                DebugLog.LOG_PRINT( "Done tracing! Spawning particles...", "INFO" )
                // EntFire( "__vs_weather_fog", "Kill" )

                Generators.StartGenerator( Generators.DeferredForEach(
                    InitializeSpawnParticles(),
                    CONFIG.ITERS_PER_FRAME.SPAWN_PARTICLES,
                    SpawnParticles,
                    null,
                    function(_) {
                        weather_complete = true
                        DebugLog.LOG_PRINT( "Spawned " + particle_count + " particles", "INFO" )
                    }
                ))
            }
        ]
    ])
}

// chat commands are all prefixed with ".w"
// e.g. "start" is ".wstart"
function VSWeather::ChatCommands::start( params, args ) { Start() }
// function VSWeather::ChatCommands::edit( params, args ) {}

function VSWeather::ChatCommands::test( params, args ) {

    if ( !("_ValidAreasForParticle_BACKUP" in VSWeather) )
        VSWeather._ValidAreasForParticle_BACKUP <- clone ValidAreasForParticle

    local area_center = GetNearestNavArea( LOCALPLAYER.GetOrigin(), INT_MAX, false, false ).GetCenter()

    foreach( particle_name, particle_info in ValidAreasForParticle ) {

        particle_info.clear()

        particle_info[ area_center ] <- {

            origin_override = Vector()
            start_in_skybox = TraceLine( area_center, area_center + Vector( 0, 0, CONFIG.WeatherSystems[ particle_name ].travel_distance ), LOCALPLAYER )
        }
    }

    TraceJobs = array( 2, null )
    DebugDrawClear()
    SetupAreaParticleInfo( 0, area_center, true )
    RunSpokeTraceLoop( @() ValidAreasForParticle = _ValidAreasForParticle_BACKUP, true )

    // ValidAreasForParticle = _ValidAreasForParticle_BACKUP
}
function VSWeather::ChatCommands::trace( params, args ) {

    local trace_full = {
        start = LOCALPLAYER.EyePosition()
        end   = LOCALPLAYER.EyeAngles().Forward() * INT_MAX
        mask  = trace_cfg.TRACE_MASK
        ignore = LOCALPLAYER
    }

    DebugLog.LOG_PRINT( "Trace info printed to console.  Set mat_queue_mode 0 for better readability.", "INFO" )
    TraceLineEx( trace_full )
    DebugDrawLine( trace_full.startpos, trace_full.endpos, 0, 255, 0, false, 10.0 )

    delete trace_full.start
    delete trace_full.end
    delete trace_full.mask
    delete trace_full.ignore

    local surface_prop = trace_full.surface_props
    local surface_prop_name = surface_prop in SURFACEPROPS ? SURFACEPROPS[surface_prop] : "UNKNOWN"
    trace_full.surface_props = surface_prop + " (" + surface_prop_name + ")"

    __DumpScope( 0, trace_full )
}

function VSWeather::ChatCommands::save( params, args ) {

    local output = ""

    if ( !args.len() )
        return DebugLog.LOG_PRINT( "Usage: .wsave <instance|script>", "INFO" )

    if ( args[0] == "instance" ) {

        foreach( kvs in SpawnedParticles )
            output += EntityKVToInstanceString( kvs )

        // slice off the first newline, add another newline for null character
        StringToFile( CONFIG.MISC.SAVE_FILENAME + ".vmf", output.slice(1) + "\n" )

        DebugLog.LOG_PRINT( "Saved " + SpawnedParticles.len() + " particle systems to instance file: tf/scriptdata/" + CONFIG.MISC.SAVE_FILENAME + ".vmf", "INFO" )
        DebugLog.LOG_PRINT( "\n1. Move this file to your tf/maps/instances/ folder\n2. Spawn a func_instance at 0 0 0 in your map\n3. Set the VMF filename to this file", "INFO")
        DebugLog.LOG_PRINT( "You can now collapse the instance into the main map, if you prefer", "INFO" )
        return
    }

    else if ( args[0] == "script" ) {

output = @"// HOW TO USE:

// 1. Move this file from tf/scriptdata/ to tf/scripts/vscripts/ on your server
// 2. add this entire line (quotes brackets etc) to your server cfg:

// script try { IncludeScript( GetMapName() + ""_weather_particles.nut"" ) } catch ( e ) { printl( ""[VSWEATHER]: "" + e ) }

// Your server will now run any script files named <mapname>_weather_particles.nut on map load.
// Only need to do this step once.

"
        output += "::VS_WEATHER_PARTICLES <- ["

        foreach( kvs in SpawnedParticles ) {

            output += "\n\t{"
            foreach( key, value in kvs ) {

                switch ( typeof value ) {

                    case "bool":
                        value = value ? "1" : "0"
                    break

                    case "Vector":
                    case "QAngle":
                        value = value.ToKVString()
                    break
                }

                output += "\n\t\t\"" + key + "\" : \"" + value + "\""
            }
            output += "\n\t},"
        }

output += @"
]

function ___VSWEATHER_PARTICLE_SPAWN() {

    foreach ( kv in VS_WEATHER_PARTICLES )
        SpawnEntityFromTable( kv.classname, kv );
}

// spawn particles immediately on script load
___VSWEATHER_PARTICLE_SPAWN()
printl( ""[VSWEATHER] spawned "" + VS_WEATHER_PARTICLES.len() + "" weather particles"" )

// respawn on round restarts
::___VSWEATHER_PARTICLE_RESPAWN <- {

    function OnGameEvent_teamplay_round_start( _ ) {

        ___VSWEATHER_PARTICLE_SPAWN()
    }
}
__CollectGameEventCallbacks( ___VSWEATHER_PARTICLE_RESPAWN )

// ignore this, or delete it, up to you!
"

        if ( CONFIG.MISC.SAVE_FILENAME != MAPNAME + "_weather_particles.nut" )
            DebugLog.LOG_PRINT( "SAVE_FILENAME is ignored for script saving!", "WARNING" )

        StringToFile( MAPNAME + "_weather_particles.nut", output )
        DebugLog.LOG_PRINT( "Saved " + SpawnedParticles.len() + " particle systems to script file: tf/scriptdata/" + MAPNAME + "_weather_particles.nut", "INFO" )
        return
    }

}

function VSWeather::ChatCommands::reset( params, args ) {

    DebugLog.LOG_PRINT( "Reloading...", "WARNING" )
    StringToFile( "__vsweather_nav_cleanup_and_save", "0" )

    // TODO: this should be getting cleared out by __vs_weather being killed
    // likely ___CREATE_SCOPE nonsense
    GameEventCallbacks.player_say.clear()

    // probably unnecessary, however this gc sweep can take upwards of a second
    // I assume it's doing something...
    EntFire( "__vs_weather", "callscriptfunction", "collectgarbage" )
    EntFire( "__vs_weather*", "Kill" )
    EntFire( "worldspawn", "RunScriptFile", getstackinfos(1).src, 0.1 )
    // SendToConsole( "mp_restartgame_immediate 1;" )
}
function VSWeather::ChatCommands::reload( params, args ) { reset( params, args ) }

function VSWeather::ChatCommands::nav( params, args ) {

    SendToConsole( "nav_edit 1" )

    if ( !args.len() )
        return DebugLog.LOG_PRINT( "Usage: .wnav <create|cleanup|subdivide|disconnect>", "INFO" )

    local cmds = split( args[0], "|", true )

    // TODO: yield for each cmd
    foreach( cmd in cmds ) {

        switch ( cmd ) {

            case "create":
                NavUtils.CreateNav()
                break
            case "cleanup":
                NavUtils.SubdivideLargeAreas()
                NavUtils.DisconnectUnreachableAreas()
                break
            case "subdivide":
                NavUtils.SubdivideLargeAreas()
                break
            case "disconnect":
                NavUtils.DisconnectUnreachableAreas()
                break
            default:
                DebugLog.LOG_PRINT( "Usage: .wnav <create|cleanup|subdivide|disconnect>", "INFO" )
                break
        }
    }
}

function VSWeather::ChatCommands::failed( params, args ) {

    DebugDrawClear()
    foreach( job in FailedJobs ) {

        // DebugLog.LOG_PRINT( "Failed job: " + job.area_name + " -> " + job.particle_name + " at " + job.trace_start.ToKVString(), "INFO" )

        local radius = CONFIG.WeatherSystems[ job.particle_name ].radius
        DebugDrawBox( job.trace_end + Vector( 0, 0, CONFIG.WeatherSystems[ job.particle_name ].travel_distance * 0.5 ), Vector( -radius, -radius, -radius ), Vector( radius, radius, radius ), 255, 0, 0, 0, 60.0 )
    }
}

// HELP COMMAND MUST BE DEFINED LAST!
function VSWeather::ChatCommands::help( params, args ) {

    local str = ""
    foreach( cmd, _ in VSWeather.ChatCommands ) {
        str += "\n.w" + cmd
    }
    DebugLog.LOG_PRINT( "Available commands:" + str, "INFO" )
}

function VSWeather::Events::OnGameEvent_player_say( params ) {

    local text = params.text

    if ( text[0] != '.' || !(1 in text) || text[1] != 'w' )
        return

    local args = split( text, " ", true )

    local cmd = args[0].slice( 2 )

    if ( !(cmd in ChatCommands) ) {

        DebugLog.LOG_PRINT( "Unknown command: " + text, "INFO" )
        return
    }

    args.remove( 0 )

    // if ( !weather_complete ) {

    //     DebugLog.LOG_PRINT( "Weather is not complete yet.", "INFO" )
    //     return
    // }

    ChatCommands[ cmd ]( params, args )
}

__CollectGameEventCallbacks( VSWeather.Events )

function VSWeather::_OnCreate() {

    SendToConsole( "sv_cheats 1; mp_waitingforplayers_cancel 1;" )
    EntFire( "team_round_timer", "Pause" )
    VSWeather.InitNav()
    DebugLog.LOG_PRINT( "Loaded!", "INFO" )
}
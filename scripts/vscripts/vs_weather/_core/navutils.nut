VSWeather.NavUtils <- {}

VSWeather.NavUtils.MAX_AREAS_PER_TICK   <- 1000
VSWeather.NavUtils.last_subdivide_len   <- 0

function VSWeather::NavUtils::GetNavAreasLargerThan( areas, size_threshold = VSWeather.CONFIG.NAV_SUBDIVIDE_LARGE_AREA_THRESHOLD ) {

    return areas.filter( @( _, area ) area.IsValid() && area instanceof CTFNavArea && area.GetSizeX() * area.GetSizeY() > size_threshold )
}

function VSWeather::NavUtils::SnapToAreaAndRunCommand( pos, command ) {

    if ( pos instanceof CTFNavArea || pos instanceof CBaseEntity )
        pos = pos.GetCenter()

    // SendToConsole fires asynchronously? set origin/angles in the same command instead
    // PLAYER.SetAbsOrigin( pos )
    // PLAYER.SnapEyeAngles( QAngle( 90, 0, 0 ) )

    // put us in noclip and don't touch any trigger_hurts/etc
    PLAYER.SetSolid( SOLID_NONE )
    PLAYER.SetSolidFlags( FSOLID_NOT_SOLID )
    PLAYER.AddFlag( FL_DONTTOUCH|FL_NOTARGET )
    PLAYER.SetCollisionGroup( COLLISION_GROUP_DEBRIS )

    PLAYER.SetMoveType( MOVETYPE_NOCLIP, MOVECOLLIDE_DEFAULT )
    SendToConsole( "setpos " + pos.ToKVString() + ";setang 90 0 0;" + command )
}

function VSWeather::NavUtils::SubdivideLargeAreas() {

    local SnapToAreaAndRunCommand = SnapToAreaAndRunCommand

    local large_areas = GetNavAreasLargerThan( AllAreas )

    local i = 0
    Generators.StartGenerator( Generators.DeferredUnrollIterable( large_areas, 0.05, function() {

        local area = large_areas[i]
        i++

        if ( area.IsValid() )
            SnapToAreaAndRunCommand( area.GetCenter(), "nav_subdivide" )
    }, 
    null, // onyield
    function ( _ ) { // oncomplete

        large_areas = NavUtils.GetNavAreasLargerThan( AllAreas )
        local large_areas_len = large_areas.len()

        if ( large_areas_len != NavUtils.last_subdivide_len ) {

            NavUtils.last_subdivide_len  = large_areas_len
            DebugLog.LOG_PRINT( "More areas to subdivide! Running again...", "DEBUG" )
            NavUtils.SubdivideLargeAreas()
            return
        }

        if ( large_areas_len )
            DebugLog.LOG_PRINT( "Some large areas failed to subdivide! Avoiding infinite loop... (last: " + NavUtils.last_subdivide_len + " cur: " + large_areas_len + ")", "WARNING" )

        DebugLog.LOG_PRINT( "Subdividing areas complete!", "INFO" )
        SendToConsole( "nav_save" )
        PLAYER.ForceRegenerateAndRespawn()
    }))
}
// nav area disconnect: Modified from scripts by Mikusch & ficool2
function VSWeather::NavUtils::DisconnectUnreachableAreas() {

    local valid_areas = AllAreas.filter( @( _, area ) area.IsValid() && area instanceof CTFNavArea )

    Generators.StartGenerator( Generators.DeferredForEach( valid_areas, MAX_AREAS_PER_TICK, function( _, area ) {

        if ( !area.IsValid() )
            return

        local center = area.GetCenter()
        for ( local dir = 0; dir < NUM_DIRECTIONS; dir++ ) {

            local adjacentAreas = {}
            area.GetAdjacentAreas( dir, adjacentAreas )

            foreach ( j, adjacentArea in adjacentAreas ) {

                local pos  = area.ComputePortal( adjacentArea, dir )
                local to   = pos + Vector()
                local from = pos + Vector()
                to.z = adjacentArea.GetZ( to )
                from.z = area.GetZ( from )

                to = adjacentArea.GetClosestPointOnArea( to )

                if ( (to.z - from.z ) > STEP_HEIGHT )
                {
                    area.DebugDrawFilled( 0, 255, 0, 32, 15, true, 0 )
                    adjacentArea.DebugDrawFilled( 255, 0, 0, 32, 15, true, 0 )
                    DebugDrawLine( from, to, 255, 255, 255, true, 15 )

                    area.Disconnect( adjacentArea )
                    DebugLog.LOG_PRINT( format( "Disconnected area #%d from area #%d", area.GetID(), adjacentArea.GetID() ), "DEBUG" )
                }
            }
        }
    }, 
    null, // onyield
    function ( _ ) { // oncomplete

        SendToConsole( "nav_save" )
        DebugLog.LOG_PRINT( "Disconnecting areas complete!", "INFO" )
    }))
}

function VSWeather::NavUtils::NavGenerator() {

    local walkable_points = []
    local e
    foreach( i, ent in [ "info_player_teamspawn", "item_teamflag", "team_control_point", "trigger_capture_area", "func_capturezone" ] ) {

        yield !printl( "collecting: " + ent )

        while ( e = FindByClassname( e, ent ) )
            walkable_points.append( e )
    }

    switch ( MapLogic.GetGamemode() ) {

        case "PL":
        case "PLR":
            walkable_points.extend( MapLogic.GetPayloadTracks().keys() )
        break

        case "MVM":
            walkable_points.extend( MapLogic.GetBombPathMarkers().keys() )
        break
    }

    walkable_points.apply( @(point) point.GetCenter() )

    local points_len = walkable_points.len()

    DebugLog.LOG_PRINT( "WALKABLE POINTS: " + points_len, "INFO" )

    local generate_delay = 0.0
    // Process spawn points for current arena
    foreach( i, point in walkable_points ) {

        // if ( !point ) continue

        generate_delay += 0.01
        EntFire( "__vs_weather", "RunScriptCode", format( @"

            local origin = Vector( %f, %f, %f )
            NavUtils.SnapToAreaAndRunCommand( origin, `nav_mark_walkable` )
            local progress = ( %d + 1 )
            local total = %d
            local str = `Marking Nav Point: ` + origin.ToKVString() + ` Progress: ` + progress + ` / ` + total
            DebugLog.LOG_PRINT( str, `DEBUG` )

        ", point.x, point.y, point.z, i, points_len ), generate_delay )

        yield true
    }

    // Schedule nav generation
    EntFire( "__vs_weather", "RunScriptCode", @"

        DebugLog.LOG_PRINT( `Areas marked! Generating nav...`, `INFO` )
        SendToConsole( `nav_generate` )

    ", generate_delay + 0.5 )

    yield true


    AddThinkToEnt( PLAYER, null )
}

function VSWeather::NavUtils::CreateNav() {

    GetAllAreas( AllAreas )

    if ( AllAreas.len() && FileToString( "__vsweather_nav_cleanup_and_save" ) == "1" ) {

        DebugLog.LOG_PRINT( "Nav already generated! Cleaning up existing nav instead...", "WARNING" )
        SendToConsole( "nav_edit 1;")
        SubdivideLargeAreas()
        DisconnectUnreachableAreas()
        StringToFile( "__vsweather_nav_cleanup_and_save", "0" )
        return 
    }

    DebugLog.LOG_PRINT( "Creating nav.  Run this command again after nav_generate to clean it up and save it!", "INFO" )

    // host_thread_mode changes when nav_generate runs/completes
    SendToConsole( "nav_edit 0;" )

    local scope = PLAYER.GetScriptScope() || (PLAYER.ValidateScriptScope(), PLAYER.GetScriptScope())

    local gen = NavGenerator()

    function NavThink() {

        if ( gen.getstatus() != "dead" )
            return resume gen, 0.05

        // else if ( GetInt( "host_thread_mode" ) )
        StringToFile( "__vsweather_nav_cleanup_and_save", "1" )
        SetPropString( PLAYER, "m_iszScriptThinkFunction", "" )

        return INT_MAX
    }
    scope.NavThink <- NavThink
    AddThinkToEnt( PLAYER, "NavThink" )
}

function CTFNavArea::ComputePortal( to, dir ) {

    local center = Vector()
    local nwCorner = GetCorner( NORTH_WEST )
    local seCorner = GetCorner( SOUTH_EAST )
    local to_nwCorner = to.GetCorner( NORTH_WEST )
    local to_seCorner = to.GetCorner( SOUTH_EAST )

    if ( dir == NORTH || dir == SOUTH )
    {
        if ( dir == NORTH )
            center.y = nwCorner.y
        else
            center.y = seCorner.y

        local left = ( nwCorner.x > to_nwCorner.x ) ? nwCorner.x : to_nwCorner.x
        local right = ( seCorner.x < to_seCorner.x ) ? seCorner.x : to_seCorner.x

        if ( left < nwCorner.x )
            left = nwCorner.x
        else if ( left > seCorner.x )
            left = seCorner.x

        if ( right < nwCorner.x )
            right = nwCorner.x
        else if ( right > seCorner.x )
            right = seCorner.x

        center.x = ( left + right ) * 0.5
    }
    else
    {
        if ( dir == WEST )
            center.x = nwCorner.x
        else
            center.x = seCorner.x

        local top = ( nwCorner.y > to_nwCorner.y ) ? nwCorner.y : to_nwCorner.y
        local bottom = ( seCorner.y < to_seCorner.y ) ? seCorner.y : to_seCorner.y

        if ( top < nwCorner.y )
            top = nwCorner.y
        else if ( top > seCorner.y )
            top = seCorner.y

        if ( bottom < nwCorner.y )
            bottom = nwCorner.y
        else if ( bottom > seCorner.y )
            bottom = seCorner.y

        center.y = ( top + bottom ) * 0.5
    }

    center.z = GetZ( center )
    return center
}

function CTFNavArea::GetClosestPointOnArea( pos ) {

    local close = Vector()
    local nwCorner = GetCorner( NORTH_WEST )
    local seCorner = GetCorner( SOUTH_EAST )
    close.x = ( pos.x - nwCorner.x >= 0 ) ? pos.x : nwCorner.x
    close.x = ( close.x - seCorner.x >= 0 ) ? seCorner.x : close.x
    close.y = ( pos.y - nwCorner.y >= 0 ) ? pos.y : nwCorner.y
    close.y = ( close.y - seCorner.y >= 0 ) ? seCorner.y : close.y
    close.z = GetZ( close )
    return close
}

// if ( FileToString( "__vsweather_nav_cleanup_and_save" ) == "1" ) {

//     EntFire(" __vs_weather", "RunScriptCode", @"
    
//         VSWeather.NavUtils.SubdivideLargeAreas()
//         VSWeather.NavUtils.DisconnectUnreachableAreas()
//         StringToFile( `__vsweather_nav_cleanup_and_save`, `0` )
//     ", 1.0)
// }
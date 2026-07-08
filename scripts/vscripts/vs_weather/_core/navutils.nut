VSWeather.NavUtils <- {

    STEP_HEIGHT = 18
    MAX_AREAS_PER_TICK = 150
    LARGE_AREA_THRESHOLD = 90000 // 900x900 units

    function SnapToAreaAndRunCommand( player, pos, command ) {

        if ( pos instanceof CTFNavArea || pos instanceof CBaseEntity )
            pos = pos.GetCenter()

        player.SetAbsOrigin( pos )
        player.SnapEyeAngles( QAngle( 90, 0, 0 ) )
        SendToConsole( command )
    }

    function SubdivideLargeAreas( player ) {

        local large_areas = AllAreas.filter( @( _, area ) area instanceof CTFNavArea && area.GetSizeX() * area.GetSizeY() > VSWeather.NavUtils.LARGE_AREA_THRESHOLD )

        local i = 0
        Generators.StartGenerator( Generators.DeferredForEach( large_areas, 1, function( _, area ) {

            i++
            printl( player + " : " + area )

            if ( area.IsValid() )
                VSWeather.NavUtils.SnapToAreaAndRunCommand( player, area, "nav_subdivide" )
        }, 
        @( _, _ ) DebugLog.LOG_PRINT( "Subdividing large areas... ( " + i + "/" + large_areas.len() + " )", "INFO" ),
        @( _ ) DebugLog.LOG_PRINT( "Subdividing large areas complete!", "INFO" ) ) )
    }
    // nav area disconnect: Modified from scripts by Mikusch & ficool2
    function DisconnectAreas() {

        GetAllAreas( AllAreas )

        function DisconnectAreaGenerator() {

            foreach ( i, area in AllAreas ) {

                if ( area instanceof CBaseEntity ) continue

                local center = area.GetCenter()
                for ( local dir = 0; dir < NUM_DIRECTIONS; dir++ ) {

                    local adjacentAreas = {}
                    area.GetAdjacentAreas( dir, adjacentAreas )

                    foreach ( j, adjacentArea in adjacentAreas ) {

                        local pos = area.ComputePortal( adjacentArea, dir )
                        local from = pos + Vector()
                        local to = pos + Vector()
                        from.z = area.GetZ( from )
                        to.z = adjacentArea.GetZ( to )

                        to = adjacentArea.GetClosestPointOnArea( to )

                        if ( (to.z - from.z ) > STEP_HEIGHT )
                        {
                            area.DebugDrawFilled( 0, 255, 0, 32, 15, true, 0 )
                            adjacentArea.DebugDrawFilled( 255, 0, 0, 32, 15, true, 0 )
                            DebugDrawLine( from, to, 255, 255, 255, true, 15 )

                            area.Disconnect( adjacentArea )
                            DebugLog.LOG_PRINT( format( "Disconnected area #%d from area #%d", area.GetID(), adjacentArea.GetID() ), "INFO" )
                        }
                    }
                }

                if ( !( i % MAX_AREAS_PER_TICK ) )
                    yield true
            }
        }

        local gen = DisconnectAreaGenerator()

        function ThinkTable::DisconnectAreaThink() {

            if ( gen.getstatus() == "dead" ) {
                SendToConsole("nav_save")
                DebugLog.LOG_PRINT( "Nav cleaned up and saved!", "INFO" )
                delete ThinkTable.DisconnectAreaThink
                return 1
            }

            resume gen
            return 0.05
        }
    }

    function NavGenerator() {

        local player = GetListenServerHost()

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
            EntFireByHandle( player, "RunScriptCode", format( @"

                local origin = Vector( %f, %f, %f )
                VSWeather.NavUtils.SnapToAreaAndRunCommand( self, origin, `nav_mark_walkable` )
                local progress = ( %d + 1 )
                local total = %d
                local str = `Marking Nav Point: ` + origin.ToKVString() + ` Progress: ` + progress + ` / ` + total
                VSWeather.DebugLog.LOG_PRINT( str, `DEBUG` )

            ", point.x, point.y, point.z, i, points_len ), generate_delay, null, null )

            yield true
        }

        // Schedule nav generation
        EntFire( "__vs_weather", "RunScriptCode", @"

            DebugLog.LOG_PRINT( `Areas marked! Generating nav...`, `INFO` )
            SendToConsole( `nav_generate` )

        ", generate_delay + 0.5 )

        yield true


        AddThinkToEnt( player, null )
    }

    function CreateNav() {

        local player = GetListenServerHost()
        if ( FileToString( "__vsweather_nav_cleanup_and_save" ) == "1" ) {

            SubdivideLargeAreas( player )
            DisconnectAreas()
            StringToFile( "__vsweather_nav_cleanup_and_save", "0" )
            return 
        }

        DebugLog.LOG_PRINT( "Creating nav.  Run this command again after nav_generate to clean it up and save it!", "INFO" )

        EntFire( "team_round_timer", "Pause" )

        // host_thread_mode changes when nav_generate runs/completes
        SendToConsole( "nav_edit 0; developer 1" )

        player.SetMoveType( MOVETYPE_NOCLIP, MOVECOLLIDE_DEFAULT )

        local scope = player.GetScriptScope() || (player.ValidateScriptScope(), player.GetScriptScope())

        local gen = NavGenerator()

        function NavThink() {

            if ( gen.getstatus() != "dead" )
                return resume gen

            // else if ( GetInt( "host_thread_mode" ) )
            StringToFile( "__vsweather_nav_cleanup_and_save", "1" )
            SetPropString( player, "m_iszScriptThinkFunction", "" )

            return -1
        }
        scope.NavThink <- NavThink
        AddThinkToEnt( player, "NavThink" )
    }
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

if ( FileToString( "__vsweather_nav_cleanup_and_save" ) == "1" ) {

    EntFire(" __vs_weather", "RunScriptCode", @"
    
        NavUtils.SubdivideLargeAreas( GetListenServerHost() )
        NavUtils.DisconnectAreas()
        StringToFile( `__vsweather_nav_cleanup_and_save`, `0` )
    ")
}
VSWeather.MapLogic <- {}

// reusable return buffer for entity lists
VSWeather.MapLogic.return_buffer <- {}

VSWeather.MapLogic.logic_ents <- {

    tf_logic_koth                    = "KOTH"
    tf_logic_arena                   = "Arena"
    // tf_logic_medieval                = "Medieval"
    // tf_logic_bounty_mode             = "Bounty"
    tf_logic_hybrid_ctf_cp           = "CTF/CP"
    tf_logic_mann_vs_machine         = "MvM"
    tf_logic_multiple_escort         = "PLR"
    tf_logic_special_delivery_mode   = "SD"
    tf_logic_robot_destruction_mode  = "RD"
    tf_logic_player_destruction_mode = "PD"
}

function VSWeather::MapLogic::GetGamemode() {

    local ent
    while ( ent = FindByClassname( ent, "tf_logic*" ) )
        if ( ent.GetClassname() in logic_ents )
            return logic_ents[ ent.GetClassname() ]

    while ( ent = FindByClassname( ent, "team_train_watcher" ) )
        return "PL"

    while ( ent = FindByClassname( ent, "passtime_logic" ) )
        return "PASS"

    while ( ent = FindByClassname( ent, "item_teamflag" ) ) {

        for ( local spawner; spawner = FindByClassname( spawner, "info_powerup_spawn" ); )
            return "Mannpower"

        for ( local cap; cap = FindByClassname( cap, "func_capturezone" ); )
            return "CTF"
    }

    return split( MAPNAME, "_" )[0].toupper()
}

function VSWeather::MapLogic::GetPayloadTracks() {
    
    return_buffer.clear()

    // helper to recursively run through branching tracks
    local function _altpath( first, altpath, altname ) {

        if ( altpath ) {

            return_buffer[ altpath ] <- altpath.GetName()

            if ( altpath = GetPropEntity( altpath, "m_paltpath" ) )
                return_buffer[ altpath ] <- altpath.GetName()                    

            while ( altpath = GetPropEntity( altpath, "m_pnext" ) ) {

                if ( altpath == first )
                    continue

                return_buffer[ altpath ] <- altpath.GetName()
            }
        }

        if ( altname != "" )
            while ( altpath = FindByName( altpath, altname ) )
                return_buffer[ altpath ] <- altname
    }

    // grab the tracks from the watcher
    for ( local watcher; watcher = FindByClassname( watcher, "team_train_watcher" ); ) {

        local first, last, prev, altpath, altname
        local first_name = GetPropString( watcher, "m_iszStartNode" )
        local last_name = GetPropString( watcher, "m_iszGoalNode" )
        // grab the start and end tracks
        while ( last  = FindByName( last,  last_name  ) ) break
        while ( first = FindByName( first, first_name ) ) break

        if ( !(first && last) )
            DebugLog.LOG_PRINT( "Error getting payload tracks:\n\n" + watcher.GetName() + "\nStart: " + first_name + "\nEnd: " + last_name + "\n\nYour path_tracks might be misconfigured?", "ERROR" )

        prev  = GetPropEntity( last, "m_pprevious" )

        altpath = GetPropEntity( prev, "m_paltpath" )
        altname = GetPropString( prev, "m_altName" )

        foreach ( path in [ altpath, first, last, prev ] ) {

            if ( !path || !path.IsValid() )
                continue

            altpath = GetPropEntity( path, "m_paltpath" )
            altname = GetPropString( path, "m_altName" )
            _altpath( first, altpath, altname )
        }

        if ( prev ) return_buffer[ prev ] <- prev.GetName()

        // iterate backwards to the starting node
        while ( prev = GetPropEntity( prev, "m_pprevious" ) ) {

            return_buffer[ prev ] <- prev.GetName()
            altpath = GetPropEntity( prev, "m_paltpath" )
            altname = GetPropString( prev, "m_altName" )
            _altpath( first, altpath, altname )
        }
    }
    return return_buffer
}

// look for trigger_capture_areas instead of team_control_point
// this is the place players actually stand to capture
// the team_control_point model could be somewhere else
function VSWeather::MapLogic::GetCaptureAreas() {

    return_buffer.clear()

    for ( local capture_zone; capture_zone = FindByClassname( capture_zone, "trigger_capture_area" ); )
        return_buffer[ capture_zone ] <- capture_zone.GetName()

    return return_buffer
}

function VSWeather::MapLogic::GetSpectatorCameras() {

    return_buffer.clear()

    local camera
    foreach( ent in [ "info_observer_point", "point_devshot_camera", "game_intro_viewpoint" ] )
        while ( camera = FindByClassname( camera, ent ) )
            return_buffer[ camera ] <- camera.GetName()

    return return_buffer
}

function VSWeather::MapLogic::GetBombPathMarkers( ... ) {

    return_buffer.clear()

    if ( !vargv.len() )
        vargv.append( "models/props_mvm/robot_hologram.mdl" )

    foreach( model in vargv )
        for( local marker; marker = FindByModel( marker, model ); )
            return_buffer[ marker ] <- marker.GetName()

    return return_buffer
}
VSWeather.MapLogic <- {

    // reusable return buffer for entity lists
    return_buffer = {}

    function GetPayloadTracks() {
        
        return_buffer.clear()

        // reuse some variables in the main loop to avoid gc pressure
        local first, last, prev, altpath, altname

        // helper to recursively run through branching tracks
        local function _altpath() {

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

            // grab the start and end tracks
            while ( first = FindByName( first, GetPropString( watcher, "m_iszStartNode" ) ) ) break
            while ( last =  FindByName( last, GetPropString( watcher, "m_iszGoalNode"   ) ) ) break

            Assert( (first && last), "Start and end tracks not found in team_train_watcher.  Your path_tracks might be misconfigured?" )

            prev  = GetPropEntity( last, "m_pprevious" )

            altpath = GetPropEntity( prev, "m_paltpath" )
            altname = GetPropString( prev, "m_altName" )

            foreach ( path in [ altpath, first, last, prev ] ) {

                if ( !path || !path.IsValid() )
                    continue

                altpath = GetPropEntity( path, "m_paltpath" )
                altname = GetPropString( path, "m_altName" )
                _altpath()
            }

            if ( prev ) return_buffer[ prev ] <- prev.GetName()

            // iterate backwards to the starting node
            while ( prev = GetPropEntity( prev, "m_pprevious" ) ) {

                return_buffer[ prev ] <- prev.GetName()
                altpath = GetPropEntity( prev, "m_paltpath" )
                altname = GetPropString( prev, "m_altName" )
                _altpath()
            }
        }
        return return_buffer
    }

    // look for trigger_capture_areas instead of team_control_point
    // this is the place players actually stand to capture
    // the team_control_point model could be somewhere else
    function GetCaptureAreas() {

        return_buffer.clear()

        for ( local capture_zone; capture_zone = FindByClassname( capture_zone, "trigger_capture_area" ); )
            return_buffer[ capture_zone ] <- capture_zone.GetName()

        return return_buffer
    }

    function GetSpectatorCameras() {

        return_buffer.clear()

        local camera
        foreach( ent in [ "info_observer_point", "point_devshot_camera", "game_intro_viewpoint" ] )
            while ( camera = FindByClassname( camera, ent ) )
                return_buffer[ camera ] <- camera.GetName()

        return return_buffer
    }

    function GetBombPathMarkers( ... ) {

        return_buffer.clear()

        if ( !vargv.len() )
            vargv.append( "models/props_mvm/robot_hologram.mdl" )

        foreach( model in vargv )
            for( local marker; marker = FindByModel( marker, model ); )
                return_buffer[ marker ] <- marker.GetName()

        return return_buffer
    }
}
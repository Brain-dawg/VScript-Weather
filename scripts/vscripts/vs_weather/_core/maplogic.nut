VSWeather.MapLogic <- {

    function GetPayloadTracks() {
        
        local tracks = {}
        local first, last, prev, altpath, altname

        local function _altpath() {

            if ( altpath ) {

                tracks[ altpath ] <- altpath.GetName()

                if ( altpath = GetPropEntity( altpath, "m_paltpath" ) )
                    tracks[ altpath ] <- altpath.GetName()                    

                while ( altpath = GetPropEntity( altpath, "m_pnext" ) ) {

                    if ( altpath == first )
                        continue

                    tracks[ altpath ] <- altpath.GetName()
                }
            }

            if ( altname != "" )
                while ( altpath = FindByName( altpath, altname ) )
                    tracks[ altpath ] <- altname
        }

        // grab the tracks from the watcher
        for ( local watcher; watcher = FindByClassname( watcher, "team_train_watcher" ); ) {

            // grab the start and end tracks
            while ( first = FindByName( first, GetPropString( watcher, "m_iszStartNode" ) ) )
                break
            while ( last = FindByName( last, GetPropString( watcher, "m_iszGoalNode" ) ) )
                break

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

            if ( prev )
                tracks[ prev ] <- prev.GetName()

            // iterate backwards to the starting node
            while ( prev = GetPropEntity( prev, "m_pprevious" ) ) {

                if ( prev == first ) {

                    // keep start/end and link them together to keep working bot logic
                    // delete every track in between
                    SetPropEntity( first, "m_pnext", last )
                    continue
                }

                tracks[ prev ] <- prev.GetName()
                altpath = GetPropEntity( prev, "m_paltpath" )
                altname = GetPropString( prev, "m_altName" )
                _altpath()
            }
        }

        return tracks
    }
}
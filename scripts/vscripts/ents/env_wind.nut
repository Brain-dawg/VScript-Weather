// UNFINISHED
// this was an experiment to recreate env_wind entirely in vscript
// it was not a good idea

IncludeScript( "weather/ents/basescriptentity" )

class CScriptEnvWind extends CBaseScriptEntity {

    gust_active = false

    _thinks    = null
    _gustStart = null
    _gustEnd   = null

    m_EnvWindShared = {

        m_iMinWind           = 0
        m_iMaxWind           = 0
        m_iMinGust           = 0
        m_iMaxGust           = 0
        m_iWindDir           = 0
        m_iInitialWindDir    = 0
        m_iGustDirChange     = 0
        m_iWindSeed          = 0
        m_flStartTime        = 0.0
        m_flMinGustDelay     = 0.0
        m_flMaxGustDelay     = 0.0
        m_flWindSpeed        = 0.0
        m_flGustDuration     = 0.0
        m_flInitialWindSpeed = 0.0

        m_OnGustStart        = null
        m_OnGustEnd          = null

        CEnvWindWindThink    = null
    }
    
    constructor( name = "__wind" + UniqueString(), table = null ) {

        if ( table && typeof table == "table" && "m_EnvWindShared" in table ) {

            foreach( prop, val in table.m_EnvWindShared )
                m_EnvWindShared[prop] = val

            delete table.m_EnvWindShared
        }

        base.constructor( "env_wind", table )

        NetProps.SetPropString( self, "m_iName", name )

        local _class = this.getclass()
        scope.CScriptEnvWind <- _class
        scope.CScriptEnvWindWindThink <- CScriptEnvWindWindThink

        self.ConnectOutput( "OnGustStart", "m_OnGustStart" )
        self.ConnectOutput( "OnGustEnd", "m_OnGustEnd" )
        AddThinkToEnt( self, "CScriptEnvWindWindThink" )

        foreach( prop, val in m_EnvWindShared )
            if ( val != null )
                m_EnvWindShared[prop] = GetSetProp( prop )

        m_EnvWindShared.m_flStartTime = Time()
        m_EnvWindShared.m_OnGustStart = m_OnGustStart
        m_EnvWindShared.m_OnGustEnd = m_OnGustEnd
    }

    function GetSetProp( prop, ... ) {

        local type = prop[2]
        local prefix = 0 in vargv ? "SetProp" : "GetProp"

        if ( !(prop in m_EnvWindShared) && prop in BaseProps )
            ret = NetProps[prefix + type].acall([this, self, prop.slice( 16 )].extend(vargv) )

        prop = "m_EnvWindShared." + prop

        local args = [this, self, prop]
        local ret

        try {
            if ( type == 'f' )
                ret = NetProps[prefix + "Float"].acall(args.extend(vargv) )
            else if ( type == 'i' )
                ret = NetProps[prefix + "Int"].acall(args.extend(vargv) )
            else
                ret = prop

            m_EnvWindShared[prop] = ret

        } catch ( e ) {}

        return ret
        
    }

    function CScriptEnvWindWindThink() {

        foreach ( think in CScriptEnvWind._thinks )
            think()

        return -1
    }

    function OnWindUpdate( func ) {

        if ( !CScriptEnvWind._thinks )
            CScriptEnvWind._thinks = [ func.bindenv( scope ) ]
        else
            CScriptEnvWind._thinks.append( func.bindenv( scope ) )
    }

    function OnGustStart( func ) {

        if ( !CScriptEnvWind._gustStart )
            CScriptEnvWind._gustStart = [ func.bindenv( scope ) ]
        else
            CScriptEnvWind._gustStart.append( func.bindenv( scope ) )
    }
    
    function OnGustEnd( func ) {

        if ( !CScriptEnvWind._gustEnd )
            CScriptEnvWind._gustEnd = [ func.bindenv( scope ) ]
        else
            CScriptEnvWind._gustEnd.append( func.bindenv( scope ) )
    }

    function m_OnGustStart() {

        CScriptEnvWind.gust_active = true

        if ( !CScriptEnvWind._gustStart || !CScriptEnvWind._gustStart.len() )
            return
        
        foreach ( func in CScriptEnvWind._gustStart )
            func()
    }
    
    function m_OnGustEnd() {

        CScriptEnvWind.gust_active = false

        if ( !CScriptEnvWind._gustEnd || !CScriptEnvWind._gustEnd.len() )
            return
        
        foreach ( func in CScriptEnvWind._gustEnd )
            func()
    }

    // function _SetupProps() {

    //     local temp = {}
    //     NetProps.GetTable( self, 0, temp )
    //     NetProps.GetTable( self, 1, m_EnvWindShared )

    //     foreach ( prop, val in temp.m_EnvWindShared ) {
    //        m_EnvWindShared[prop] <- val
    //     }
    //     m_EnvWindShared = m_EnvWindShared.filter( @( prop, val ) 15 in prop && prop[15] == '.' && startswith( prop, "m_EnvWindShared." ) )
    // }
}
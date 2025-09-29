IncludeScript( "weather/ents/basescriptentity" )

class CScriptEnvWind extends CBaseScriptEntity {

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

        m_OnGustEnd          = null
        m_OnGustStart        = null

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

        AddThinkToEnt( self, "CScriptEnvWindWindThink" )

        foreach( prop, val in m_EnvWindShared )
            if ( val != null )
                m_EnvWindShared[prop] = GetSetProp( prop )

        m_EnvWindShared.m_flStartTime = Time()
    }

    function CScriptEnvWindWindThink() {

        CScriptEnvWind.m_flWindSpeed = Time()
        OnWindUpdate( CScriptEnvWindWindThink )

        return -1
    }

    function OnWindUpdate( func = null ) {

        if ( func )
            func.call( scope )
    }

    function GetSetProp( prop, ... ) {

        local type = prop[2]
        local prefix = 0 in vargv ? "SetProp" : "GetProp"

        if ( !(prop in m_EnvWindShared) && prop in BaseProps )
            ret = NetProps[prefix + type].acall([this, self, prop.slice( 16 )].extend(vargv) )

        prop = "m_EnvWindShared." + prop

        local args = [this, self, prop]
        local ret

        printl( self )

        try {
            if ( type == 'f' )
                ret = NetProps[prefix + "Float"].acall(args.extend(vargv) )
            else if ( type == 'i' )
                ret = NetProps[prefix + "Int"].acall(args.extend(vargv) )
            else
                ret = prop

            m_EnvWindShared[prop] = ret

        } catch ( e ) {
            error( e + self + "\n" )
        }

        return ret
        
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
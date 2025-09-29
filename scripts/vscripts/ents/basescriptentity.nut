class CBaseScriptEntity {

    self  = null
    scope = null
    BaseProps = null

    constructor( classname, table = null ) {

        if ( table && typeof table == "table" )
            self = SpawnEntityFromTable( classname, table )
        else 
            self = Entities.CreateByClassname( classname )

        self.ValidateScriptScope()
        scope = self.GetScriptScope()
        scope.CBaseScriptEntity <- this

        NetProps.SetPropBool( self, "m_bForcePurgeFixedupStrings", true )

        if ( !( "m_iTeamNum" in this ) )
            _SetupProps()
    }

    // set up all CBaseEntity netprops
    function _SetupProps() {

        // grab worldspawn and some other random entity, look for matching netprops/datamaps
        local base1 = Entities.First()
        local base2 = Entities.Next( base1 )

        // combine netprop/datamaps
        local base1_props = {}
        local base1_temp  = {}
        NetProps.GetTable( base1, 0, base1_props )
        NetProps.GetTable( base1, 1, base1_temp )

        local base2_props = {}
        local base2_temp  = {}
        NetProps.GetTable( base2, 0, base2_props )
        NetProps.GetTable( base2, 1, base2_temp )

        foreach ( prop, val in base1_temp )
            base1_props[prop] <- val

        foreach ( prop, val in base2_temp )
            base2_props[prop] <- val

        // merge shared props
        BaseProps = base1_props.filter( @( prop, val ) prop in base2_props )
    }
}
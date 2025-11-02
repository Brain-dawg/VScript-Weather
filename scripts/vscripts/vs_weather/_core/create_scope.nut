
/******************************************************************************************************
 * Namespacing wrapper for creating self-contained "extension" vscripts.                              *
 *                                                                                                    *
 * - Creates a global reference to the dummy entity scope to use as a "namespace" for your extension. *
 * - All code is cleaned up when the dummy entity is killed                                           *
 * - Built-in "_OnDestroy" callback for handling root/misc scoped vars related to our "extension"     *
 * - Optional think function setup for easily managing multiple concurrent thinks.                    *
 ******************************************************************************************************/

/**
 * @function ___CREATE_SCOPE
 *
 * @param {string} name
 *        Target name of the entity.  A common prefix for your extension scopes is recommended
 *        common prefixes allow for e.g. `ent_fire __myext_* Kill` to clean up everything at once.
 *
 * @param {table} namespace
 *        Root table reference to the scope. This is your extension's namespace.
 *
 * @param {handle} entity_ref
 *        Optional root table reference to the entity.
 *
 * @param {string|function} think_func
 *        Set a a think function for this entity/scope, depending on argument type:
 *        - string: creates a new think function that iterates over an internal table named "ThinkTable", allowing for multiple concurrent thinks that can be added/removed dynamically.
 *        - function: Sets the think function directly, useful for "permanent" thinks where you don't need to dynamically add/remove multiple concurrent thinks.
 *
 * @param {string} [classname]
 *        (Optional) Overrides the dummy entity classname with a custom one before spawning.
 *        Default: "logic_autosave"
 * 
 *        NOTE: the default "logic_autosave" has its classname changed to a random preserved entity after spawning ("entity_saucer").  This does not apply to classname overrides...
 *        ... If you use a non-preserved entity, this namespace will only exist for the duration of the current round, and will be deleted when the underlying entity is killed...
 *        ... Search "*s_PreserveEnts[]" in the SDK codebase for a list of preserved entity classnames.
 * 
 *        WARNING: If you are overriding this to "move_rope" or "keyframe_rope" to make it a "real" preserved entity, know that some servers will kill these entities indiscriminately to save edicts...
 *        ... we use "entity_saucer" because it is a more obscure entity that server owners will likely forget about and not kill it.
 * 
 *        WARNING: This is not a general purpose entity spawner! the underlying entity only exists as a script scope bucket to dump our code into.
 *
 * @param {boolean} [table_auto_delegate]
 *        (Optional) Automatically call .setdelegate(namespace) on all inserted tables.  This effectively "flattens" every table into the main namespace.
 *        - MyTable.Table1.MyFunc() can be called as MyTable.MyFunc() instead, or MyFunc() if we're calling from inside MyTable's scope.
 *        - Set this to false if it's causing headaches/naming collisions.
 *        Default: true
 *
 * @return {table}
 *        Returns a table containing the entity and scope references.
 */

/*****************
 * EXAMPLE USAGE *
 *****************/

/*****************************************************************************************************
 * - Create a new "namespace" from an entity scope, name the entity "__myext_ent"                    *
 * - Internally spawns a dummy entity and runs "::MyExtension <- ent.GetScriptScope()"               *
 *                                                                                                   *
 * ___CREATE_SCOPE( "__myext_ent", "MyExtension", "MyExtensionEntity", "MyExtensionThink" )          *
 *                                                                                                   *
 * // Namespace is now available as "::MyExtension"                                                  *
 *                                                                                                   *
 * // Create a function scoped to our extension                                                      *
 * function MyExtension::MyFunction() {                                                              *
 *                                                                                                   *
 *     __DumpScope( 0, this )                                                                        *
 * }                                                                                                 *
 * MyExtension.MyFunction()                                                                          *
 *                                                                                                   *
 * // Add a think function scoped to our extension that iterates all players.  Runs automatically    *
 * function MyExtension::ThinkTable::IterateAllPlayers() {                                           *
 *                                                                                                   *
 *     for ( local i = 1, player; i <= MAX_CLIENTS; i++ )                                            *
 *         if ( player = PlayerInstanceFromIndex( i ) )                                              *
 *             printl( player )                                                                      *
 * }                                                                                                 *
 *                                                                                                   *
 * // _OnDestroy will fire automatically when the dummy entity is killed                             *
 * // you can use this to clean up any game events or global variables                               *
 * ::MyExtensionGlobalVar <- "blah"                                                                  *
 * function MyExtension::_OnDestroy() {                                                              *
 *                                                                                                   *
 *     delete ::MyExtensionGlobalVar                                                                 *
 *     printl( "Zombies ate your extension! Goodbye cruel world..." )                                *
 * }                                                                                                 *
 *                                                                                                   *
 * // Sub-components of your extension                                                               *
 * MyExtension.PlayerHandler <- {                                                                    *
 *                                                                                                   *
 *     function ChangeAllPlayerTeams( team = TEAM_SPECTATOR ) {                                      *
 *                                                                                                   *
 *         foreach ( player in GetAllPlayers() )                                                     *
 *             player.ForceChangeTeam( team, true )                                                  *
 *     }                                                                                             *
 * }                                                                                                 *
 *                                                                                                   *
 * // alternative syntax                                                                             *
 * function MyExtension::PlayerHandler::FindPlayerByName( name ) {                                   *
 *                                                                                                   *
 *     foreach ( player in GetAllPlayers() )                                                         *
 *         if ( Convars.GetClientConvarValue( "name", player.entindex() ) == name )                  *
 *             return player                                                                         *
 * }                                                                                                 *
 *                                                                                                   *
 * // functions can be called from their parent scope for better perf and less ugly code             *
 * // this can cause naming conflicts for different functions with identical names                   *
 * // if you want to disable this behavior, set `table_auto_delegate` to false                       *
 * MyExtension.FindPlayerByName()                                                                    *
 *                                                                                                   *
 * MyExtensionEntity.Kill() // delete the entity and the global ::MyExtension reference alongside it *
 * EntFire( "__myext_ent", "Kill" ) // same thing                                                    *
 *****************************************************************************************************/

/*****************
 * !!IMPORTANT!! *
 *****************/

/*************************************************************************************************
 * Because this uses an entity scope as a base and not a blank table, built-in vars              *
 * like 'self' and '__vname' will exist and will point to the dummy entity                       *
 * You will need to .bindenv() or .call() to re-scope these functions if you (e.g.):             *
 *                                                                                               *
 * 1. define a function in your namespace that references 'self'                                 *
 * 2. try to call that function from the scope of another entity using MyExtension.MyFunction(). *
 *                                                                                               *
 * 'self' here will not point to the target entity, it will point to the dummy entity instead.   *
 ************************************************************************************************/

if ( !( "___active_scopes___" in ROOT ) )
	::___active_scopes___ <- {}

function ___CREATE_SCOPE( name = "", namespace = null, entity_ref = null, think_func = null, classname = null, table_auto_delegate = true ) {

	local ent = FindByName( null, name )

	if ( !ent || !ent.IsValid() ) {

		ent = CreateByClassname( classname || "logic_autosave" )
		SetPropString( ent, STRING_NETPROP_NAME, name )
		ent.ValidateScriptScope()
		::DispatchSpawn( ent )
	}

	SetPropBool( ent, STRING_NETPROP_PURGESTRINGS, true )
	___active_scopes___[ ent ] <- namespace

	// don't spawn an actual preserved ent to save an edict
	if ( !classname )
		SetPropString( ent, "m_iClassname", "entity_saucer" )

	local ent_scope = ent.GetScriptScope()

	local namespace  =  namespace  || format( "%s_Scope", name )
	local entity_ref =  entity_ref || format( "%s_Entity", name )
	ROOT[ namespace ]  <- ent_scope
	ROOT[ entity_ref ] <- ent

	ent_scope.setdelegate( {

		function _newslot( k, v ) {

			if ( k == "_OnDestroy" && !_OnDestroy )
				_OnDestroy = v.bindenv( ent_scope )

			ent_scope.rawset( k, v )

            if ( typeof v == "function" ) {

                if ( k == "_OnCreate" )
                    _OnCreate.call( ent_scope )

                // fix anonymous function declarations in perf counter
                else if ( !v.getinfos().name )
                    compilestring( format( @" local _%s = %s.bindenv( this ); function %s() { _%s() }", k, k, k, k ) ).call( ent_scope )
            }

            // delegate variables to ent_scope for less verbose writing
            // e.g. Scope.MyTable.MyFunc() can be written instead as Scope.MyFunc() in some places
            else if ( typeof v == "table" && table_auto_delegate )
                v.setdelegate( ent_scope )
		}

	}.setdelegate( {

			parent     = ent_scope.getdelegate()
			id         = ent.GetScriptId()
			index      = ent.entindex()
			_OnDestroy = null

			function _get( k ) { return parent[k] }

			function _delslot( k ) {

				if ( k == id ) {

					if ( _OnDestroy )
						_OnDestroy()

                    // delete root references to ourself
					if ( namespace in ROOT )
						delete ROOT[ namespace ]

					if ( entity_ref in ROOT )
						delete ROOT[ entity_ref ]
				}

				delete parent[k]
			}
		} )
	)

	if ( think_func ) {

		// function passed, Add the think function directly to the entity
		if ( endswith( typeof think_func, "function" ) ) {

			local think_name = think_func.getinfos().name || format( "%s_Think", name )

			ent_scope[ think_name ] <- think_func
			AddThinkToEnt( ent, think_name )
			return
		}

        // String passed, set up think table and assume we're defining the actual function later
		ent_scope.ThinkTable <- {}

		compilestring( format( "function %s() { foreach( func in ThinkTable ) func.call( this ); return -1 }", think_func ) ).call( ent_scope )

		AddThinkToEnt( ent, think_func )
	}

	return { Entity = ent, Scope = ent_scope }
}
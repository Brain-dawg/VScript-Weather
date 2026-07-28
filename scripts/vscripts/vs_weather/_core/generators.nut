/******************************************************************************************************************************************************
 * GENERATOR FUNCTIONS                                                                                                                                *
 *                                                                                                                                                    *
 * standalone library for using generators+thinks to defer code execution to later frames.                                                            *
 * Finally, callback hell for VScript                                                                                                                 *
 *                                                                                                                                                    *
 * We rely heavily on deferring execution to later frames so we can run very expensive code on very large maps without worrying about SQQuerySuspend. *
 * ( multiple hull/ray traces on every nav area in the map in one big loop )                                                                          *
 * have the think iterate over a table of generators, run X number of iterations per frame, remove them when they're dead.                            *
 ******************************************************************************************************************************************************/

VSWeather.Generators <- {}

VSWeather.Generators.active_generators <- {}

function VSWeather::Generators::StartGenerator( func ) { active_generators[ func ] <- true }
function VSWeather::Generators::StopGenerator( func ) { active_generators[ func ] = false; }
function VSWeather::Generators::ToggleGenerators() { foreach( func, state in active_generators ) { active_generators[ func ] = !state } }

function VSWeather::Generators::GeneratorChain( steps ) {

    function executeStep(i) {

        DebugLog.LOG_PRINT( "executeStep called with i=" + i + ", step_names.len()=" + steps.len(), "DEBUG" )

        if ( !(i in steps) ) {
            DebugLog.LOG_PRINT( "Generator chain complete!", "DEBUG" )
            return  // Chain complete
        }

        local step_config = steps[i];
        DebugLog.LOG_PRINT( "Executing generator step: " + (i+1), "DEBUG" )
        // Extract parameters from the step configuration
        local generator_factory = step_config[0];  // Function that creates the generator
        local custom_oncomplete = step_config.len() ? step_config[step_config.len()-1] : null;

        // Create the chaining oncomplete function
        local function chainComplete( ... ) {

            DebugLog.LOG_PRINT( "Generator step " + (i+1) + " completed!", "DEBUG" )
            if ( custom_oncomplete )
                custom_oncomplete.acall( [this].extend(vargv) );
            executeStep( i + 1 );  // Continue to next step
        }

        // Create and start the generator with the chaining complete callback
        local generator = generator_factory( chainComplete );
        DebugLog.LOG_PRINT( "Started generator: " + generator, "DEBUG" )

        StartGenerator( generator );
    }

    executeStep( 0 );
}

// Unrolls X number of function calls to EntFire RunScriptCode commands
function VSWeather::Generators::DeferredUnrollIterable( iterable, delay_tick = SINGLE_TICK, func = null, onyield = null, oncomplete = null ) {

    Assert( func, "null function passed to DeferredUnroll (argument 4)" )
    local func_info = func.getinfos()

    local run_cmd = "parameters" in func_info && 1 in func_info.parameters ? "RunScriptCode" : "CallScriptFunction"

    local func_name = (func_info.name || "") + UniqueString( "Generator_DeferredUnroll" )
    // start on next frame
    yield 1

    local dummy = CreateByClassname( "logic_autosave" )
    local entity_name = func_name + "_entity"
    SetPropString( dummy, STRING_NETPROP_NAME, entity_name )
    ::DispatchSpawn( dummy )
    SetPropString( dummy, "m_iClassname", "move_rope" )
    SetPropBool( dummy, STRING_NETPROP_PURGESTRINGS, true )

    dummy.ValidateScriptScope()
    local scope = dummy.GetScriptScope()
    scope[ func_name ] <- func
    scope.iterable <- iterable

    local iter_len = iterable.len()
    local strings = array( iter_len + 1, "" )
    local delay = 0

    for ( local i = 0; i < iter_len; delay += delay_tick, i++ ) {

        local func_call = run_cmd == "RunScriptCode" ? func_name + "("+i+")" : func_name
        strings[i] = func_call
        EntFire( entity_name, run_cmd, func_call, delay )
    }

    function _oncomplete() {

        if ( oncomplete ) 
            oncomplete( iterable );

        foreach( str in strings ) {

            local tmp = CreateByClassname( "logic_autosave" )
            SetPropString( tmp, STRING_NETPROP_NAME, str )
            ::DispatchSpawn( tmp )
            SetPropBool( tmp, STRING_NETPROP_PURGESTRINGS, true )
            tmp.Kill()
        }
        EntFire( entity_name, "Kill" )
    }
    scope._oncomplete <- _oncomplete.bindenv( this )
    local func_delete = "_oncomplete(); delete " + func_name
    strings[iter_len] = func_delete
    EntFire( entity_name, "RunScriptCode", func_delete, delay + SINGLE_TICK )
}

function VSWeather::Generators::DeferredUnrollSimple( num_calls, delay_tick = SINGLE_TICK, func = null, onyield = null, oncomplete = null ) {
    DeferredUnrollIterable( array( num_calls ), delay_tick, func, onyield, oncomplete )        
}
// generic loop, iters_per_frame number of function calls per think
function VSWeather::Generators::DeferredFor( max, iters_per_frame, func, onyield = null, oncomplete = null ) {

    // start on next frame
    yield 1

    for ( local i = 0; i < max; i++ ) {

        func( i )

        if ( !( i % iters_per_frame ) ) {

            if ( onyield ) onyield()

            yield 1
        }
    }

    if ( oncomplete ) oncomplete()
    return
}

// generic for each loop, iters_per_frame number of function calls per think
function VSWeather::Generators::DeferredForEach( iterable, iters_per_frame, func, onyield = null, oncomplete = null ) {

    // start on next frame
    yield 1

    local i = 0

    foreach( k, v in iterable ) {

        i++
        func( k, v )

        if ( !( i % iters_per_frame ) ) {

            if ( onyield ) onyield( k, v )

            yield 1
        }
    }

    if ( oncomplete ) oncomplete( iterable )
    return
}

// non-blocking loop, will exit when the provided exit function returns false
function VSWeather::Generators::NonBlockingLoop( run, iters_per_frame, func, onyield = null, oncomplete = null ) {

    // start on next frame
    yield 1
    local i = 0

    while ( run() ) {

        i++
        func()

        if ( !( i % iters_per_frame ) ) {

            if ( onyield ) onyield()

            yield 1
        }

    }

    if ( oncomplete ) oncomplete()
    return
}

function VSWeather::ThinkTable::RunGenerators() {

    if ( !Generators.active_generators.len() )
        return

    // __DumpScope( 0, Generators.active_generators )

    foreach( gen, running in Generators.active_generators ) {

        if ( gen.getstatus() == "dead" ) {

            delete Generators.active_generators[ gen ]
            continue
        }

        else if ( running ) {
            
            if ( gen.getstatus() != "dead" ) resume gen

            // function ResumeGenerator() { if ( gen.getstatus() != "dead" ) resume gen }
            // ResumeGenerator()
            // EntFireByHandle( self, "CallScriptFunction", "ResumeGenerator", -1, null, null )
        }
    }
}
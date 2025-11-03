/******************************************************************************************************************************************************
 * GENERATOR FUNCTIONS                                                                                                                                *
 *                                                                                                                                                    *
 * wrapper for handling the boilerplate of using generators+thinks to defer code execution to later frames.                                           *
 * Finally, callback hell for VScript                                                                                                                 *
 *                                                                                                                                                    *
 * We rely heavily on deferring execution to later frames so we can run very expensive code on very large maps without worrying about SQQuerySuspend. *
 * ( multiple hull/ray traces on every nav area in the map in one big loop )                                                                          *
 * have the think iterate over a table of generators, run X number of iterations per frame, remove them when they're dead.                            *
 ******************************************************************************************************************************************************/

VSWeather.Generators <- {

    active_generators = {}

    function StartGenerator( func ) { active_generators[ func ] <- true }
    function StopGenerator( func ) { active_generators[ func ] = false; }
    function ToggleGenerators() { foreach( func, state in active_generators ) { active_generators[ func ] = !state } }

    // simple Entity I/O, unrolls X number of function calls to EntFire CallScriptFunction commands 
    function DeferredUnrollSimple( num_calls, delay_mult, func, onyield = @() true ) {

        local func_name = func.getinfos().name || UniqueString( "Generator_DeferredUnrollSimple" )
        VSWeather[ func_name ] <- func

        // start on next frame
        yield 1

        local entity_name = "__vs_weather"
        for ( local i = 0, delay = SINGLE_TICK; i < num_calls; delay += (SINGLE_TICK * delay_mult), i++ ) {

            EntFire( entity_name, "CallScriptFunction", func_name, delay )

            if ( !( i % iters_per_frame ) ) {

                if ( onyield )
                    onyield( i )

                yield 1
            }
        }

        PZI_Util.ScriptEntFireSafe( entity_name, "delete " + func_name, delay + SINGLE_TICK )
    }

    // generic loop, iters_per_frame number of function calls per think
    function DeferredFor( max, iters_per_frame, func, onyield = null, oncomplete = null ) {

        // start on next frame
        yield 1

        for ( local i = 0; i < max; i++ ) {

            func( i )

            if ( !( i % iters_per_frame ) ) {

                if ( onyield )
                    onyield( i )

                yield 1
            }
        }

        if ( oncomplete )
            oncomplete()
        return
    }

    // generic for each loop, iters_per_frame number of function calls per think
    function DeferredForEach( iterable, iters_per_frame, func, onyield = null, oncomplete = null ) {

        // start on next frame
        yield 1

        local i = 0

        foreach( k, v in iterable ) {

            i++
            func( k, v )

            if ( !( i % iters_per_frame ) ) {

                if ( onyield )
                    onyield( k, v )

                yield 1
            }
        }

        if ( oncomplete )
            oncomplete( iterable )
        return
    }

    // non-blocking loop, will exit when the provided exit function returns false
    function NonBlockingLoop( exit, iters_per_frame, func, onyield = null, oncomplete = null ) {

        // start on next frame
        yield 1
        local i = 0

        while ( exit() ) {

            i++
            func( i )

            if ( !( i % iters_per_frame ) ) {

                if ( onyield )
                    onyield( i )

                yield 1
            }

        }

        if ( oncomplete )
            oncomplete()

        return
    }
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
            
            if ( gen.getstatus() != "dead" )
                resume gen

            // function ResumeGenerator() { if ( gen.getstatus() != "dead" ) resume gen }
            // ResumeGenerator()
            // EntFireByHandle( self, "CallScriptFunction", "ResumeGenerator", -1, null, null )
        }
    }
}
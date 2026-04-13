// This is where you configure your weather system
VSWeather.CONFIG <- {

    /******************
     *                *
     * BASIC SETTINGS *
     *                *
     ******************/
    /********************************************************************************
     * maximum number of info_particle_systems to spawn                             *
     *                                                                              *
     * This is not the absolute number of spawned particles                         *
     * If detected valid areas < MAX_WEATHER_SYSTEMS,                               *
     * the number of spawned particles will be reduced to the number of valid areas *
     ********************************************************************************/
    MAX_WEATHER_SYSTEMS = 256

    /*******************************************************************************************
     * Ignore prop_static/prop_dynamic/anything using a studiomdl                              *
     * This is so small rocks/trees/etc don't invalidate potential weather system locations    *
     * However, if you have e.g. a prop_static shack/entire building, this will cause problems *
     *******************************************************************************************/
    IGNORE_PROPS = true

    WeatherSystems = {

        /****************************************
         * define particle systems by name here *
         ****************************************/
        // env_sandstorm_002_angry = {

        //     /******************************************************************************
        //      * "safe" radius of this effect before it will clip into surrounding geometry *
        //      ******************************************************************************/
        //     radius = 300

        //     /**********************************************************************************
        //      * distance from the particle system origin -> the point where the particle stops *
        //      **********************************************************************************/
        //     travel_distance = 650

        //     /**********************************************************************************
        //      * entity keyvalues passed to the info_particle_system entity                     *
        //      * for valid keyvalues, create one in hammer and disable SmartEdit.               *
        //      * or see VDC page: https://developer.valvesoftware.com/wiki/Info_particle_system *
        //      **********************************************************************************/
        //     keyvalues = {

        //         /************************************************************
        //          * if this is not set, targetname will be set to:           *
        //          * "__vs_weather_<particle name>_<area id>".                *
        //          * <area id> is the nav area ID associated with this effect *
        //          ************************************************************/
        //         // targetname      = "my_rain_test"

        //         /************************************
        //          * start the particle system active *
        //          ************************************/
        //         start_active    = true

        //         /****************************************************************************
        //          * Many configs set tf_particles_disable_weather 0 for performance reasons. *
        //          * NOTE: weirdly the example env_rain_002_256 will not be affected by this? *
        //          ****************************************************************************/
        //         flag_as_weather = true
        //     }
        // }
        env_rain_002_256 = {

            radius = 300
            travel_distance = 650
            keyvalues = {
                start_active = true
                flag_as_weather = true
            }
        }
    }

    /***************************
     *                         *
     * ADVANCED SETTINGS BELOW *
     *                         *
     ***************************/

    /******************************************************************
     * Per-frame loop settings for low power performance tuning       *
     * If you're having issues hitting SQQuerySuspend                 *
     * or client crashes due to the DebugDraw spam                    *
     * lower these values until it stops                              *
     *                                                                *
     * These are MAXIMUM settings.                                    *
     * If MAX_WEATHER_SYSTEMS = 30, SPAWN_PARTICLES > 30 does nothing *
     ******************************************************************/
    ITERS_PER_FRAME = {

        TRACE_JOB_INIT  = 150 // number of trace jobs to initialize per frame
        TRACE_JOB_RUN   = 50 // number of TraceLine/TraceLineEx/TraceHull function calls per frame (and some other expensive things)
        SPAWN_PARTICLES = 50  // number of particle systems to spawn per frame
    }
}
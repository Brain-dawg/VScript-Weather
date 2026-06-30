// This is where you configure your weather system
VSWeather.CONFIG <- {

    /******************
     * BASIC SETTINGS *
     ******************/

    /********************************************************************************
     * maximum number of info_particle_systems to spawn                             *
     *                                                                              *
     * This is not the absolute number of spawned particles                         *
     * If detected valid areas < MAX_WEATHER_SYSTEMS,                               *
     * the number of spawned particles will be reduced to the number of valid areas *
     ********************************************************************************/
    MAX_WEATHER_SYSTEMS = 300


    /*******************************************************************************************
     * Ignore all displacements (terrain)                                                      *
     *                                                                                         *
     * If all underground/indoors sections are closed off by world brushes or static props     *
     * (e.g. no caves), setting this to true will allow all rain to clip through displacements *
     * If your map allows this, this may alleviate some "dead spots" with no rain.             *
     * This will completely break e.g. tc_hydro caves.  Be careful                             *
     *******************************************************************************************/
    IGNORE_DISPLACEMENTS = false


    /*********************************************************************
     * Ignore all props (static/dynamic)                                 *
     *                                                                   *
     * Same as above, but for props.                                     *
     * Don't use this if your map has e.g. prop_static shacks/roofs/etc. *
     *********************************************************************/
    IGNORE_PROPS = false

    /**********************************************************************************
     * Adds forgiveness to the trace system                                           *
     * This is intended to ignore smaller decorations (roof trims, fence roofs, etc)  *
     * Higher values = larger objects get ignored                                     *
     *                                                                                *
     * A little weird under the hood:                                                 *
     * this value is subtracted from comparison between 2 TraceLine results           *
     * 0-100% forgiveness is between 0.0 and 2.0, not 0.0 and 1.0                     *
     * TRACE_FORGIVENESS = 1.0 = 50% forgiveness, 2.0 = ignore everything             *
     **********************************************************************************/
    TRACE_FORGIVENESS = 0.05

    WeatherSystems = {

        /******************************************************************************
         * define particle systems by name here                                       *
         * TODO: While there is code to support multiple particle systems...          *
         * it doesn't work correctly.  Only one particle system is supported for now. *
         ******************************************************************************/
        env_rain_002_256 = {

            /******************************************************************************
             * "safe" radius of this effect before it will clip into surrounding geometry *
             ******************************************************************************/
            radius = 264

            /**********************************************************************************
             * distance from the particle system origin -> the point where the particle stops *
             **********************************************************************************/
            travel_distance = 650

            /**********************************************************************************
             * entity keyvalues passed to the info_particle_system entity                     *
             * for valid keyvalues, create one in hammer and disable SmartEdit.               *
             * or see VDC page: https://developer.valvesoftware.com/wiki/Info_particle_system *
             **********************************************************************************/
            keyvalues = {

                /************************************************************
                 * if this is not set, targetname will be set to:           *
                 * "__vs_weather_<particle name>_<area id>".                *
                 * <area id> is the nav area ID associated with this effect *
                 ************************************************************/
                // targetname      = "my_rain_test"

                /************************************
                 * start the particle system active *
                 ************************************/
                start_active    = true

                /****************************************************************************
                 * Many configs set tf_particles_disable_weather 0 for performance reasons. *
                 * NOTE: weirdly the example env_rain_002_256 will not be affected by this? *
                 ****************************************************************************/
                flag_as_weather = true
            }
        }
        // env_sandstorm_002_angry = {

        //     radius = 300
        //     travel_distance = 650
        //     keyvalues = {
        //         angles          = QAngle( 45, 180, 0 )
        //         start_active    = true
        //         flag_as_weather = true
        //     }
        // }
    }

    /***************************
     * ADVANCED SETTINGS BELOW *
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

        // number of nav areas to process per frame
        NAV_AREAS  = 600
        // number of TraceLine/TraceLineEx/TraceHull function calls per-job per frame (and some other expensive things)
        // this doesn't need to be divisible by 12 but is recommended.
        TRACE_FUNCS = 12 * 64
        // number of concurrent trace jobs running per frame
        // not implemented, use TRACE_FUNCS instead.
        // TRACE_JOBS = 4
        // number of particle systems to spawn per frame
        SPAWN_PARTICLES = 100
    }
}
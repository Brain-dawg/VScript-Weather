// This is where you configure your weather system
// WARNING: DO NOT DELETE KEYS FROM THIS FILE, YOU WILL BREAK THINGS!
// there are no defaults if the expected config keys don't exist!
VSWeather.CONFIG <- {

    /******************
     * BASIC SETTINGS *
     ******************/

    /*****************************************************************************
    * define particle systems by name here                                       *
    * TODO: While there is code to support multiple particle systems...          *
    * it doesn't work correctly.  Only one particle system is supported for now. *
    ******************************************************************************/
    WeatherSystems = {

        env_rain_002_256 = {

            /******************************************************************************
             * "safe" radius of this effect before it will clip into surrounding geometry *
             ******************************************************************************/
            radius = 260

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

    /****************************************************************************************
     * Ignore all textures with $translucent 1 or $alpha 1.  Does not apply to $alphatest 1 *
     *                                                                                      *
     * Only use this if your map has e.g. metal fencing and no glass roofs/windows.         *
     ****************************************************************************************/
    IGNORE_TRANSLUCENT = false

    /***************************************************
     * Trace mask for what shouldn't be rained through *
     ***************************************************/
    TRACE_MASK = MASK_OPAQUE|CONTENTS_HITBOX|CONTENTS_WINDOW
    
    /************************************************************
     * Ignore certain textures when tracing for weather effects *
     * Useful for skipping e.g. non-$translucent fences         *
     ************************************************************/
    IGNORE_THESE_TEXTURES = {

        "moon/moon_floor_grate01": true
        "moon/moonbase_grate001": true
        "metal/metalgrate013a": true
        "egypt/barbed_wire_fence_01": true
        // supports trailing wildcards for e.g. grate and grate_a
        "models/props_sunshine/cafe_table001_grate*" : true
    }

    /**********************************************************************************
     * Adds forgiveness to the trace system                                           *
     * This is intended to ignore smaller decorations (roof trims, fence roofs, etc)  *
     * Higher values = larger objects get ignored.                                    *
     **********************************************************************************/
    TRACE_FORGIVENESS = 1.0

    /**************************************************************
     * If a nav's total area size is larger than this value in HU *
     * the navmesh helpers for subdividing will run on it.        *
     **************************************************************/
    NAV_SUBDIVIDE_LARGE_AREA_THRESHOLD = 200*200

    /**************************************************************
     * Filename for the vmf instance output                       *
     * NOTE: this is ignored for server config (.nut file) output *
     **************************************************************/
    SAVE_FILENAME = MAPNAME + "_weather_particles"

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
        NAV_AREAS  = 1200
        // number of TraceLine/TraceLineEx/TraceHull function calls per-job per frame (and some other expensive things)
        // this doesn't need to be divisible by 12 but is recommended.
        TRACE_FUNCS = 12*128
        // number of particle systems to spawn per frame
        SPAWN_PARTICLES = 300
    }
}
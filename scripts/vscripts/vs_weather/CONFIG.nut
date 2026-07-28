/*****************************************************************************************************************************************
 * WARNING: DO NOT DELETE KEYS FROM THIS FILE, YOU WILL BREAK THINGS!                                                                    *
 * there are no defaults if the expected config keys don't exist!                                                                        *
 *                                                                                                                                       *
 * Script Usage:                                                                                                                         *
 * 1. add your particle systems to the WeatherSystems table (replace the example particle).  Configure other settings below (if needed). *
 * 2. run `script_execute vscript_weather` in console to load the script in-game                                                         *
 * 3. If your map has no navmesh, type `.wnav create`, repeat step 2 on map reload, then type `.wnav cleanup`                            *
 * 4. type `.wstart` to trace the map and spawn particles                                                                                *
 * 5a. FOR MAPPERS: type `.wsave instance` to save particles to a .vmf instance                                                          *
 * 5b. FOR SERVER OWNERS: type `.wsave script` to save particles to a .nut file.  Open this file to see how to use in your server cfg    *
 * 6. for updating the config and re-running, type `.wreload` or `.wreset` in chat, repeat step 4                                        *
 *                                                                                                                                       *
 * if you are having issues with "Script terminated by SQQuerySuspend":                                                                  *
 * - if it happens very early after running `.wstart`, try setting ALL_NAV_CORNERS_SLOW to false                                         *
 * - if it happens randomly in the middle of tracing, reduce TRACE_FUNCS (bottom of this file)                                           *
 *****************************************************************************************************************************************/

VSWeather.CONFIG <- {

    /*****************************************************************************
    * define particle systems by name here                                       *
    * TODO: While there is code to support multiple particle systems...          *
    * it doesn't work correctly.  Only one particle system is supported for now. *
    ******************************************************************************/
    WeatherSystems = {

        // example particle system
        env_rain_002_256 = {

            /******************************************************************************
             * "safe" radius of this effect before it will clip into surrounding geometry *
             ******************************************************************************/
            radius = 256

            /*********************************************************************
             * multiplier for the radius check for nearby particles              *
             * particles spawning too far apart? try setting this to <= 0.85     *
             *********************************************************************/
            overlap_mult = 0.85

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

                /**************************************************
                 * if this is not set, targetname will be set to: *
                 * "__vs_weather_<particle name>_<origin xyz>".   *
                 **************************************************/
                // targetname      = "my_rain_test"

                /************************************
                 * start the particle system active *
                 ************************************/
                start_active    = true

                /****************************************************************************
                 * Many configs set tf_particles_disable_weather 0 for performance reasons. *
                 ****************************************************************************/
                flag_as_weather = true
            }
        }
    }

    /******************
     * BASIC SETTINGS *
     ******************/

    MISC = {

        /*******************************************************************************
        * maximum number of info_particle_systems to spawn                             *
        *                                                                              *
        * This is not the absolute number of spawned particles                         *
        * If detected valid areas < MAX_WEATHER_SYSTEMS,                               *
        * the number of spawned particles will be reduced to the number of valid areas *
        ********************************************************************************/
        MAX_WEATHER_SYSTEMS = 300

        /****************************************************************************
        * If true, append the xyz location of the particle system to the targetname *
        * Only works for custom targetnames, see targetname note in WeatherSystems  *
        *****************************************************************************/
        UNIQUE_TARGETNAMES = false

        /*************************************************************
        * If a nav's total area size is larger than this value in HU *
        * the navmesh helpers for subdividing will run on it.        *
        **************************************************************/
        NAV_SUBDIVIDE_LARGE_AREA_THRESHOLD = 200*200

        /**************************************************************
        * Filename for the vmf instance output                       *
        * NOTE: this is ignored for server config (.nut file) output *
        **************************************************************/
        SAVE_FILENAME = MAPNAME + "_weather_particles"
    }

    /******************
     * TRACE SETTINGS *
     ******************/

    /************************************************************************************************************
     * WARNING: The following settings will fire TraceLineEx if set to true, rather than simple TraceLine calls *
     * This will slow down the tracing process significantly, reduce TRACE_FUNCS to compensate.                 *
     *                                                                                                          *
     * IGNORE_DISPLACEMENTS = true                                                                              *
     * IGNORE_PROPS = true                                                                                      *
     * IGNORE_TRANSLUCENT = true                                                                                *
     * IGNORE_THESE_TEXTURES = { ... } // putting anything in this table will fire TraceLineEx                  *
     * IGNORE_THESE_SURFACE_PROPS = { ... } // putting anything in this table will fire TraceLineEx             *
     * AVOID_THESE_ENTS = { ... } // putting anything in this table will fire TraceLineEx                       *
     ************************************************************************************************************/

    TRACING = {

        /*************************************************************************************
         * All four nav corners will be tested for particle placement, as well as the center *
         * Setting this to true will 4x the amount of traces, meaning 4x the time to finish  *
         * Most maps will see significantly better particle placement though.                *
         * Takes upwards of a minute on pl_enclosure, you've been warned.                    *
         *                                                                                   *
         * BUG: This may trigger SQQuerySuspend on large navs.                               *
         * If you are having issues with this, set to false and use .wnav subdivide instead  *
         *************************************************************************************/
        ALL_NAV_CORNERS_SLOW = true

        /*********************************************************************************
        * Adds forgiveness to the trace system                                           *
        * This is intended to ignore smaller decorations (roof trims, railings, etc)     *
        * Higher values = larger objects get ignored.                                    *
        **********************************************************************************/
        TRACE_FORGIVENESS = 1.0

        /**************************************************
        * Trace mask for what shouldn't be rained through *
        * See constants.nut for some pre-defined masks.   *
        ***************************************************/
        TRACE_MASK = MASK_OPAQUE|CONTENTS_HITBOX|CONTENTS_WINDOW|CONTENTS_MONSTER

        /******************************************************************************
        * Ignore all displacements (terrain)                                          *
        *                                                                             *
        * If your map allows this, this may alleviate some "dead spots" with no rain. *
        * This will completely break e.g. tc_hydro caves.  Be careful                 *
        *******************************************************************************/
        IGNORE_DISPLACEMENTS = false

        /*********************************************************************
        * Ignore all props (static/dynamic)                                 *
        *                                                                   *
        * Same as above, but for props.                                     *
        * Don't use this if your map has e.g. prop_static shacks/roofs/etc. *
        *********************************************************************/
        IGNORE_PROPS = false

        /***************************************************************************************
        * Ignore all textures with $translucent 1 or $alpha 1.  Does not apply to $alphatest 1 *
        *                                                                                      *
        * Only use this if your map has e.g. lots of metal fencing and no glass roofs/windows. *
        ****************************************************************************************/
        IGNORE_TRANSLUCENT = false

        /***********************************************************
        * Ignore certain textures when tracing                     *
        * Useful for skipping e.g. brush fences                    *
        *                                                          *
        * WARNING: This is extremely limited... Only world brushes *
        * VScript tracing doesn't support displacements/props      *
        * See IGNORE_THESE_SURFACE_PROPS for a possible workaround *
        ************************************************************/
        IGNORE_THESE_TEXTURES = {
            // "moon/moon_floor_grate01": true
            // "moon/moonbase_grate001": true
            // "metal/metalgrate013a": true
            // "egypt/barbed_wire_fence_01": true
        }

       /*****************************************************************
        * Ignore certain surface props when tracing                     *
        * Useful if your map only uses e.g. "rock" or "dirt" surfaces   *
        * on displacements/props that can be safely rained through      *
        *****************************************************************/
        IGNORE_THESE_SURFACE_PROPS = {
            // "rock": true
            // "dirt": true
        }

        /***********************************************************************************
         * WARNING: EXTREMELY SLOW! PROBABLY DON'T USE THIS!                               *
         *                                                                                 *
         * Don't spawn particles in this area if it will collide with these named entities *
         * Also accepts classnames, e.g. "func_breakable"                                  *
         ***********************************************************************************/
        AVOID_THESE_ENTS = {
            
            // thundermountain finale brushes
            // "explode_pre_brushes": true
            // "explode_post_brushes": true
            // "cap_c3_cart_tip_brush": true
        }
    }

    /************************
     * PERFORMANCE SETTINGS *
     ************************/
    ITERS_PER_FRAME = {

        /***************************************************************************************************
         * Main loop, AKA the slow part:                                                                   *
         * number of TraceLine/TraceLineEx/TraceHull function calls per frame (and other expensive things) *
         * set this as high as you can until perf warnings are safely between 70-90ms                      *
         * >100ms will hit SQQuerySuspend                                                                  *
         ***************************************************************************************************/
        TRACE_FUNCS = 800

        /********************************************
         * number of nav areas to process per frame *
         ********************************************/
        NAV_AREAS  = 800

        /**********************************************************
         * number of particle systems to spawn per frame          *
         **********************************************************/
        SPAWN_PARTICLES = 50
    }
}
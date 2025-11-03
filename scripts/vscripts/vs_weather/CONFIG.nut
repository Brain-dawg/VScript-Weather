// This is where you configure your weather system
VSWeather.CONFIG <- {

    // maximum number of info_particle_systems to spawn
    MAX_WEATHER_SYSTEMS = 64

    WeatherSystems = {

        // define particle systems by name here
        env_rain_002_256 = {

            // "safe" radius of this effect before it will clip into surrounding geometry
            radius = 300

            // distance from the particle system origin -> the point where the particle stops
            travel_distance = 650

            // entity keyvalues passed to the info_particle_system entity
            // Create an info_particle_system in hammer and disable SmartEdit to see valid keyvalues.
            // or see VDC page: https://developer.valvesoftware.com/wiki/Info_particle_system
            keyvalues = {

                // if this is not set, targetname will be set to "__vs_weather_<particle name>_<area id>".  area id is the nav area ID associated with this effect
                // targetname      = "my_rain_test"

                // start the particle system active
                start_active    = true

                // disabled for testing purposes
                flag_as_weather = false
            }
        }
    }
}
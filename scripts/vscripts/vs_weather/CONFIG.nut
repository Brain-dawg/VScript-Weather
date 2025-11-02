// This is where you configure your weather system
VSWeather.CONFIG <- {

    // maximum number of info_particle_systems to spawn
    MAX_WEATHER_SYSTEMS = 64

    WeatherSystems = {

        env_rain_002_256 = { // add particle system name as table key

            radius = 256 // "safe" radius of this effect before it will clip into surrounding geometry
            travel_distance = 592 // maximum distance the particles will travel (for rain, this is the distance from the particle system origin -> the point where the rain particle stops)
        }
    }
}
VSWeather.Util <- {

    function AnglesToVector( angles ) {

        local pitch = angles.x * Pi / 180.0
        local yaw = angles.y * Pi / 180.0
        local x = cos( pitch ) * cos( yaw )
        local y = cos( pitch ) * sin( yaw )
        local z = sin( pitch )
        return Vector( x, y, z )
    }
}
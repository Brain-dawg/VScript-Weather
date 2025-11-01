VSWeather.DebugLog <- {

    // Logging
    LOG_DEBUG   = "[VS WEATHER INFO]" 
    LOG_DEBUG   = "\x0722FF22[VS WEATHER DEBUG]\x07FBECCB" 
    LOG_WARNING = "\x07FFFF66[VS WEATHER WARNING]\x07FBECCB" 
    LOG_ERROR   = "\x07FF0000[VS WEATHER ERROR]\x07FBECCB" 
    LOG_FATAL   = "\x07FF0000[VS WEATHER FATAL]\x07FBECCB" 

    function LOG_PRINT( message, severity = "INFO" ) {

        if ( !GetInt( "developer" ) && severity != "INFO" )
            return

        local log_const = "LOG_" + severity
        if ( log_const in CONST )
            ClientPrint( null, 3, CONST[log_const] + message )

        printl( "VS WEATHER LOG: " + message )
    }
}
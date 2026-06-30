VSWeather.DebugLog <- {

    // Logging
    LOG_INFO   = "\x0704C6DB[VS WEATHER INFO]\x07FBECCB "
    LOG_DEBUG   = "\x0722FF22[VS WEATHER DEBUG]\x07FBECCB "
    LOG_WARNING = "\x07FFFF66[VS WEATHER WARNING]\x07FBECCB "
    LOG_ERROR   = "\x07FF0000[VS WEATHER ERROR]\x07FBECCB "
    LOG_FATAL   = "\x07FF0000[VS WEATHER FATAL]\x07FBECCB "

    function LOG_PRINT( message, severity = "INFO" ) {

        if ( !GetInt( "developer" ) && severity != "INFO" )
            return

        ClientPrint( null, 3, this["LOG_" + severity] + message )

        Assert( ( severity != "ERROR" && severity != "FATAL" ), message )

        printl( "[VS WEATHER] " + message )
    }
}
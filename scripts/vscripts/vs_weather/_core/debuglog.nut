VSWeather.DebugLog <- {}

// Logging
VSWeather.DebugLog.LOG_INFO    <- "\x0704C6DB[VSWEATHER]\x07FBECCB "
VSWeather.DebugLog.LOG_DEBUG   <- "\x0722FF22[VSWEATHER]\x07FBECCB "
VSWeather.DebugLog.LOG_WARNING <- "\x07FFFF66[VSWEATHER]\x07FBECCB "
VSWeather.DebugLog.LOG_ERROR   <- "\x07FF0000[VSWEATHER]\x07FBECCB "
VSWeather.DebugLog.LOG_FATAL   <- "\x07FF0000[VSWEATHER]\x07FBECCB "

function VSWeather::DebugLog::LOG_PRINT( message, severity = "INFO" ) {

    message += "\n"
    if ( severity == "DEBUG" && GetInt( "developer" ) < 2 )
        return

    ClientPrint( null, 3, this["LOG_" + severity] + message )

    if ( severity == "ERROR" )
        error( message )

    Assert( severity != "FATAL", message )

    // printl( "[VS WEATHER] " + message )
}
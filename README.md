# VSWeather
## Automagic weather particle placement for your TF2 maps
![cool debug trace](./trace.gif)
*Slowed down and visualized*

## What it do
VSWeather traverses your maps navmesh and runs thousands upon thousands of traces, collision checking as many parts of your map as possible to automatically generate accurate info_particle_system placement with little manual cleanup required.  Anywhere this script doesn't place weather effects, you probably need to use collision particles.

You can export the results to either a VMF instance for further fine-tuning, or a script file to execute in your server config to add weather effects to existing maps.

Your mileage will vary depending on your map's layout, included in the `examples` folder is a collection of pre-generated particle configs for several maps for showing the types of maps it does (and doesn't) work best on.  None of these examples were modified afterwards, all of them were generated using the provided default config (with the exception of pl_enclosure, `ALL_NAV_CORNERS_SLOW` was set to false for this, nav's too big for this setting).

If your map does not have a navmesh, the `.wnav create` command will automatically handle multi-stage and other types of maps that struggle with the basic `nav_generate` command.  After generating the nav, you can use `.wnav cleanup` to automatically subdivide large nav areas and disconnect unreachable ones ([credit to Mikusch and ficool2 for the nav disconnect script](https://tf2maps.net/downloads/disconnect-unreachable-adjacent-nav-areas.16744/))

## Installing/Using
Drop the `scripts/` folder in this repo into your `tf/` folder.

See `tf/scripts/vscripts/vs_weather/CONFIG.nut` for usage and configuration.

## Chat Commands
- `.wstart` start the weather particle placement process.
- `.wsave <instance|script>` save the results to a VMF instance or script file.
- `.wreload` or `.wreset` reload the script for config changes.  Use this command instead of re-executing the main script.
- `.wnav <create|cleanup|subdivide|disconnect>` navmesh utilities, self-explanatory.
- `.whelp` simply prints every chat command.

Debug Commands (probably not super useful):
- `.wtest` Trace the closest nav area with DebugDrawLine to see why a particular nav area was skipped.  **Run `.wreload` after using this**
- `.wtrace` runs TraceLineEx from your current view angles and dumps the results to console.
- `.wfailed` draws all failed trace jobs.  Pretty useless.

## FAQ
- I'm getting a bunch of "does not exist" errors in console
    - You did not use `.wreload`/`.wreset` and tried to `script_execute vscript_weather` a second time.  Run `ent_fire __vs* Kill` then `script_execute vscript_weather` again.
- I'm getting a bunch of "script terminated by SQQuerySuspend" errors
    - See `tf/scripts/vscripts/vs_weather/CONFIG.nut` for more info.
- I set `developer 2` and now my game is completely frozen and busted when I open/close console from all the debug message spam
    - Yea my bad, don't do this for now...

## Credit/License
You are free to use the generated weather instances and scripts as you please, including commercial use, credit me if you want.  That being said, the `.wnav disconnect` and `.wnav cleanup` commands rely on a modified version of the script for disconnecting unreachable areas, consult those credits if you use these features.

If this script helped you and you want to support me, slide me a fat <1% on your map on the workshop or something idk.  Not required.

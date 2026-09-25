# RAT — Raid Activity Tracker

World of Warcraft: Mists of Pandaria 5.4.8 addon that estimates inactivity
during raid-trash combat from the local client's combat log.

RAT starts a session automatically inside a raid instance. A trash pack starts
after combat-log interaction between the group and an external unit. Boss
encounters are excluded using encounter events, the encounter-progress API when
available, and visible boss unit IDs. A manual stop pauses automatic recording
in that raid until you leave it for 30 seconds or start another session manually. Sessions
survive wipes and reloads. Finished sessions are retained for fourteen days.

Each player gets 15 seconds to join a pack. After their first personal action,
gaps of seven seconds or more count as inactivity. Crossing either limit
credits the whole applicable interval; a pack that ends during the grace
period adds nothing. A resurrected player receives 30 seconds before
inactivity can start again. Pet-only activity never credits the owner. Dead
and offline time is excluded. These three limits can be changed from 1 to 120
seconds using the Settings button or slash commands.

Open the report with `/rat` or the minimap button. Click a player for the
recorded inactivity intervals. The report includes eligible trash time, idle
time and percentage, longest idle interval, and number of packs observed for
that player. Use `Previous` and `Next` for saved sessions. `Export` opens a
selectable report that can be copied; RAT never posts it to group chat.

Commands:

- `/rat` — open or close the report
- `/rat start`, `/rat stop`, `/rat reset` — control the session
- `/rat settings` — open the settings window
- `/rat join N`, `/rat gap N`, `/rat revive N` — change limits in seconds
- `/rat sort percent`, `/rat sort idle`, `/rat sort name` — sort the table
- `/rat export` — open a copyable report
- `/rat minimap` — show or hide the minimap button
- `/rat help` — show command summary

Resumed sessions and packs that lose combat-log evidence while the group still
appears in combat are marked in the report. Combat-log visibility depends on
the observer's client, so the report is an estimate rather than proof that a
player was inactive. Boss detection can still depend on the server providing
encounter or boss-unit information.

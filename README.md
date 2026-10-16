# FS22_oh_no_i_am_stuck

A Farming Simulator 22 mod for when you're **stuck with a heavy trailer**. Turn it on and your throttle drives every wheel of the combination: the tractor's differentials lock and every wheel of every attached trailer gets drive torque too.

## Features

- The tractor's **differentials lock**, so all of its driven wheels turn together
- **Every wheel of every attached trailer, dolly and implement gets drive torque** in the direction you're driving
- Trailer wheels are only driven **while you give throttle**. Brake, coast or shift to neutral and they roll freely again
- The push is based on each trailer's own weight (including its load), so a full trailer pushes harder than an empty one
- Three strengths: low, medium and high (20%, 35% or 50% of the trailer's weight)
- Full push below 8 km/h, fading out up to 12 km/h. The diff locks open again above 15 km/h, so it gets you going but doesn't help you at speed
- A wheel that spins above 25 km/h (in the air, or on ice) gets no torque, and a trailer at an angle gets less push
- The strength is saved per tractor. The on/off state is not saved
- Works in multiplayer (the server does the physics)
- Works together with FS22_ThrottleHold

## Installation

1. Download `FS22_oh_no_i_am_stuck.zip` from the [Releases](../../releases) page.
2. Put the zip in `Documents\My Games\FarmingSimulator2022\mods`. Don't unzip it.
3. Turn on **Oh No I Am Stuck** when you load your savegame.

## Usage

| Input (in a vehicle) | Action |
|---|---|
| Left ALT + W | Turn all-wheel drive on / off |
| Left ALT + Q | Change strength (low / medium / high) |

You can change the keys in the game's controls menu. While it's on, a line at the top of the screen shows the strength and how many trailer wheels are being driven.

### Getting unstuck

1. Get in the stuck tractor.
2. Press ALT + W to turn it on.
3. Give throttle, forward or reverse. The tractor and all trailer wheels push together.
4. Still stuck? Press ALT + Q for more strength.
5. Once you're free, press ALT + W to turn it off.

**Tip:** don't go full throttle straight away. Spinning wheels dig in deeper.

## Known limitations

- A 2WD tractor's front wheels are not driven. Only the wheels that are already driven get locked together.
- Attached vehicles with their own engine (for example a towed tractor) don't get torque.

## Reporting problems

If something doesn't work, open `Documents\My Games\FarmingSimulator2022\log.txt`, search for `[OhNoIAmStuck]` and `OhNoIAmStuck.lua`, and open an issue with those lines and the vehicle and trailer you were using.

## Files

- `modDesc.xml`: mod description, key bindings and translations
- `scripts/register.lua`: adds the mod to every drivable vehicle
- `scripts/OhNoIAmStuck.lua`: diff locks, trailer wheel torque, keys and on-screen text
- `scripts/OhNoIAmStuckEvent.lua`: multiplayer event

## Credits

Made by Timo.

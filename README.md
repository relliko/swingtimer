# swingtimer

A low-profile melee swing timer for Ashita v4. It's a slim bar that fills up until your next auto-attack round, with the seconds left in small text beside it.

- It only shows while you're engaged, and fades out when you disengage.
- It never takes a click from the game.
- It learns your real swing speed from the rounds you actually swing, so haste and gear are picked up by themselves. It remembers the speed for each weapon set.

Nothing is ever sent to the server: swingtimer only reads client memory and incoming packets.

## Installation
- Copy the `swingtimer` folder into your Ashita v4 `addons` directory.
- Type `/addon load swingtimer` in game, then `/swing move` to put the bar where you want it.

## Usage
| Command | |
|---|---|
| `/swing on\|off` | show or hide the timer (`/swingtimer` works too) |
| `/swing move` | show the bar so you can drag it into place; `/swing move` again when done |
| `/swing size <width> <height>` | the bar's size in pixels (140 x 3 to start) |
| `/swing text on\|off` | the seconds left beside the bar |
| `/swing reset` | put it back below the middle of the screen |
| `/swing forget` | forget the swing speeds it has learned |
| `/swing debug` | your weapon set, its delay and what has been learned |

## How it times your rounds
The server (PhoenixXI, a LandSandBoat fork) swings one weapon delay after your last round, checking every 400 ms. Your first round comes 2 seconds after you engage. Weapon skills, spells and abilities pause that timer.

- The timer starts from your weapons' delay, with dual wield (NIN) and martial arts (MNK, PUP) by job level.
- It then learns the real time between your rounds. The server's 400 ms steps average out, and a haste change is picked up within a round.
- Intervals with a weapon skill, spell, ability or weapon swap in them aren't learned, and neither is a single long gap (such as being out of range).
- While you're busy with something else the bar stays full until your next round lands.

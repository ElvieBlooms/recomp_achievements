# Recomp Achievements Online

An add-on for Recomp Achievements that puts your score on the community
leaderboard by itself. Every time you save, it sends your leaderboard card
(and your Extra Credit page) if it changed since the last send. No more
copying codes into a form.

Recomp Achievements on its own never goes online. This add-on is the only
part that does, so leave it out if you'd rather keep it that way. Your
achievements, the menu and everything other mods use stay in the main
mod either way.

## Install

1. Install **Recomp Achievements** 2.7.0 or newer.
2. Install this add-on the same way (MODS > Import mod .zip) and enable
   both for the games you play.
3. Save in game. Open START > TROPHIES and press SELECT: the bottom of the
   card says ONLINE: SENT once it's on the board.

## Link it to Discord

Until it's linked, a save's scores belong to the save. To manage them from
Discord (and update them with `/score` too), link it once:

1. After a save has been sent, the card shows `DISCORD: /link` and a code
   like `ABCD-1234`.
2. Send `/link ABCD-1234` to the leaderboard bot.

The code lasts 7 days. Each save links on its own, and Save Sync carries
the link to your other devices.

## What it sends

To the leaderboard bot on Cloudflare: the game, trainer name, points,
achievements earned, play time, save ID and check code from the card, the
Extra Credit lines if SEND EXTRA CREDIT is on, and a random key kept in
your save. Cloudflare sees your IP address like any website does. Nothing
is sent to RetroAchievements.

## Options

In the MODS menu:

- **ONLINE SCORES**: turn sending off without uninstalling.
- **SEND EXTRA CREDIT**: off sends only the main card.

An unofficial fan project, not affiliated with RetroAchievements.
Source and issues: https://github.com/ElvieBlooms/recomp_achievements

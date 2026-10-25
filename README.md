# RC Party Orbs

Replaces the party frames with animated fire orbs: health and power orbs for you, your party and your target, threat borders, debuff colors, click to target, and modifier+click to dispel or resurrect.

Works on Retail (Midnight), MoP Classic, Cata, Wrath, TBC Anniversary, Classic Era and WoW Forever. On Retail and WoW Forever the game hides exact health, power and debuff types from addons in combat; the orbs then fill from the game's readable percentage.

Type `/fpo` in game for the options and commands.

Maintained by **Raw Card**.

## Tests

`pip install lupa && python3 tools/test_clients.py` loads the addon (TOC, XML frames and Lua) on a simulated copy of every client and class, joins a party and plays a fight with debuffed, dead, offline and out-of-range members, a raid and a vehicle, clicks every options control, runs every slash command and fires every event the addon listens for. Retail and WoW Forever get hidden combat values, and touching protected frames in combat counts as a failure. It runs on every push.

## Releasing (for the maintainer)

1. Update `## Version` in every `.toc` file and add the notes to the top of `CHANGELOG.md`.
2. On GitHub: **Releases** → **Draft a new release** → **Choose a tag** → type `v` plus the version (for example `v2.3.1`) → **Create new tag on publish** → **Publish release**.
3. The **Package and release** job (Actions tab) builds the zip, attaches it to the release, and uploads it to CurseForge (project `1435676`). It needs the `CF_API_KEY` secret (Settings → Secrets and variables → Actions).

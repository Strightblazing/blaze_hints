# blaze_hints

A hint system for Qbox, built in game by admins. Each **hint** is a set of steps: players get messages, inspect spots
and talk to NPCs, gather code pieces (messages, notes, inspect spots, NPC riddles, shop receipts), enter a code at a
keypad or an NPC, and it ends at a personal ox_inventory stash.

- Server is authoritative: codes are made and checked on the server; the full code is never sent to a client.
- Progress, found code pieces and stash unlocks are saved per character (citizenid).
- Every builder event checks the admin group / ace on the server, not only the command.
- Peds, vehicles, props, particles, blips, the camera and your HUD are cleaned up / restored on resource stop,
  logout, death and step end.
- All notifications use `lib.notify` (Lation UI restyles them). The only sound is a small click on keypad keys and letter tiles.

## Requirements

**Required** (the resource will not start without them):

- Qbox ([qbx_core](https://github.com/Qbox-project/qbx_core))
- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- [ox_target](https://github.com/overextended/ox_target): talk to NPCs, inspect spots, keypads, stashes
- [ox_inventory](https://github.com/overextended/ox_inventory): note / receipt items, personal stashes, shops

**Optional** (used automatically when running):

- `lation_ui`: Lation look for notifications and the menu builder
- `lation_shops`: NPC shop replies open Lation Shops (otherwise an ox_inventory shop)
- `Renewed-Weathersync` or `qb-weathersync`: in-game time for time locks (otherwise the real clock)

## Install

1. Put the folder in your resources (for example `resources/[standalone]/blaze_hints`) and keep the name
   **blaze_hints**: the item exports use it.
2. Add `ensure blaze_hints` to `server.cfg`, after everything under Requirements.
3. The tables (`blaze_hints`, `blaze_hints_progress`) are created on start. `sql/blaze_hints.sql` has the same SQL if
   you want to run it yourself. Coming from 1.0.x: the old tables are renamed on start and everything is kept.
4. Add the two items to `ox_inventory/data/items.lua`:

```lua
['blaze_note'] = {
    label = 'Note', weight = 5, stack = false, close = true, consume = 0,
    description = 'A handwritten note.',
    client = { image = 'printed_document.png', export = 'blaze_hints.readNote' },
},
['blaze_receipt'] = {
    label = 'Receipt', weight = 2, stack = false, close = true, consume = 0,
    description = 'A shop receipt.',
    client = { image = 'g_atm_receipt.png', export = 'blaze_hints.readNote' },
},
```

Using either one opens the note reader with that item's own text (each player's note holds their own piece).

5. Shop receipts:
   - **ox_inventory shops** work by themselves (a `buyItem` hook).
   - **Lation Shops**: add this to `OnItemPurchased` in `lation_shops/server/utils/hooks.lua`
     (it does nothing while blaze_hints is stopped):

```lua
if GetResourceState('blaze_hints') == 'started' then
    TriggerEvent('blaze_hints:shopPurchase', source, shopId)
end
```

## Commands (admins)

| Command | What it does |
| --- | --- |
| `/hintbuilder` | Opens the builder (`Config.BuilderStyle`). `/hintbuilder menu` or `/hintbuilder nui` picks one for that time |
| `/hintmanage` | Manage hints: players, progress, clean-up (see below) |
| `/hintlist` | Lists hints |
| `/hintreset <hintId> [serverId]` | Starts a hint over for you or a player (new code) |
| `/hinttoggle <hintId>` | Enables / disables a hint |
| `/hintdelete <hintId>` | Deletes a hint and everyone's progress on it |
| `/hintdemo`, `/hintdemonpc [classic]`, `/hintdemofull` | Test hints built around where you stand |

Players: `/hintnotes` lists the code pieces they have found.

## Builder

**Screen (`nui`)**: hint dropdown, name, enabled / auto start, numbered step list (▲ ▼ ✕ on hover, ✕ twice to delete) and
*Add step* on the left. On the right: *Place here* (your coords + heading), *Preview*, *Save*, *—* (hide the builder to
walk somewhere; `/hintbuilder` brings it back exactly as it was) and cards for the step, its code source, time lock,
world scene, NPC dialog or stash rewards. Saving updates the hint for every online player right away.

**Menus (`menu`)**: the same settings as ox_lib context menus and input dialogs. With `lation_ui` running (and
`Config.UseLationUI = true`) they use Lation's menus and inputs.

## Manage (`/hintmanage`, or *Manage* in the builder)

- **Overview**: every hint with on / off, steps, how many characters started and finished it, and who is on it now.
- **Per hint**: turn on / off, edit in the builder, duplicate (a copy, turned off, to change safely), reset everyone's
  progress, delete.
- **Players**: everyone who started it (name, step, finished, stash state, online). Put one on any step (handy for
  testing) or reset them; works for offline characters too.
- **Clean up**: delete every hint named "Demo ..." in one go, and remove progress of characters that were deleted.

Every action is checked against the admin group on the server.

## Startup

The console shows a Blaze Scriptworks banner when the hints have loaded (version, hint and step counts, Lation UI or
ox_lib, shops, in-game time source), then compares the version with the latest GitHub release
(`Config.VersionCheck`).

## Steps

Steps run in order for each character. Every step can have a **time lock** and a **world scene**.

| Type | What happens |
| --- | --- |
| `message` | A `lib.notify` (inform, titled "New hint") after the previous step, after a delay, or when entering a zone. Can carry a code piece (`{piece}` in the text), as a notification or as a `blaze_note` item |
| `inspect` | An ox_target spot only the player on that step sees. Optional close-up camera and prop. Overlay with the caption, "Code piece X of Y found" and "[E] Stop inspecting" |
| `npc` | A local ped with "Talk". Dialog lines with up to 4 replies: `next_line`, `give_clue` (can carry a piece: NPC riddle), `open_password`, `open_shop` (can give a receipt piece), `end`. Replies can finish the step |
| `password` | Keypad (digits) or word (letter tiles). Fixed or random per player, with a length. Wrong answers count down tries, then a cooldown (optionally the hint goes back with a new code) |
| `scene` | A world scene to reach. The next step with no spot of its own (inspect, stash, password) sits on it |
| `stash` | Personal ox_inventory stash (`RegisterStash(..., owner = true)`), locked until the character gets there. Rewards are added once to that character's own copy. Permanent storage or a one-time reward box |

A password step with no spot of its own, right after an NPC step, is entered at that NPC (its `open_password` reply).

### Code sources

On a password step, tick any mix of: message pieces, note item, inspect spot, NPC riddle, shop receipt, scramble.
The server splits the code across the steps between the previous password step and this one that carry a ticked kind
(in order). Scramble shows the code's characters shuffled on the code screen.

### Time locks (checked on the server)

| Mode | Settings |
| --- | --- |
| `ingame_hours` | Opens / closes hours (wraps past midnight). Reads Renewed-Weathersync or qb-weathersync; without one it warns and uses the real clock |
| `real_time` | Days (Mon-Sun) + hours, server clock or `Config.TimeZone` (UTC offset) |
| `date_window` | `YYYY-MM-DD HH:MM` open / close |
| `timer_after_last_step` | Seconds after the previous step: `wait` (opens after) or `expire` (too late after: the hint goes back with a new code) |

While locked: messages wait until it opens; NPCs and spots are hidden or show the locked message; optional "come back at X" hint.

### World scenes

Presets in `Config.ScenePresets`: `armored_van` (stockade, rear doors 2 and 3 open, frozen, invincible, locked,
engine off), `crate_drop`, `briefcase`. 0-4 guards (calm, hostile or set dressing), smoke / sparks / flare,
an optional temporary search-area blip.

- **private** (default): non-networked entities spawned only for the player on that step.
- **shared**: spawned by the server so everyone sees them while someone is on that step; effects and the blip stay
  on the screens of players on that step. A stash only keeps a *private* scene after its step.

## Config highlights

- `Config.CinematicDialog`: letterbox + face camera + HUD hidden, or the small bottom-right panel (per NPC override).
- `Config.Markers`: the where-to-look marker, a floating **?** (or any GTA marker type) over the current inspect spot,
  keypad and unlocked stash, only for the player on that step and never while the step is time-locked. Each step can
  force it on or off in the builder ("Where-to-look marker").
- `Config.Camera`: hide your own character and players standing at the clue / NPC during hint cameras. Only on the
  screen of the player looking; everyone else still sees everyone.
- `Config.Hud`: hide your own HUD while hint screens are open: put its show / hide export here, or a toggle function.
- `Config.Shop.system`: `auto` (Lation Shops, else ox_inventory), `lation` or `ox`.
- `Config.MaxWrongTries`, `Config.DefaultCooldown`, `Config.ResetOnFail`: password defaults (per step in the builder).
- `Config.Words`: random words for word codes.
- `Config.Text`: every player-facing string.

## License

GNU GPL v3 (see [LICENSE](LICENSE)). You can use, change and share it; if you share a changed version,
share its source under the same license.

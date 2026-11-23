# blaze_hints

Clue hunts for Qbox, built in game by admins. Players get hint notifications, gather code pieces
(hints, notes, inspect spots, NPC riddles, shop receipts), enter a code at a keypad or an NPC, and the hunt
ends at a personal ox_inventory stash.

- Server is authoritative: codes are made and checked on the server; the full code is never sent to a client.
- Progress, found code pieces and stash unlocks are saved per character (citizenid).
- Every builder event checks the admin group / ace on the server, not only the command.
- Peds, vehicles, props, particles, blips, the camera and your HUD are cleaned up / restored on resource stop,
  logout, death and step end.
- All notifications use `lib.notify` (Lation UI restyles them). The only sound is a small click on keypad keys and letter tiles.

## Install

1. Dependencies: `ox_lib`, `oxmysql`, `ox_target`, `ox_inventory`, `qbx_core`. Optional: `lation_ui` (menu builder look),
   `lation_shops` (NPC shops), `Renewed-Weathersync` or `qb-weathersync` (in-game time locks), `element_hud` (HUD hiding).
2. `ensure blaze_hints` after those.
3. The tables are created on start. `sql/blaze_hints.sql` has the same SQL if you want to run it yourself.
4. Items (already added to this server's `ox_inventory/data/items.lua`; add them elsewhere like this):

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
     (already done on this server):

```lua
if GetResourceState('blaze_hints') == 'started' then
    TriggerEvent('blaze_hints:shopPurchase', source, shopId)
end
```

## Commands (admins)

| Command | What it does |
| --- | --- |
| `/huntbuilder` | Opens the builder (`Config.BuilderStyle`). `/huntbuilder menu` or `/huntbuilder nui` picks one for that time |
| `/huntlist` | Lists hunts |
| `/huntreset <huntId> [serverId]` | Starts a hunt over for you or a player (new code) |
| `/hunttoggle <huntId>` | Enables / disables a hunt |
| `/huntdelete <huntId>` | Deletes a hunt and everyone's progress on it |
| `/huntdemo`, `/huntdemonpc [classic]`, `/huntdemofull` | Test hunts built around where you stand |

Players: `/huntnotes` lists the code pieces they have found.

## Builder

**Screen (`nui`)**: hunt dropdown, name, enabled / auto start, numbered step list (▲ ▼ ✕ on hover, ✕ twice to delete) and
*Add step* on the left. On the right: *Place here* (your coords + heading), *Preview*, *Save*, *—* (hide the builder to
walk somewhere; `/huntbuilder` brings it back exactly as it was) and cards for the step, its code source, time lock,
world scene, NPC dialog or stash rewards. Saving updates the hunt for every online player right away.

**Menus (`menu`)**: the same settings as ox_lib context menus and input dialogs. With `lation_ui` running (and
`Config.UseLationUI = true`) they use Lation's menus and inputs.

## Steps

Steps run in order for each character. Every step can have a **time lock** and a **world scene**.

| Type | What happens |
| --- | --- |
| `hint` | A `lib.notify` (inform) after the previous step, after a delay, or when entering a zone. Can carry a code piece (`{piece}` in the text), as a notification or as a `blaze_note` item |
| `inspect` | An ox_target spot only the hunter sees. Optional close-up camera and prop. Overlay with the caption, "Code piece X of Y found" and "[E] Stop inspecting" |
| `npc` | A local ped with "Talk". Dialog lines with up to 4 replies: `next_line`, `give_clue` (can carry a piece: NPC riddle), `open_password`, `open_shop` (can give a receipt piece), `end`. Replies can finish the step |
| `password` | Keypad (digits) or word (letter tiles). Fixed or random per player, with a length. Wrong answers count down tries, then a cooldown (optionally the hunt goes back with a new code) |
| `scene` | A world scene to reach. The next step with no spot of its own (inspect, stash, password) sits on it |
| `stash` | Personal ox_inventory stash (`RegisterStash(..., owner = true)`), locked until the character gets there. Rewards are added once to that character's own copy. Permanent storage or a one-time reward box |

A password step with no spot of its own, right after an NPC step, is entered at that NPC (its `open_password` reply).

### Code sources

On a password step, tick any mix of: hint pieces, note item, inspect spot, NPC riddle, shop receipt, scramble.
The server splits the code across the steps between the previous password step and this one that carry a ticked kind
(in order). Scramble shows the code's characters shuffled on the code screen.

### Time locks (checked on the server)

| Mode | Settings |
| --- | --- |
| `ingame_hours` | Opens / closes hours (wraps past midnight). Reads Renewed-Weathersync or qb-weathersync; without one it warns and uses the real clock |
| `real_time` | Days (Mon-Sun) + hours, server clock or `Config.TimeZone` (UTC offset) |
| `date_window` | `YYYY-MM-DD HH:MM` open / close |
| `timer_after_last_step` | Seconds after the previous step: `wait` (opens after) or `expire` (too late after: the hunt goes back with a new code) |

While locked: hints wait until it opens; NPCs and spots are hidden or show the locked message; optional "come back at X" hint.

### World scenes

Presets in `Config.ScenePresets`: `armored_van` (stockade, rear doors 2 and 3 open, frozen, invincible, locked,
engine off), `crate_drop`, `briefcase`. 0-4 guards (calm, hostile or set dressing), smoke / sparks / flare,
an optional temporary search-area blip.

- **private** (default): non-networked entities spawned only for the hunter.
- **shared**: spawned by the server so everyone sees them while someone is on that step; effects and the blip stay
  on the hunters' screens. A stash only keeps a *private* scene after its step.

## Config highlights

- `Config.CinematicDialog`: letterbox + face camera + HUD hidden, or the small bottom-right panel (per NPC override).
- `Config.Markers`: the where-to-look marker, a floating **?** (or any GTA marker type) over the current inspect spot,
  keypad and unlocked stash, only for the hunter on that step and never while the step is time-locked. Each step can
  force it on or off in the builder ("Where-to-look marker").
- `Config.Hud`: which HUD export to hide (element_hud set up), and when.
- `Config.Shop.system`: `auto` (Lation Shops, else ox_inventory), `lation` or `ox`.
- `Config.MaxWrongTries`, `Config.DefaultCooldown`, `Config.ResetOnFail`: password defaults (per step in the builder).
- `Config.Words`: random words for word codes.
- `Config.Text`: every player-facing string.

## License

GNU GPL v3 (see [LICENSE](LICENSE)). You can use, change and share it; if you share a changed version,
share its source under the same license.

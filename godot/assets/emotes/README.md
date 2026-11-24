# Chat emotes

Drop-in folder for the in-game event feed (`godot/scripts/Events.gd`).

Any `*.png` or `*.webp` file in this folder becomes an emote token named after
the file, lowercased:

```
assets/emotes/chog_hype.png  ->  :chog_hype:
assets/emotes/gg.webp        ->  :gg:
```

Use square images (128×128 or 256×256 is plenty; the feed draws them at 20 px)
with a transparent background. Built-in emotes already ship from
`assets/img/` (`:chicken:`, `:gem:`, `:mon:`, `:loot:`, `:star:`, `:energy:`).

Emotes are inserted into player event lines at random (35% of lines, 100% of
hype lines such as "picked the chicken" / "won the round"). Typing the token in
a message always renders the image, so a future chat input needs no extra work.

## Animated emotes (GIF-style)

Godot has no GIF/APNG decoder, so a GIF has to become a horizontal sprite sheet
(all frames in one row, equal width). Export e.g. `chog_dance.png` at
`frames × 64 px` wide and 64 px tall, then the frame driver can animate it by
updating one shared `ImageTexture` — no per-row work.

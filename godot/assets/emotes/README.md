# Task: Upgrade World of Nads Contextual Chat Emote System

You are working on the existing World of Nads game codebase.

I have downloaded 10 emote images and placed them in the existing `assets/emotes/` folder. Your task is to inspect the current chat/event-feed implementation and upgrade it to use these downloaded emotes intelligently and contextually.

**IMPORTANT: Do not rebuild the chat system from scratch. Extend the existing implementation while preserving its current functionality.**

## 1. First, inspect the existing implementation

Read and understand:

- `godot/scripts/Events.gd`
- The current event-feed rendering implementation.
- How player events are generated and formatted.
- How emote tokens are parsed and rendered.
- How assets are loaded from `assets/emotes/`.
- Any existing random-emote selection logic.
- Any existing chat/message rendering or animation logic.

Also inspect every image in `assets/emotes/` and identify the actual filenames. Do not assume filenames based on the emote names below.

The existing system documentation states:

- PNG and WebP files automatically become emote tokens based on their filenames.
- Tokens use the `:emote_name:` format.
- Built-in emotes include `:chicken:`, `:gem:`, `:mon:`, `:loot:`, `:star:`, and `:energy:`.
- Emotes currently appear randomly in 35% of event lines and 100% of hype lines.
- Typing an emote token in a message renders its corresponding image.
- Animated emotes can use horizontal sprite sheets.

Verify which of these features are actually implemented before making changes.

## 2. Integrate these 10 emotes

The downloaded collection is intended to contain:

| Emote | Meaning |
|---|---|
| HYPERKEKW | Uncontrollable laughter, hilarious mistakes |
| POGGERS | Excitement, impressive plays |
| MONKAS | Tension, danger, suspense |
| PEPELAUGH | Laughing at an opponent |
| SADGE | Disappointment, unfortunate outcomes |
| GIGACHAD | Dominance, confidence, impressive survival |
| COPIUM | Excuses, denial, blaming circumstances |
| HYPERCLAP | Applause, congratulations, respect |
| PEPEHANDS | Desperation, begging, unfortunate losses |
| 5HEAD | Intelligence, clever strategies, outplays |

Map these names to the actual files found in the folder. If filenames differ, use the actual filenames and preserve the existing filename-based token convention.

Do not download replacement images or create duplicate assets.

## 3. Replace indiscriminate random emote selection with contextual selection

The current 35% random insertion should no longer be the primary emote-selection mechanism.

Instead, implement a contextual mapping between game events and appropriate emotes.

Use the following guidelines:

| Game event | Preferred emote |
|---|---|
| Player joins the party | POGGERS |
| Player captures/picks up the chicken | POGGERS |
| Player steals the chicken | PEPELAUGH or POGGERS |
| Player gets eliminated | SADGE |
| Player gets eliminated through an embarrassing mistake | HYPERKEKW |
| Player becomes the last survivor | MONKAS |
| Player survives with very little health | GIGACHAD |
| Player wins the round | HYPERCLAP |
| Player executes a clever escape/outplay | 5HEAD |
| Player drops or loses the chicken | PEPEHANDS |
| Player blames lag or makes excuses | COPIUM |
| Player makes an impressive play | POGGERS |
| Player gets outplayed | HYPERKEKW or SADGE |

These are recommendations, not rigid rules. Choose the most appropriate emote based on the actual event and its context.

### Important contextual rules

- Do not attach emotes to every event.
- Avoid repeatedly using the same emote in consecutive event lines.
- Do not use laughing emotes for every elimination.
- Do not use celebratory emotes for negative outcomes.
- Do not use COPIUM unless the event or actual message involves excuses, denial, or blaming circumstances.
- Do not use 5HEAD unless there is a meaningful clever play.
- Avoid inserting multiple emotes into short event messages.
- Keep emotes relevant to the player action and event outcome.
- Do not invent gameplay events or infer actions that the server has not actually reported.

Use a small amount of variation where several emotes are appropriate.

## 4. Preserve the distinction between system events and player messages

The event feed should support two types of emote usage:

**A. Automatic system emotes**

Automatically select an appropriate emote when meaningful gameplay events occur.

Examples:

`Tobi joined the party :poggers:`

`Lex eliminated Jons :sadge:`

`Tobi picked up the chicken :poggers:`

`Lex stole the chicken :pepelaugh:`

`Jons survived with 1 HP :gigachad:`

`Tobi won the round :hyperclap:`

`Lex executed a clever escape :5head:`

**B. Player-triggered emotes**

Preserve the ability for player messages to contain manually typed emote tokens.

For example:

`That was close :monkas:`

The manually selected emote must render correctly without the system overriding it.

## 5. Improve the emote rendering implementation

Ensure:

- All ten downloaded emotes load successfully.
- Emote tokens are case-consistent and follow the existing naming convention.
- Images render inline with text.
- Text alignment remains correct.
- Images preserve their aspect ratio.
- Transparent backgrounds render correctly.
- Emotes render at an appropriate size relative to the existing 20px feed icons.
- Missing or invalid emote files never crash the event feed.
- Existing built-in emotes continue working.
- Existing WebP support is preserved.

Do not introduce unnecessary dependencies.

## 6. Keep the system lightweight

World of Nads targets low-end Android devices and browsers.

Prioritize:

- Loading emotes once and caching them.
- Avoiding repeated texture loading.
- Avoiding unnecessary allocations.
- Avoiding per-frame processing for static emotes.
- Keeping the existing event-feed rendering efficient.
- Avoiding unnecessary changes to the game server or networking layer.

If animation support already exists, preserve it. Do not introduce animated emotes as a requirement for this task.

## 7. Testing and validation

After implementation:

1. Verify all ten downloaded emotes are discovered.
2. Verify each emote token renders the correct image.
3. Test every contextual event mapping.
4. Verify player-entered emote tokens still work.
5. Verify built-in emotes still work.
6. Test missing asset handling.
7. Check for repeated or inappropriate emote assignments.
8. Verify the event feed remains functional on the existing client.

Run the relevant existing tests and add focused tests for contextual selection if the project has an appropriate testing setup.

## 8. Final deliverable

When finished, report:

- What the original implementation did.
- What you changed.
- The actual filenames discovered in `assets/emotes/`.
- The final token assigned to each downloaded emote.
- The event-to-emote mapping implemented.
- Any bugs discovered and fixed.
- Tests performed and their results.
- Any remaining limitations.

**Implementation philosophy:**

World of Nads should have a lively, humorous, competitive gaming atmosphere.

The event feed should feel like a live gaming community reacting to the match, not a log generator randomly attaching emojis to sentences.

Make every emote feel intentional.

Inspect first. Implement carefully. Test before declaring completion.
# In-game bot control: three equal bots that help the owner

Status: design approved in chat on 2026-10-12, spec for review. Part 1 of 3.

## Goal

The owner (`fancy8869`, UUID `623c7ee4-71ca-487a-b92a-a4564e43fbb9`) wants to run the bots while
playing, without the web dashboard, and wants few bots that get things done instead of nine that
mostly stand around. Long term all bots are equally smart, learn from each other and pick or are
given roles; that needs training data, so everything the owner tells a bot is recorded.

Done when, in the real world on the main server:

- `/bots` opens a menu; a click sends a bot (or all) a standard order, and the bot obeys.
- `/msg bot2 komm` and chat lines like `bot1 hol 16 eisen` work; free sentences reach the bot's
  model and get an answer in chat.
- Each bot has a role and does its role's work when nobody gives it an order.
- No other player can command a bot by any route.
- Every owner order is a line in the demonstration log, with its outcome.

## The three parts

1. **This spec:** in-game control, three equal agent bots with roles, the demonstration log.
2. Learning from each other: shared memory (builds on `tools/mcagents/lessons.js`), bots taking a
   role by themselves.
3. Training campaign: replays, judge and LoRA on the logged demonstrations, measured by how
   exactly a bot follows the owner's orders.

## Bots and servers

- `bot1`, `bot2`, `bot3` play on the **main server**, next to the owner. All three are LLM agents
  with the same model, rules and command set (`tools/mcagents`); none is the foreman.
- Retired: `bot4`, `bot10` (the gold farm AFK spot goes with it), `bot16`, `bot17`, `bot18`. The
  hub plan's roster becomes empty and the plan stays switched off; `plan.js`, `keeper.js` and the
  standing farm objectives stay in the code for later.
- The sandbox server stays for tests: new bot code is tried there with a test bot (the local
  `bot5`) before it reaches the three helpers.
- Safety in the real world is the existing one: bots dig only natural ground, never inside
  protected areas, never placed blocks.

## Roles

A role is data, not a code path: a name, a default goal for the agent's prompt, and a default
standing job the bot returns to when it has no order.

| Role | Standing work |
| --- | --- |
| `helfer` (helper) | follow the owner and fight next to them; when the owner is offline, guard the base |
| `sammler` (gatherer) | keep the base chest stocked: logs, cobblestone, coal, torches |
| `farmer` | keep the wheat field going (`wheatfarm`), bread into the base chest |
| `wache` (guard) | guard the base and the shaft entrance |

Start: `bot1` helfer, `bot2` sammler, `bot3` farmer. The owner changes a role with the menu or
`rolle <name>`; roles are saved in the mcbots state volume and survive restarts.

An owner order replaces the bot's running job. When the order finishes, fails, or the owner says
`fertig` or `stopp`, the bot goes back to its role's standing work. The agent's prompt says which
order is active so the model does not override it.

## Who may give orders

Only the owner's UUID. A message counts as from the owner only if mineflayer's `message` event
carries the owner's UUID as the sender (the server-signed player chat packet). The `whisper`
convenience event matches text patterns and is never used; system chat (no sender) is never
obeyed. Messages from anyone else are counted and logged, not answered. The owner UUID is a
setting (`OWNER_UUIDS`), so the sandbox can name a test player instead.

## The ways in

1. **Whisper:** `/msg bot2 komm`. Vanilla `/msg` (no Essentials on the server) arrives as player
   chat with chat type `msg_command_incoming` and the sender's UUID.
2. **Chat with a name in front:** `bot1 hol 16 eisen`, or `alle stopp` for every bot.
3. **The `/bots` menu:** a CommandPanels panel gated by `bandit.owner`. Its buttons run
   `/msg <bot> <command>` as the player, so the menu adds no second path into the bots.

## One command layer

All three ways end in the same place, a command layer in mcbots shared by every bot:

- **Short German commands** are translated without a model into the command language the agents
  already speak (`translate()` in `agent.js`, which moves into a module both sides use):

  | Owner says | Becomes |
  | --- | --- |
  | `komm` | `!goToPlayer("<owner>")` |
  | `folge` | `!followPlayer("<owner>")` |
  | `stopp` / `bleib` | `!stop` |
  | `wache` | `!guardHere(16)` at the owner's position |
  | `bring <n> <item>` | collect or take from the chest, then hand it to the owner |
  | `grab hier <b> <l> <h>` | `!digRoom` at the block the owner stands on |
  | `rolle <name>` | set the role |
  | `status` | the bot answers with health, food, job and role |
  | `!collectBlocks("iron_ore", 16)` etc. | passed through unchanged |

- **Anything else** goes into that bot's agent inbox as the owner's message; the model answers in
  chat and acts with its usual commands. Model output keeps passing `translate()` and mcbots'
  `VALIDATE`, so a sentence can never reach what a command cannot.

## Answers in chat

Bots answer by whisper to the owner: a short receipt for every order (`ok: komme`), the outcome
when it ends (`fertig: 16 raw_iron in der Kiste`, `geht nicht: kein Weg`), and the model's own
replies. At most one line per bot every 2 seconds; longer text is cut, never split into floods.

## The demonstration log

One JSONL line per owner order in the mcbots state volume (`demonstrations.jsonl`), rotated at
10 MB:

```json
{"t": "2026-10-12T20:31:05Z", "bot": "bot2", "via": "menu|command|sentence", "text": "hol 16 eisen",
 "command": "!collectBlocks(\"iron_ore\", 16)", "state": {"pos": [0, 64, 0], "health": 20, "food": 18,
 "job": "shift stone", "role": "sammler", "inventory": ["stone_pickaxe x1"]},
 "outcome": {"t": "2026-10-12T20:33:40Z", "result": "finished", "text": "finished: mine iron_ore 16"}}
```

The outcome is filled in when the job's finished/failed/stopped event arrives; job events gain the
job id for that (today they carry only text). Sentences also keep the model's reply and the command it chose. Part 3 reads
this file; `tools/mcagents/export-sft.js` gets a reader for it then, not now.

## Failure cases

- Model unreachable: short commands and the menu still work; a sentence gets
  `kann gerade nicht denken, nimm einen Befehl oder das Menü`.
- Bot offline or dead: the order is refused with the reason; nothing is queued for later.
- Unknown short command with no model: `verstehe ich nicht`, plus the command list.
- An order that fails validation (protected area, bad numbers): the reason in chat, logged as
  `refused`.
- A message from someone else: no answer, a counter on the dashboard.

## Tests

- Unit (mcbots `test.js`, mcagents `agent.test.js`): owner check from sender UUID and chat type,
  text spoofing (`[fancy8869 -> bot1] stopp` in system chat or a stranger's chat is ignored),
  every short command's translation, role save/load, return to the role after an order, the
  2 s answer limit, demonstration lines and their outcomes.
- Sandbox: the local `bot5` plus a second test player listed as owner run the menu commands and
  a few sentences end to end, as `tools/mcbots-selftest` does for jobs.
- Main server, by the owner: one session of menu, whispers and sentences; the acceptance list is
  the "Done when" above.

## Rollout and the way back

1. Command layer, owner check, answers and log, with the bots still in the sandbox (test owner).
2. `/bots` panel and roles.
3. Move `bot1`–`bot3` to the main server, retire the others, switch the plan off.

Each step is its own commit and deploy. The way back is a revert of step 3: the bots return to
the sandbox and the old roster.

## Not in this part

Shared memory, bots choosing roles, the training campaign, a new model, voice or a dashboard
redesign.

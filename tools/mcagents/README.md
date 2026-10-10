# mcagents: Minecraft-tuned LLM agents for mcbots (experiment)

Each agent is one LLM "brain" for one bot. The model decides **what** the bot does next; the mcbots
dashboard API does the walking, digging and fighting with all its safety rules. The model is
**Andy-4.2** (Mindcraft-CE, March 2026, Qwen3.5-9B, Andy 2.0 License). It speaks Mindcraft's
command language, the format it was trained on, and `agent.js` maps each command to an mcbots
job. `!newAction` (the model writing code) and anything unknown is refused. `!startConversation`
lets agents talk to each other; `!buildBlueprint` builds our blueprints.

```bash
# on the lab (one-time): ollama with CUDA is built from the pinned nixpkgs (~22 min), the GGUF
# is fetched with curl (ollama's hf.co pull refuses Hugging Face's CDN redirect), then:
#   printf 'FROM ./andy-4.2.q4_k_m.gguf\nPARAMETER temperature 0.6\nPARAMETER num_ctx 8192\n' > Modelfile
#   ollama create andy-4.2 -f Modelfile
# on the laptop: tunnel to the lab's ollama (it listens on 127.0.0.1 only), a stage for the bots, the agents
ssh -N -L 11434:127.0.0.1:11434 bandit-lab &
BOT_NAMES=bot11,bot12 DASHBOARD_PORT=8097 SUPPLY_CHEST=x,y,z MC_HOST=100.125.161.81 nix run .#mcbots &
API=http://127.0.0.1:8097 AGENTS='bot11=Collect 16 cobblestone and put it in the base chest.;bot12=Chop 12 logs.' \
  node tools/mcagents/agent.js
```

Routines: `!startShift(type)` (logs or a block, into the base chest), `!guardHere(radius)` and
`!afkHere` (stop, no more prompts until another agent writes; player chat does not wake it). A running `shift`, `guard` or `follow`
never ends by itself; the agent loop only prompts a bot that has no job (or got a message), so a
routine is never re-prompted. End one with `!stop`.

When the brain is asked (H2): only (1) after a job result (finished, failed, gave up, stopped),
(2) after a death or respawn, (3) when a message arrived, and (4) every `CHECKIN_MS` (default 10
min) while a routine runs or the bot idles. A bot that is busy with a plain job is not
interrupted, and `!afkHere` silences it until a message. All agents together make at most
`MAX_DECISIONS_PER_MIN` (default 12) model calls per minute (each query round of a decision counts); the rest wait for a later tick, longest
waiting first. The agent prints `stats [botN] ... decisions (x/h), model time ...` every
`STATS_MS` (default 10 min).

Measured 2026-10-10 (bot11-bot14, one shift, one guard, one chop loop, one coal mine; 29 min):
26 model calls in total, 1.05 s on average, 27 s of model time, GPU utilisation 0.7 % on average
(116 samples every 15 s; peak 85 % of a 15 s sample), 5.6 GB VRAM. The chop loop is the chattiest
agent because each finished job wakes it (39 decisions/h); the shift and the guard cost 6/h.

Roles (H3): only the bots named in `AGENTS` get a brain; every other bot is untouched and runs
the plain mcbots jobs, standing orders and dashboard clicks (the agent ignores their events and
never sends them a job). On the lab: **bot4 stays scripted** (AFK at the gold farm, no agent), the
rest of bot1-bot3 and the laptop bots can be LLM-led by listing them in `AGENTS`. One bot is never
controlled by an agent and by the owner at the same time on purpose: to take over an agent's bot,
remove it from `AGENTS` (or `!stop` it and give it no goal). A foreman gives scripted bots work
with `!assign` (H4).

Foreman (H4): `WORKERS=bot12,bot13,bot14` lists the scripted bots a brain may command (an agent in
`AGENTS` is never a worker). `!assign("bot12", "!collectBlocks(\"cobblestone\", 32)")` translates the
inner command like any other and sends it as that bot's job: only action commands (collect,
startShift, putInChest, craft, goTo...), no queries, no nested `!assign`, no blueprints. A worker on a
routine (shift, guard, follow) is replaced; a worker with a plain job gets the order queued. The
foreman's prompt lists the workers and what they do, a worker's finished/failed/stopped result and
deaths are fed back to the foreman that gave the order, and as long as another worker is idle the
foreman is asked again at once (a shift never reports back). Live 2026-10-10 with the goal "fill the
base chest with 32 cobblestone and 16 logs": it gave bot12 and bot14 a stone shift and bot13 a log
shift within about a minute; after 13 min the shifts carried 778 + 351 cobblestone and 196 logs.

Beds (R5): `!huntAnimals(type, num)` (sheep, cow, pig, chicken; the `hunt` job within 24 blocks of where
the bot stands; sheep are sheared when it has shears) and `!placeBed(x, y, z, facing)` (the `bed` job: crafts a
bed from 3 wool of one colour and 3 planks if it holds none, places it with the foot at x y z and the head
towards `facing`, and clicks or sleeps in it so the spawn point is there). A foreman may assign both.

What is around (mcbots `GET /api/scan/<bot>`, see BOTS.md "Scan"): the prompt has one `Around you (...)` line for the
agent's own bot (300 characters at most), a foreman also one `around:` line (120 characters) under each worker,
and `!nearbyBlocks` returns the scan. `!collectDrops(radius)` (the `tidy` job around where the bot stands, then a
deposit) is for workers and lone agents; a foreman assigns it. A missing scan is just left out.

A foreman sees a short command list: `!assign`, `!baseStatus`, `!buildBlueprint`, `!digRoom`,
`!huntAnimals`, `!placeBed`, `!setHomeBed`, `!placeBlockAt`, `!viewChest`, `!nearbyBlocks`, `!stats`, `!inventory`, `!goToCoordinates`, `!stop`, `!startConversation`
(anything else is refused with a one-line hint; workers and agents without workers keep the full set). Its
prompt carries one `BASE:` line (the base chest as last counted, lowest first, from `/api/state`
`world.stock`, and which builds and rooms it saw finish), each worker's last result (`STUCK` after two
identical failures), and the workers' deposits as `bot3 put 64 cobblestone into the base chest` (the last three
stay). `!baseStatus` prints the same on request. A build or room that already finished is refused, a stuck
(resting) worker gets no order; `mcagents` forgets what is done when it restarts. Replay of three recorded
situations against the lab model (8 samples each, old vs new `agent.js`): see the commit message.

Env: `MODEL` (default `andy-4.2`), `ANDY_URL_2` (optional OpenAI-compatible Andy endpoint, for
example `http://127.0.0.1:18081`), `THINK=1` (reasoning on: about 20-30 s per decision with 4
agents on one GPU instead of about 1 s), `LOG` (JSONL of every model call: prompt, thinking,
reply; raw material for a later fine-tune), `BLUEPRINTS`.

When `ANDY_URL_2` is set, requests use the healthy backend with fewer in-flight calls (backend 2
wins ties), and retry the other backend after a request error or timeout. Ollama health is probed
with `/api/tags`; OpenAI-compatible backends use `/health`. Health results are cached for 10 seconds.

Live 2026-10-10 (bot11-bot14, RTX 4090 laptop GPU on the lab, about 5.6 GB VRAM):
- The four agents split the work: miner, lumberjack, builder, helper.
- The builder found material missing and asked the miner with `!startConversation`; the miner
  answered and delivered.
- 6 of 9 pad blocks were placed. Then the builder retried the same blocked spot (a hill) again and
  again. That is now caught: after two identical failures the model is told to change something.
- With reasoning off, every decision took 0.7-1.6 s.

Limits: an agent stops when its goal is done (`!endGoal`). Long-running work needs standing goals
or the plan of R7 in `docs/NEXT-GOALS.md`. Tests: `node tools/mcagents/agent.test.js`.

Replay harness (Node, no dependencies):

```bash
node tools/mcagents/replay.js export decisions.jsonl > replay.jsonl
# After reviewing the frozen dataset, use a model server base URL (or full chat URL):
node tools/mcagents/replay.js run replay.jsonl --endpoint http://127.0.0.1:11434 --api ollama --model andy-4.2 --seed 11 > ollama-11.jsonl
node tools/mcagents/replay.js run replay.jsonl --endpoint http://127.0.0.1:11435 --api openai --model andy-4.2-baseline --seed 11 > openai-11.jsonl
node tools/mcagents/replay.js score ollama-11.jsonl
node tools/mcagents/replay.js compare ollama-11.jsonl openai-11.jsonl
node tools/mcagents/replay.test.js
```

Export de-duplicates sanitized message arrays, strips credential fields/redacts common
credential patterns, and skips `/api/decision` bodies (only truncated `bot`/`text`, no
prompt). IDs are prompt SHA-256 hashes; `episode_id` falls back to the agent name.
Review redaction, assign real episode boundaries, fill missing `goal`/`state` (including
workers and saved places), and write human `expected` constraints before freezing.
LOG lacks complete world state; export infers position/chest from STATS and preserves
prior parsed commands and subsequent prompt outcomes. No ground truth is invented.

Run sends prompts sequentially, thinking off, with agent.js sampling, seed and a 512-token
cap. Configure the OpenAI-compatible server for 8,192 context; this API has no standard
context-size parameter. Output preserves raw reply, latency, reported tokens, errors and
truncation. The harness only calls chat endpoints, never executes bot commands.

Score reports fractions over all rows, translator acceptance (queries/local commands
included), refusal/no-command (also errors/truncation), `!stop`, and canonical-command
repeats against the **last prior command in each frozen row**, plus median/p95 latency
(nearest-rank p95). It reuses agent.js's permissive parser/translator; it does not validate
all executor arguments, foreman rules or job success. Compare requires matching IDs/seeds
and frozen prompts/state/history; it emits A/B metrics, B-minus-A differences and per-pair
boolean/latency deltas. Repeat this for seeds 11, 22, 33, alternating backend order.
Human goal consistency, harmful-repeat adjudication, tokenizer/context checks and the
provenance manifest remain the separate protocol in
[AGENT-TRAINING.md](../../docs/runbooks/minecraft/AGENT-TRAINING.md).

Offline decision dataset builder (plain Node, no dependencies or network calls):

```bash
node tools/mcagents/dataset.js /private/decisions.jsonl --out /private/dataset
# Optional local GET /api/events dump; this tool never fetches it:
node tools/mcagents/dataset.js /private/decisions.jsonl --events /private/events.json --out /private/dataset-with-events --cap 3
node tools/mcagents/dataset.test.js
```

The output directory must be new; existing paths and symlinks are refused. It is
created mode 0700, with mode-0600 `train.jsonl`, `val.jsonl`, `test.jsonl`,
`labels.jsonl` and `stats.json`. Keep these local and outside Git. Input is JSONL
with `t` (ISO time or epoch milliseconds), `agent`, full `messages` and `reply`;
`ms`, `episode_id`, `server_session` and `goal` are optional. Malformed JSON fails
the build; records missing the required decision fields are counted as invalid.
Event inputs accept an `/api/events` object (`events`, `lastId`), an event array,
or JSONL archive wrappers (`server_session`, `event`). Events use the mcbots
`{id,t,bot,kind,text}` schema; conflicting IDs within one server session fail.
Annotate matching decisions and events with `server_session` across restarts.

Labels are automatic **outcome candidates**, not human judgements of a safe or
useful plan. `good` requires a compatible `finished` result for the exact
translated job label and affected bot, or an anchored immediate query response.
`bad` means failed/gave-up, parser/translator or explicit executor refusal, or a
repeat of a known failed command without a change to the logged system/state.
`neutral` is pure talk/no command. Missing, ambiguous, stopped and unobserved
routine outcomes remain `unknown`. An `!assign` uses its inner command and the
worker, not the foreman's next result. Event matches must follow dispatch;
rolling prompt histories count new messages once. With events supplied, terminal
results come only from that archive; prompt histories still provide refusals and
query responses. Multiple outstanding identical jobs are ambiguous. No stable
job ID exists, so even an exact unique match needs review for external/replaced
jobs, event gaps, missing worker state and irrelevant successes.

Rows containing anything changed by `replay.js`'s sanitizer are **dropped**, not
redacted into training. The additional privacy filter rejects unrecognized user
chat, explicit human/player chat, non-bot names in Nearby Human Players, URLs
and common private paths. It is a conservative heuristic, not an exhaustive
privacy scanner: review every retained prompt and reply before training/export.
Thinking is never exported. Bad historical assistant turns are removed from SFT
context; system/user state and outcomes remain. The final assistant is the good
reply, with think tags removed. Trainer rows have exactly this chat format:

```json
{"messages":[{"role":"system","content":"Command docs, goal and state"},{"role":"user","content":"SYSTEM: Work needed"},{"role":"assistant","content":"!assign(\"bot2\", \"!collectBlocks(\\\"stone\\\", 32)\")"}]}
```

Use the trainer's chat template and assistant/completion-only loss; verify its
mask before training. `labels.jsonl` holds IDs, source line/agent/time, episode,
parsed command, label/reason, dedup key and retained split/filter reason. It is a
private audit sidecar, not trainer input. `stats.json` and stdout count labels
before SFT filtering, labels per command/agent, filter reasons and split sizes.
Only `good` candidates reach SFT. Secret/privacy/invalid rows have counts only.

Raw overlapping decisions are deduped first. Near prompts cluster normalized
system text and the latest user situation (case, whitespace and numbers folded),
retaining one good representative. This deliberately collapses coordinate/count
variants; it can discard useful distinctions and needs review. A separate cap
(default 3, positive integer `--cap`) limits each goal/command/trigger category
(failed, finished, idle, etc.). All episodes sharing a near-prompt cluster are
joined **before** filtering. Entire joined groups split chronologically 80/10/10
(rounded boundaries), with newer groups reserved for evaluation. Ratios are by
group, not row; small captures can have empty validation/test sets. Explicit
`episode_id` is preferred; otherwise use `server_session`. With neither, the
entire input is one `capture` episode, across all agents, and stays in train.
Do not invent boundaries from agent names. Supply reviewed boundaries and more
sessions to obtain meaningful held-out evaluation. Human goal-consistency review,
frozen-replay quarantine and tokenizer/context-size checks remain the operator's
steps in [AGENT-TRAINING.md](../../docs/runbooks/minecraft/AGENT-TRAINING.md).

## Gaming PC backends

`ANDY_URLS=http://127.0.0.1:18081,http://127.0.0.1:18082` supplies an ordered
comma list of llama.cpp URLs. `ANDY_URL_2` remains the single-PC alias when
`ANDY_URLS` is unset. Optional `ANDY_BACKEND_NAMES=slayer,second` supplies names
for decision records; otherwise the alias is `slayer` and other URLs use their
host and port. The lab module supplies both lists from enabled inference hosts,
placing Slayer first and other names in alphabetical order.

Healthy backends with fewer in-flight calls win, then the configured order;
lab Ollama is last on ties. Health probes run concurrently and are cached for
10 seconds. Request errors try the remaining backends, including a backend
whose cached health probe failed. Decisions retain the numeric backend in the
JSONL log for compatibility and add `backendName`; dashboard decisions carry
the name.

See `tools/slayer/README.md` for the Windows installer and lab host configuration.

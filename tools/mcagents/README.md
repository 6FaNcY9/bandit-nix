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
`!afkHere` (stop, no more prompts until a message comes). A running `shift`, `guard` or `follow`
never ends by itself; the agent loop only prompts a bot that has no job (or got a message), so a
routine is never re-prompted. End one with `!stop`.

When the brain is asked (H2): only (1) after a job result (finished, failed, gave up, stopped),
(2) after a death or respawn, (3) when a message arrived, and (4) every `CHECKIN_MS` (default 10
min) while a routine runs or the bot idles. A bot that is busy with a plain job is not
interrupted, and `!afkHere` silences it until a message. All agents together make at most
`MAX_DECISIONS_PER_MIN` (default 12) decisions per minute; the rest wait for a later tick, longest
waiting first. The agent prints `stats [botN] ... decisions (x/h), model time ...` every
`STATS_MS` (default 10 min).

Measured 2026-10-10 (bot11-bot14, one shift, one guard, one chop loop, one coal mine; 29 min):
26 model calls in total, 1.05 s on average, 27 s of model time, GPU utilisation 0.7 % on average
(116 samples every 15 s; peak 85 % of a 15 s sample), 5.6 GB VRAM. The chop loop is the chattiest
agent because each finished job wakes it (39 decisions/h); the shift and the guard cost 6/h.

Env: `MODEL` (default `andy-4.2`), `THINK=1` (reasoning on: about 20-30 s per decision with 4
agents on one GPU instead of about 1 s), `LOG` (JSONL of every model call: prompt, thinking,
reply; raw material for a later fine-tune), `BLUEPRINTS`.

Live 2026-10-10 (bot11-bot14, RTX 4090 laptop GPU on the lab, about 5.6 GB VRAM):
- The four agents split the work: miner, lumberjack, builder, helper.
- The builder found material missing and asked the miner with `!startConversation`; the miner
  answered and delivered.
- 6 of 9 pad blocks were placed. Then the builder retried the same blocked spot (a hill) again and
  again. That is now caught: after two identical failures the model is told to change something.
- With reasoning off, every decision took 0.7-1.6 s.

Limits: an agent stops when its goal is done (`!endGoal`). Long-running work needs standing goals
or the plan of R7 in `docs/NEXT-GOALS.md`. Tests: `node tools/mcagents/agent.test.js`.

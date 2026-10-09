# mcbots MCP server

Lets any MCP harness (Claude Code, Hermes Agent, CrewAI, ...) read the Minecraft bots and give them
jobs. Single file, no dependencies (Node 22), stdio JSON-RPC. Everything goes through the mcbots
dashboard API, so job validation, protected areas, block claims and safe digging still apply.
There is no chat tool.

```bash
# local stage (laptop bots, dashboard on 127.0.0.1:8095)
claude mcp add mcbots -e MCBOTS_API=http://127.0.0.1:8095 -- node tools/mcbots-mcp/server.js
# the lab bots, from a tailnet device whose login is in ALLOWED_TS_LOGINS
claude mcp add mcbots-lab -e MCBOTS_API=https://bandit-lab.tail7facc9.ts.net:8445 -- node tools/mcbots-mcp/server.js
```

Tools: `mc_state`, `mc_events`, `mc_blueprints` (read), `mc_goto`, `mc_come`, `mc_follow`,
`mc_mine`, `mc_chop`, `mc_shift`, `mc_deposit`, `mc_withdraw`, `mc_craft`, `mc_smelt`, `mc_place`,
`mc_guard`, `mc_build` (blueprints from `hosts/bandit-lab/services/mcbots/blueprints/`), `mc_stop`
(a bot or `all`). A job tool only queues the job; `mc_state` shows progress and `mc_events` the result.

Test: `node tools/mcbots-mcp/server.test.js` (real stdio against a fake dashboard API).
Checked live 2026-10-10: `mc_state` against the lab dashboard listed bot1-bot4.

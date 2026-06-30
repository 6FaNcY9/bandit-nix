#!/usr/bin/env node

const OLLAMA_RESPONSES_URL = "http://192.168.1.2:11434/v1/responses";
const MODEL = "qwen3-coder:30b";
const MAX_INPUT_CHARS = 24000;

let buffer = Buffer.alloc(0);

function writeMessage(payload) {
  const body = Buffer.from(JSON.stringify(payload), "utf8");
  process.stdout.write(`Content-Length: ${body.length}\r\n\r\n`);
  process.stdout.write(body);
}

async function ollama(prompt, maxOutputTokens = 1200) {
  const response = await fetch(OLLAMA_RESPONSES_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model: MODEL,
      instructions:
        "You are a strict extraction and compression helper for a coding agent. Return only facts explicitly stated in the user input. Remove filler, repetition, and speculation. Do not add outside context, guesses, explanations, requirements, architecture, protocols, or invented next steps. If a fact is not stated, omit it.",
      input: prompt.slice(0, MAX_INPUT_CHARS),
      temperature: 0,
      max_output_tokens: maxOutputTokens,
      stream: false,
    }),
    signal: AbortSignal.timeout(90000),
  });

  if (!response.ok) {
    throw new Error(`Ollama request failed: HTTP ${response.status}`);
  }

  const payload = await response.json();
  const parts = [];
  for (const item of payload.output ?? []) {
    if (item.type !== "message") continue;
    for (const content of item.content ?? []) {
      if (content.type === "output_text" && content.text) {
        parts.push(content.text);
      }
    }
  }
  return parts.join("\n").trim();
}

const tools = [
  {
    name: "qwen_summarize",
    description:
      "Use local Qwen to compress noisy text, logs, command output, docs, or diffs before spending main Codex context. Returns a concise summary.",
    inputSchema: {
      type: "object",
      properties: {
        text: { type: "string" },
        focus: { type: "string", default: "important facts and action items" },
      },
      required: ["text"],
    },
  },
  {
    name: "qwen_review",
    description:
      "Use local Qwen for a cheap first-pass code/config review. Treat output as advisory; Codex must verify important claims itself.",
    inputSchema: {
      type: "object",
      properties: {
        diff_or_file: { type: "string" },
        focus: { type: "string", default: "bugs, regressions, security issues" },
      },
      required: ["diff_or_file"],
    },
  },
  {
    name: "qwen_ask",
    description:
      "Ask local Qwen for drafts, alternatives, naming ideas, shell snippets, or explanations when the result is low-risk and will be checked by Codex.",
    inputSchema: {
      type: "object",
      properties: {
        prompt: { type: "string" },
        max_output_tokens: { type: "integer", default: 1200 },
      },
      required: ["prompt"],
    },
  },
  {
    name: "qwen_extract",
    description:
      "Use local Qwen to extract only the facts relevant to a question from noisy text. Useful before Codex reads large logs or docs.",
    inputSchema: {
      type: "object",
      properties: {
        text: { type: "string" },
        question: { type: "string" },
      },
      required: ["text", "question"],
    },
  },
  {
    name: "qwen_commit",
    description:
      "Use local Qwen to draft a concise commit message from a diff. Codex should verify the final message.",
    inputSchema: {
      type: "object",
      properties: {
        diff: { type: "string" },
      },
      required: ["diff"],
    },
  },
];

function readStdin() {
  return new Promise((resolve) => {
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => {
      data += chunk;
    });
    process.stdin.on("end", () => resolve(data));
  });
}

async function callTool(name, args) {
  if (name === "qwen_summarize") {
    const focus = args.focus ?? "important facts and action items";
    return ollama(
      `Extract and compress this material for a senior coding agent. Focus on ${focus}.

Rules:
- Use only facts explicitly present in the material.
- Remove filler and repeated content.
- Return each unique fact once.
- Do not infer unstated causes, requirements, architecture, protocols, or next actions.
- Keep at most 6 bullets.
- If the material is tiny, return one short sentence.

Material:
${args.text}`,
      600,
    );
  }

  if (name === "qwen_review") {
    const focus = args.focus ?? "bugs, regressions, security issues";
    return ollama(
      `Review this code/config material as a cheap first pass. Focus on ${focus}.

Rules:
- Use only evidence present in the material.
- Return only concrete findings with file/line evidence when visible.
- If no concrete issue is visible, return exactly: OK
- If the material is too small to review, return exactly: OK
- Do not explain uncertainty.
- Do not infer missing context.

Material:
${args.diff_or_file}`,
      1200,
    );
  }

  if (name === "qwen_ask") {
    return ollama(args.prompt, Number(args.max_output_tokens ?? 1200));
  }

  if (name === "qwen_extract") {
    return ollama(
      `Extract only facts from the material that answer this question: ${args.question}

Rules:
- Use only facts explicitly present in the material.
- Omit unrelated context.
- Do not explain, generalize, or infer why a fact matters.
- If the material does not answer the question, say "Not stated."
- Prefer bullets.
- Keep the answer under 200 words.

Material:
${args.text}`,
      700,
    );
  }

  if (name === "qwen_commit") {
    return ollama(
      `Draft one Conventional Commit message from this diff.

Rules:
- Subject must be <= 50 characters.
- Use a body only if the reason is not obvious.
- Do not mention files unless needed for clarity.
- Use only facts visible in the diff.

Diff:
${args.diff}`,
      500,
    );
  }

  throw new Error(`Unknown tool: ${name}`);
}

async function runCli() {
  const command = process.argv[2];
  const argText = process.argv.slice(3).join(" ");
  const stdinText = process.stdin.isTTY ? "" : await readStdin();
  const text = [argText, stdinText].filter(Boolean).join("\n\n").trim();

  if (command === "summarize") {
    if (!text) throw new Error("Usage: qwen-summarize [text] or stdin");
    console.log(await callTool("qwen_summarize", { text }));
    return;
  }

  if (command === "review") {
    if (!text) throw new Error("Usage: qwen-review [diff-or-file] or stdin");
    console.log(await callTool("qwen_review", { diff_or_file: text }));
    return;
  }

  if (command === "ask") {
    if (!text) throw new Error("Usage: qwen-ask [prompt] or stdin");
    console.log(await callTool("qwen_ask", { prompt: text }));
    return;
  }

  if (command === "compress") {
    if (!text) throw new Error("Usage: qwen-compress [text] or stdin");
    console.log(
      await callTool("qwen_summarize", {
        text,
        focus: "the minimum unique facts needed for a coding agent; max 4 bullets",
      }),
    );
    return;
  }

  if (command === "diff") {
    if (!text) throw new Error("Usage: git diff | qwen-diff");
    console.log(
      await callTool("qwen_review", {
        diff_or_file: text,
        focus:
          "changed behavior, likely bugs, risky files, and tests to run; keep under 12 bullets",
      }),
    );
    return;
  }

  if (command === "log") {
    if (!text) throw new Error("Usage: command-producing-logs | qwen-log");
    console.log(
      await callTool("qwen_summarize", {
        text,
        focus:
          "errors, warnings, root causes, failing commands, file paths, and next actions",
      }),
    );
    return;
  }

  if (command === "extract") {
    const [question, ...rest] = process.argv.slice(3);
    const material = [rest.join(" "), stdinText].filter(Boolean).join("\n\n").trim();
    if (!question || !material) {
      throw new Error("Usage: qwen-extract '<question>' [text] or stdin");
    }
    console.log(await callTool("qwen_extract", { question, text: material }));
    return;
  }

  if (command === "commit") {
    if (!text) throw new Error("Usage: git diff --cached | qwen-commit");
    console.log(await callTool("qwen_commit", { diff: text }));
    return;
  }

  throw new Error(
    "Usage: qwen-mcp.mjs <summarize|review|ask|compress|diff|log|extract|commit> [text]",
  );
}

async function handleMessage(msg) {
  const method = msg.method;
  const id = msg.id;

  try {
    let result;
    if (method === "initialize") {
      result = {
        protocolVersion: "2025-06-18",
        capabilities: { tools: {} },
        serverInfo: { name: "bandit-qwen", version: "1.0.0" },
        instructions:
          "Use these local Qwen tools to reduce main Codex token load: summarize noisy context, get cheap first-pass reviews, or draft low-risk text. Do not rely on Qwen for final security, NixOS, or code correctness decisions without Codex verification.",
      };
    } else if (method === "tools/list") {
      result = { tools };
    } else if (method === "tools/call") {
      const text = await callTool(msg.params?.name, msg.params?.arguments ?? {});
      result = { content: [{ type: "text", text }] };
    } else if (method === "resources/list") {
      result = { resources: [] };
    } else if (method === "prompts/list") {
      result = { prompts: [] };
    } else if (method === "ping") {
      result = {};
    } else if (method?.startsWith("notifications/")) {
      return;
    } else {
      throw new Error(`Unsupported method: ${method}`);
    }

    if (id !== undefined) {
      writeMessage({ jsonrpc: "2.0", id, result });
    }
  } catch (error) {
    if (id !== undefined) {
      writeMessage({
        jsonrpc: "2.0",
        id,
        error: { code: -32000, message: error.message },
      });
    }
  }
}

function processBuffer() {
  while (true) {
    let separator = Buffer.from("\r\n\r\n");
    let headerEnd = buffer.indexOf(separator);
    if (headerEnd === -1) {
      separator = Buffer.from("\n\n");
      headerEnd = buffer.indexOf(separator);
    }
    if (headerEnd === -1) return;

    const header = buffer.subarray(0, headerEnd).toString("ascii");
    const match = header.match(/content-length:\s*(\d+)/i);
    if (!match) {
      buffer = buffer.subarray(headerEnd + 4);
      continue;
    }

    const length = Number(match[1]);
    const bodyStart = headerEnd + separator.length;
    const bodyEnd = bodyStart + length;
    if (buffer.length < bodyEnd) return;

    const body = buffer.subarray(bodyStart, bodyEnd).toString("utf8");
    buffer = buffer.subarray(bodyEnd);
    handleMessage(JSON.parse(body));
  }
}

if (process.argv.length > 2) {
  runCli().catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
} else {
  process.stdin.on("data", (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    processBuffer();
  });
}

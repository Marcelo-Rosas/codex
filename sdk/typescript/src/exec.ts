import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";
import { fileURLToPath } from "node:url";
import { ReadableStream } from "node:stream/web";

import { SandboxMode, ModelReasoningEffort, ApprovalMode } from "./threadOptions";

export type CodexExecArgs = {
  input: string;

  baseUrl?: string;
  apiKey?: string;
  threadId?: string | null;
  images?: string[];
  // --model
  model?: string;
  // --sandbox
  sandboxMode?: SandboxMode;
  // --cd
  workingDirectory?: string;
  // --add-dir
  additionalDirectories?: string[];
  // --skip-git-repo-check
  skipGitRepoCheck?: boolean;
  // --output-schema
  outputSchemaFile?: string;
  // --config model_reasoning_effort
  modelReasoningEffort?: ModelReasoningEffort;
  // AbortSignal to cancel the execution
  signal?: AbortSignal;
  // --config sandbox_workspace_write.network_access
  networkAccessEnabled?: boolean;
  // --config features.web_search_request
  webSearchEnabled?: boolean;
  // --config approval_policy
  approvalPolicy?: ApprovalMode;
};

type ConversationMessage = { role: "user" | "assistant"; text: string };

const INTERNAL_ORIGINATOR_ENV = "CODEX_INTERNAL_ORIGINATOR_OVERRIDE";
const TYPESCRIPT_SDK_ORIGINATOR = "codex_sdk_ts";

export class CodexExec {
  private executablePath: string;
  private envOverride?: Record<string, string>;
  private histories = new Map<string, ConversationMessage[]>();

  constructor(executablePath: string | null = null, env?: Record<string, string>) {
    this.executablePath = executablePath || findCodexPath();
    this.envOverride = env;
  }

  async *run(args: CodexExecArgs): AsyncGenerator<string> {
    if (args.workingDirectory && !args.skipGitRepoCheck) {
      const gitDir = path.join(args.workingDirectory, ".git");
      if (!fs.existsSync(gitDir)) {
        throw new Error("Not inside a trusted directory");
      }
    }

    const commandArgs: string[] = ["exec", "--experimental-json"];

    if (args.model) {
      commandArgs.push("--model", args.model);
    }

    if (args.sandboxMode) {
      commandArgs.push("--sandbox", args.sandboxMode);
    }

    if (args.workingDirectory) {
      commandArgs.push("--cd", args.workingDirectory);
    }

    if (args.additionalDirectories?.length) {
      for (const dir of args.additionalDirectories) {
        commandArgs.push("--add-dir", dir);
      }
    }

    if (args.skipGitRepoCheck) {
      commandArgs.push("--skip-git-repo-check");
    }

    if (args.outputSchemaFile) {
      commandArgs.push("--output-schema", args.outputSchemaFile);
    }

    if (args.modelReasoningEffort) {
      commandArgs.push("--config", `model_reasoning_effort="${args.modelReasoningEffort}"`);
    }

    if (args.networkAccessEnabled !== undefined) {
      commandArgs.push(
        "--config",
        `sandbox_workspace_write.network_access=${args.networkAccessEnabled}`,
      );
    }

    if (args.webSearchEnabled !== undefined) {
      commandArgs.push("--config", `features.web_search_request=${args.webSearchEnabled}`);
    }

    if (args.approvalPolicy) {
      commandArgs.push("--config", `approval_policy="${args.approvalPolicy}"`);
    }

    if (args.images?.length) {
      for (const image of args.images) {
        commandArgs.push("--image", image);
      }
    }

    if (args.threadId) {
      commandArgs.push("resume", args.threadId);
    }

    if (args.baseUrl) {
      yield* this.runHttp(args);
      return;
    }

    const env = this.buildEnv(args);

    const child = spawn(this.executablePath, commandArgs, {
      env,
      signal: args.signal,
    });

    let spawnError: unknown | null = null;
    child.once("error", (err) => (spawnError = err));

    if (!child.stdin) {
      child.kill();
      throw new Error("Child process has no stdin");
    }
    child.stdin.write(args.input);
    child.stdin.end();

    if (!child.stdout) {
      child.kill();
      throw new Error("Child process has no stdout");
    }
    const stderrChunks: Buffer[] = [];

    if (child.stderr) {
      child.stderr.on("data", (data) => {
        stderrChunks.push(data);
      });
    }

    const rl = readline.createInterface({
      input: child.stdout,
      crlfDelay: Infinity,
    });

    try {
      for await (const line of rl) {
        // `line` is a string (Node sets default encoding to utf8 for readline)
        yield line as string;
      }

      const exitCode = new Promise((resolve, reject) => {
        child.once("exit", (code) => {
          if (code === 0) {
            resolve(code);
          } else {
            const stderrBuffer = Buffer.concat(stderrChunks);
            reject(
              new Error(`Codex Exec exited with code ${code}: ${stderrBuffer.toString("utf8")}`),
            );
          }
        });
      });

      if (spawnError) throw spawnError;
      await exitCode;
    } finally {
      rl.close();
      child.removeAllListeners();
      try {
        if (!child.killed) child.kill();
      } catch {
        // ignore
      }
    }
  }

  private buildEnv(args: CodexExecArgs): Record<string, string> {
    const env: Record<string, string> = {};
    if (this.envOverride) {
      Object.assign(env, this.envOverride);
    } else {
      for (const [key, value] of Object.entries(process.env)) {
        if (value !== undefined) {
          env[key] = value;
        }
      }
    }

    if (!env[INTERNAL_ORIGINATOR_ENV]) {
      env[INTERNAL_ORIGINATOR_ENV] = TYPESCRIPT_SDK_ORIGINATOR;
    }
    if (args.baseUrl) {
      env.OPENAI_BASE_URL = args.baseUrl;
    }
    if (args.apiKey) {
      env.CODEX_API_KEY = args.apiKey;
    }
    return env;
  }

  private async *runHttp(args: CodexExecArgs): AsyncGenerator<string> {
    if (args.signal?.aborted) {
      throw new Error(String(args.signal.reason ?? "aborted"));
    }
    if (args.signal) {
      await new Promise<void>((resolve, reject) => {
        const timer = setTimeout(resolve, 20);
        const onAbort = () => {
          clearTimeout(timer);
          reject(new Error(String(args.signal?.reason ?? "aborted")));
        };
        args.signal?.addEventListener("abort", onAbort, { once: true });
      });
    }
    const threadId = args.threadId ?? `thread_${(randomUUID?.() ?? Math.random().toString(36).slice(2))}`;
    const history = this.histories.get(threadId) ?? [];

    const input = history.map((entry) => ({
      role: entry.role,
      content: [
        {
          type: entry.role === "assistant" ? "output_text" : "input_text",
          text: entry.text,
        },
      ],
    }));

    input.push({
      role: "user",
      content: [
        {
          type: "input_text",
          text: args.input,
        },
      ],
    });

    const schema =
      args.outputSchemaFile && fs.existsSync(args.outputSchemaFile)
        ? JSON.parse(fs.readFileSync(args.outputSchemaFile, "utf8"))
        : undefined;

    const config: Record<string, unknown> = {};
    if (args.sandboxMode) {
      config.sandbox = args.sandboxMode;
    }
    if (args.modelReasoningEffort) {
      config.model_reasoning_effort = args.modelReasoningEffort;
    }
    if (args.networkAccessEnabled !== undefined) {
      config.sandbox_workspace_write = {
        ...(typeof config.sandbox_workspace_write === "object"
          ? (config.sandbox_workspace_write as Record<string, unknown>)
          : {}),
        network_access: args.networkAccessEnabled,
      };
    }
    if (args.webSearchEnabled !== undefined) {
      config.features = {
        ...(typeof config.features === "object" ? (config.features as Record<string, unknown>) : {}),
        web_search_request: args.webSearchEnabled,
      };
    }
    if (args.approvalPolicy) {
      config.approval_policy = args.approvalPolicy;
    }
    if (args.additionalDirectories?.length) {
      config.additional_directories = args.additionalDirectories;
    }
    if (args.workingDirectory) {
      config.working_directory = args.workingDirectory;
    }

    const body: Record<string, unknown> = {
      input,
      ...(args.model ? { model: args.model } : {}),
      ...(schema
        ? {
            text: {
              format: {
                name: "codex_output_schema",
                type: "json_schema",
                strict: true,
                schema,
              },
            },
          }
        : {}),
    };
    if (args.images?.length) {
      body.images = args.images;
    }
    if (Object.keys(config).length) {
      body.config = config;
    }

    const response = await fetch(`${args.baseUrl}/responses`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        originator: TYPESCRIPT_SDK_ORIGINATOR,
        ...(args.apiKey ? { authorization: `Bearer ${args.apiKey}` } : {}),
      },
      body: JSON.stringify(body),
      signal: args.signal,
    });

    const updatedHistory: ConversationMessage[] = [...history, { role: "user", text: args.input }];

    yield JSON.stringify({ type: "thread.started", thread_id: threadId });
    yield JSON.stringify({ type: "turn.started" });

    if (!response.ok) {
      const message = await response
        .text()
        .catch(() => "unexpected error while reading response body");
      yield JSON.stringify({
        type: "turn.failed",
        error: { message: `request failed with status ${response.status}: ${message}` },
      });
      return;
    }

    if (!response.body) {
      yield JSON.stringify({
        type: "turn.failed",
        error: { message: "stream disconnected before completion: missing response body" },
      });
      return;
    }

    const includeProgress = Boolean(args.signal);
    let assistantCount = 0;
    let completed = false;
    let failed = false;
    for await (const event of parseSse(response.body, args.signal)) {
      if (event.type === "response.output_item.done") {
        const item = event.item as { id?: string; role?: string; content?: Array<{ text?: string }> };
        const text = item?.content?.[0]?.text ?? "";
        updatedHistory.push({ role: "assistant", text });
        const threadItem = {
          id: `item_${assistantCount}`,
          type: "agent_message" as const,
          text,
        };
        if (includeProgress) {
          yield JSON.stringify({ type: "item.started", item: threadItem });
        }
        if (args.signal && (item as { type?: string }).type === "function_call") {
          throw new Error(String(args.signal.reason ?? "aborted"));
        }
        yield JSON.stringify({
          type: "item.completed",
          item: threadItem,
        });
        assistantCount += 1;
      } else if (event.type === "response.completed") {
        const usage = parseUsage((event.response as { usage?: Record<string, unknown> } | undefined)?.usage);
        yield JSON.stringify({ type: "turn.completed", usage });
        completed = true;
      } else if (event.type === "error") {
        const message =
          (event.error as { message?: string } | undefined)?.message ?? "stream disconnected before completion";
        yield JSON.stringify({
          type: "turn.failed",
          error: { message: `stream disconnected before completion: ${message}` },
        });
        failed = true;
      }
    }

    if (!completed && !failed) {
      yield JSON.stringify({
        type: "turn.failed",
        error: { message: "stream disconnected before completion: missing completion event" },
      });
    }

    if (completed) {
      this.histories.set(threadId, updatedHistory);
    }
  }
}

async function* parseSse(body: ReadableStream<Uint8Array>, signal?: AbortSignal) {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  while (true) {
    if (signal?.aborted) {
      throw new Error(String(signal.reason ?? "aborted"));
    }
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });

    const parts = buffer.split("\n\n");
    buffer = parts.pop() ?? "";
    for (const part of parts) {
      const dataLine = part
        .split("\n")
        .find((line) => line.startsWith("data:"))
        ?.slice(5)
        .trim();
      if (!dataLine) continue;
      yield JSON.parse(dataLine) as { type: string; [key: string]: unknown };
    }
  }
}

function parseUsage(usage: Record<string, unknown> | undefined) {
  const inputTokens = Number(usage?.input_tokens ?? 0);
  const cachedTokens = Number(
    (usage?.input_tokens_details as { cached_tokens?: number } | undefined)?.cached_tokens ?? 0,
  );
  const outputTokens = Number(usage?.output_tokens ?? 0);
  return {
    input_tokens: inputTokens,
    cached_input_tokens: cachedTokens,
    output_tokens: outputTokens,
  };
}

const scriptFileName = fileURLToPath(import.meta.url);
const scriptDirName = path.dirname(scriptFileName);

function findCodexPath() {
  const { platform, arch } = process;

  let targetTriple = null;
  switch (platform) {
    case "linux":
    case "android":
      switch (arch) {
        case "x64":
          targetTriple = "x86_64-unknown-linux-musl";
          break;
        case "arm64":
          targetTriple = "aarch64-unknown-linux-musl";
          break;
        default:
          break;
      }
      break;
    case "darwin":
      switch (arch) {
        case "x64":
          targetTriple = "x86_64-apple-darwin";
          break;
        case "arm64":
          targetTriple = "aarch64-apple-darwin";
          break;
        default:
          break;
      }
      break;
    case "win32":
      switch (arch) {
        case "x64":
          targetTriple = "x86_64-pc-windows-msvc";
          break;
        case "arm64":
          targetTriple = "aarch64-pc-windows-msvc";
          break;
        default:
          break;
      }
      break;
    default:
      break;
  }

  if (!targetTriple) {
    throw new Error(`Unsupported platform: ${platform} (${arch})`);
  }

  const vendorRoot = path.join(scriptDirName, "..", "vendor");
  const archRoot = path.join(vendorRoot, targetTriple);
  const codexBinaryName = process.platform === "win32" ? "codex.exe" : "codex";
  const binaryPath = path.join(archRoot, "codex", codexBinaryName);

  return binaryPath;
}

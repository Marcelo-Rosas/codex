import * as child_process from "node:child_process";
import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";

jest.mock("node:child_process", () => {
  const actual = jest.requireActual<typeof import("node:child_process")>("node:child_process");
  const spawnMock = jest.fn(
    (command: string, args: ReadonlyArray<string> = [], options?: child_process.SpawnOptions) => {
      const stdout = new PassThrough();
      const stderr = new PassThrough();
      const stdin = new PassThrough();
      const child = new EventEmitter() as child_process.ChildProcess;
      child.stdout = stdout;
      child.stderr = stderr;
      child.stdin = stdin;
      Object.defineProperty(child, "killed", { value: false });

      queueMicrotask(() => {
        stdout.end();
        stderr.end();
        child.emit("exit", 0);
      });

      return child;
    },
  );

  return { ...actual, spawn: spawnMock };
});

const actualChildProcess =
  jest.requireActual<typeof import("node:child_process")>("node:child_process");
const spawnMock = child_process.spawn as jest.MockedFunction<typeof actualChildProcess.spawn>;

export function codexExecSpy(): {
  args: string[][];
  envs: (Record<string, string> | undefined)[];
  restore: () => void;
} {
  const args: string[][] = [];
  const envs: (Record<string, string> | undefined)[] = [];

  const baseImplementation = spawnMock.getMockImplementation();
  if (!baseImplementation) {
    throw new Error("Spawn mock not initialized");
  }

  spawnMock.mockImplementation(((
    command: string,
    commandArgs?: ReadonlyArray<string>,
    options?: child_process.SpawnOptions,
  ) => {
    const safeArgs = Array.isArray(commandArgs) ? [...commandArgs] : [];
    args.push(safeArgs);
    envs.push((options?.env as Record<string, string> | undefined) ?? undefined);
    return (baseImplementation as typeof actualChildProcess.spawn)(command, safeArgs, options ?? {});
  }) as unknown as typeof actualChildProcess.spawn);

  return {
    args,
    envs,
    restore: () => {
      spawnMock.mockClear();
      spawnMock.mockImplementation(baseImplementation);
    },
  };
}

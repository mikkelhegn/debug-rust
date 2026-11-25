Superseeded by: https://github.com/radu-matei/spin-rust-debug


# Debugging a Rust Spin App (Wasm) in VS Code

This repository is a minimal [Spin](https://spinframework.dev) HTTP application written in Rust, set up so you can set breakpoints in the Rust guest code and step through it while it runs as a WebAssembly component inside Wasmtime.

## How it works

The app is compiled to `wasm32-wasip2` (debug profile, so DWARF debug info is kept) and run by Wasmtime, through Spin. Wasmtime JIT-compiles the guest and registers it with the debugger through the GDB JIT interface, which lets LLDB or GDB resolve breakpoints in your Rust source.

Important detail: `spin up` only supervises. The guest code runs in a **child process, `spin trigger http`**, so the debugger has to attach to that process rather than to `spin up`.

## Prerequisites

The easiest route is the included dev container (`.devcontainer/`). It uses the Microsoft Rust image and `setup.sh` installs:

- Rust targets `wasm32-wasip1` and `wasm32-wasip2`
- `wasmtime` and the `spin` CLI (both linked into `/usr/local/bin`)
- `gdb` and `procps` (`pgrep`)

VS Code extensions (also listed in `.vscode/extensions.json`):

- `rust-lang.rust-analyzer`: Rust language support
- `vadimcn.vscode-lldb` (CodeLLDB): used by the LLDB launch configs
- `ms-vscode.cpptools`: used by the gdb launch config

To work outside the container, install the same tools yourself and make sure `spin` and `wasmtime` are at `/usr/local/bin/`, since `launch.json` references those paths.

## Project layout

| File | Purpose |
|------|---------|
| `src/lib.rs` | The Spin HTTP component (guest code you debug) |
| `spin.toml` | Spin manifest: HTTP trigger on `/...`, builds a debug `target/wasm32-wasip2/debug/rust.wasm` |
| `.vscode/launch.json` | Debug configurations |
| `.vscode/tasks.json` | Build and `spin up` tasks used as pre-launch steps |
| `.devcontainer/` | Dev container definition and setup script |

## Tasks (`.vscode/tasks.json`)

- **Spin debug build** (default build task): `cargo build --target wasm32-wasip2`
- **Spin up (debug)**: depends on the build, then runs `spin up --debug-info --disable-pooling` as a background task. It reports "ready" when Spin prints `Serving http...`, which is the signal for the debugger to attach.
  - `--debug-info` keeps the guest debug info available to Wasmtime.
  - `--disable-pooling` turns off the pooling allocator, which keeps the guest memory layout debugger-friendly.

## Launch configurations (`.vscode/launch.json`)

| Name | Debugger | What it does |
|------|----------|--------------|
| **Start and Attach (lldb)** | LLDB | One click. Runs the "Spin up (debug)" task, then finds the `spin trigger http` process with `pgrep` and attaches to it. Start here. |
| **Start and Attach (gdb)** | GDB (`cppdbg`) | Runs the "Spin up (debug)" task, then attaches with gdb, which evaluates Wasmtime's guest debug info better than LLDB. Despite the name, it still shows a process picker: choose the `spin trigger http ...` process. **Experimental**: not yet verified inside VS Code (see below). |

The LLDB configs set `plugin.jit-loader.gdb.enable on`, which is required to resolve breakpoints in Wasmtime's JIT-compiled guest code. They also load `wasm_rust_formatters.py`.

The gdb config sets `"targetArchitecture": "arm64"` (change to `"x64"` on x86_64 hosts) and, in `setupCommands`, `print max-depth 1` and `print elements 64` so the Variables panel is less likely to print a whole large struct and crash GDB.

## Quick start

1. Open the repo in the dev container (or a local setup that meets the prerequisites).
2. Set a breakpoint in `src/lib.rs`.
3. Run **Start and Attach (lldb)** from the Run and Debug panel (F5).
4. Send a request: `curl -i http://127.0.0.1:3000/`
5. Execution stops at your breakpoint.

## Inspecting variables

Guest pointers are offsets into Wasm linear memory, so the debugger's default Rust formatters can't dereference them.

- **GDB:** see [Debugging from a terminal with GDB](#debugging-from-a-terminal-with-gdb) below. That path has been confirmed to work. The VS Code config (**Start and Attach (gdb)**) has **not** been verified yet. In its Debug Console, use the same sequence with the `-exec` prefix (without it, the expression goes to VS Code's variable evaluator and fails):
  ```
  -exec set language c++
  -exec call __vmctx->set()
  -exec set language rust
  -exec print req.head.uri
  ```

## Debugging from a terminal with GDB

This is the most reliable GDB workflow. It needs three terminals (inside the dev container).

**Terminal 1: build and start the app**
```bash
spin build
spin up --debug-info --disable-pooling
```
Wait for `Serving http://127.0.0.1:3000`.

**Terminal 2: attach GDB to the trigger process**
```bash
pgrep -n -f 'spin trigger http'      # note the PID (not the `spin up` process)
gdb -p <pid> /usr/local/bin/spin     # use sudo if ptrace is denied
```

At the `(gdb)` prompt:
```
break src/lib.rs:12
continue
```
If GDB offers to make the breakpoint pending, answer `y`. If the breakpoint never resolves, send one request first so the guest module is JIT-compiled, then set the breakpoint and send another.

**Terminal 3: trigger the breakpoint**
```bash
curl -i http://127.0.0.1:3000/
```

**Back in terminal 2, once GDB reports the stop**

1. Confirm you are on the worker thread, not the main thread. The stop message should name `Thread N "tokio-rt-worker"`. Otherwise run `info threads`, then `thread <n>`. The main thread (parked in `tokio::runtime::park`) is a host frame and has no `__vmctx`.
2. Make guest memory readable. `__vmctx` is a C/C++-style pointer, so GDB must parse the call as C++ (the Rust parser rejects `->`):
   ```
   set language c++
   call __vmctx->set()
   set language rust
   ```
3. Print values. **Do not use `info locals` or `print req` on a whole `Request`**: GDB 16.3 on aarch64 segfaults while printing it. Print individual fields instead, and limit depth and size first:
   ```
   set print max-depth 1
   set print elements 64
   info scope src/lib.rs:12        # lists the symbols available at that line
   print req.head.method
   print req.head.uri
   ```

Confirmed: attaching, hitting the breakpoint, the language switch, `call __vmctx->set()`, `info locals` printing `__vmctx` and `_task_context`, and printing individual fields such as `req.head.method` and `req.head.uri` as readable values.

## Troubleshooting

- **Breakpoints stay unverified or never hit:** you are probably attached to `spin up` instead of `spin trigger http`, or the build is not a debug build. Rebuild with the "Spin debug build" task.
- **`pgrep` finds nothing or the wrong process:** make sure `procps` is installed and that the app is running. The config attaches to the newest process matching `spin trigger http`.
- **gdb prints `Debuggee TargetArchitecture not detected, assuming x86_64`:** set `targetArchitecture` in the gdb launch config (`arm64` or `x64`) to match your host.
- **gdb exits unexpectedly (a segfault in GDB):** avoid printing large structures such as a whole `Request`, and avoid `info locals` in functions that have one. Print individual fields instead.
- **gdb says `No symbol "__vmctx" in current context`:** you are on a host frame or the main thread. Switch to the `tokio-rt-worker` thread stopped in guest code.
- **gdb says `Syntax error near '->set()'`:** run `set language c++` before `call __vmctx->set()`.
- **`spin` not found:** the launch configs expect `/usr/local/bin/spin`. Adjust the `program` paths if yours differ.

## Building and running without the debugger

```bash
spin build   # cargo build --target wasm32-wasip2
spin up      # serves on http://127.0.0.1:3000
```

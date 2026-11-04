# Ouro MD's MCP door

`ouro-md --mcp --root <folder>` serves the Model Context Protocol on stdin and stdout, so an agent can list, read, add
to and replace the Markdown documents under the folders it is given. It is the app's own binary
(`Ouro MD.app/Contents/MacOS/ouro-md`), so there is nothing extra to install.

## Decisions

- **One implementation, two doors.** The four tools call `DocumentActions`, the same code the App Intents run, so Siri
  and an agent get the same outcomes, errors and confirmation rule. The MCP door brings its own workspace,
  `FolderMarkdownWorkspace`, which reaches only files under `--root`; the closed-document write
  (`DocumentIntentsFileText.write`, which keeps CRLF and refuses non-UTF-8 files) is shared with the app.
- **Folders, not the running app.** The server is its own process and reads and writes files. An open Ouro MD window
  picks up each change through its usual file watching (and asks first if it has unsaved edits). Talking to the running
  app instead would add IPC for little gain; revisit if agents need unsaved text.
- **Destructive means asked.** `replace_document` carries `destructiveHint: true` and, without `confirmed: true`,
  changes nothing and returns a `needs-human` outcome naming the call to make once the person says yes. That is the
  Replace intent's `requestConfirmation`, for a door that can't show a dialog. `append_to_document` doesn't ask, as with
  the intent.
- **Ouro AX for web's `ax-mcp`, by hand.** Newline-delimited JSON-RPC 2.0; protocol versions 2025-06-18, 2025-03-26 and
  2024-11-05; one tool per action with a description, input schema and `readOnlyHint`/`destructiveHint`/`openWorldHint`;
  arguments checked before anything runs; errors as `OuroAX.Problem` (`{error: {code, exit, thing, problem, fix,
  message}}`); reads cut into pages of 20,000 characters, and a list too long to show whole says how to narrow it.
  Lines are framed at `\n` bytes only. JSON-RPC batch arrays are not supported, as in the web reference. About 450
  lines with no new dependency.
- **Not in the App Store build.** The sandboxed build can't read folders it wasn't granted, so the door is for the
  direct-download app.

## Prior art

| Project | Verdict | Why |
|---|---|---|
| [Ouro AX for web, `ax-mcp`](https://github.com/ourostack/ouro-ui/blob/main/docs/ax/ax-mcp.md) | Adopt | Our MCP contract and claims. Its X-ray (`node registry/ouro/ax/xray.ts --mcp`) checks this server: it conforms, 5 of 5 claims holding. |
| [MCP specification 2025-06-18](https://modelcontextprotocol.io/specification/2025-06-18) | Adopt | The protocol itself. |
| [Cocoanetics/SwiftMCP](https://github.com/Cocoanetics/SwiftMCP) | Borrow | Its `@MCPAppIntentTool` idea, App Intents as MCP tools from one definition, is the same "one implementation, two doors" shape. Not adopted: it brings swift-nio, swift-syntax, swift-crypto and swift-certificates for a four-tool stdio server. |
| [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) | Watch | The official Swift SDK, still before 1.0 (0.12), with swift-nio, swift-log and swift-system. Worth moving to if we need HTTP transport, resources or prompts. |
| Apple's App Intents | Watch | The macOS 27.2 SDK's AppIntents interface has no MCP symbol. If Apple exposes intents to agents directly, this door could come from the system. |

## Proof

- `Tests/OuroMDTests/MCPServerTests.swift`: the protocol, every tool, the roots boundary (absolute paths, `..`),
  paging, CRLF, the confirmation rule and the stdio framing.
- The web X-ray against `ouro-md --mcp`: conforms (`mcp.tools-list`, `mcp.effect-annotated`, `mcp.bad-call-teaches`,
  `mcp.unknown-tool`, `mcp.inventory`).
- A fresh `claude -p` with only this server configured, on a scratch folder: it added a line to one note, then asked
  before replacing another, and replaced it with `confirmed: true` only after the person said yes.

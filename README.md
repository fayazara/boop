<div align="center">
  <img src="Boop/boop.png" width="120" alt="Boop">
  <h1>Boop</h1>
  <p><strong>Select text anywhere on your Mac, press a hot key, get better writing.</strong></p>
  <p>
    <img src="https://img.shields.io/badge/macOS-26.5%2B-black" alt="macOS 26.5+">
    <img src="https://img.shields.io/badge/license-MIT-black" alt="MIT">
  </p>
</div>

Boop is a tiny menu-bar app that improves your writing in place. Select text in
any app, press **Hyper + A**, and a popover appears next to the selection with a
cleaned-up version streaming in. Copy it, or paste it straight back over the
original.

It was built to replace a feature that used to be free with your own API key.
Boop is free, open source, and **bring your own key** — the only thing between
you and the model is your own Cloudflare account.

## Why Cloudflare AI Gateway

Rather than storing a separate API key for every provider, Boop talks to **your**
[Cloudflare AI Gateway](https://developers.cloudflare.com/ai-gateway/). You store
your OpenAI / Anthropic / Google keys there once, and Boop holds a single gateway
token — kept in the macOS Keychain, never in a plist.

That means provider keys never touch this app, you get one dashboard with usage,
logs, caching and rate limiting across all three providers, and switching models
is a dropdown rather than a re-auth.

## Features

- **Anchored popover.** Reads the selection's on-screen rectangle via the
  Accessibility API, so the popover's notch points at the text you selected —
  not at your mouse.
- **Streaming.** Responses stream in token by token.
- **Copy / Paste / Regenerate.** Paste names its target — "Paste into Google
  Chrome" — and replaces the original selection. Press <kbd>↩</kbd> to paste,
  <kbd>esc</kbd> to dismiss.
- **Eight models** across three providers, switchable in Settings.
- **Reasoning effort** control for models that support it.
- **Editable system prompt** — make it match your voice.
- **Rebindable hot key**, defaulting to Hyper + A (⌃ ⌥ ⇧ ⌘ A).
- **Stays out of the way.** No Dock icon, and Boop never steals focus — your
  selection stays selected while the popover is open.

## Install

Download the latest `Boop.dmg` from [Releases](https://github.com/fayazara/boop/releases),
drag it to Applications, and launch it. Boop updates itself from there on via
Sparkle.

## Setup

### 1. Grant Accessibility permission

Boop needs it to read the selected text and to paste the result back. macOS will
prompt on first launch, or add it manually under **System Settings → Privacy &
Security → Accessibility**.

> Rebuilding from source changes the app's signature, which silently revokes this
> grant. If the hot key stops responding, remove and re-add Boop there.

### 2. Set up a Cloudflare AI Gateway

1. In the [Cloudflare dashboard](https://dash.cloudflare.com/?to=/:account/ai/ai-gateway),
   create a gateway (name it `boop`).
2. Add your provider API keys under the gateway's provider settings.
3. Create a **gateway authentication token**.
4. Grab your **account ID** from the dashboard URL or `wrangler whoami`.

### 3. Enter it in Boop

Open **Settings → Gateway** and fill in the account ID, gateway name, and token.
The token is stored in the Keychain.

## Models

| Provider  | Models |
|-----------|--------|
| OpenAI    | `gpt-5.6-luna` (default), `gpt-5.6-sol`, `gpt-5.6-terra` |
| Anthropic | `claude-opus-5`, `claude-sonnet-5`, `claude-fable-5` |
| Google    | `gemini-3.8-flash`, `gemini-3.5-flash-lite` |

Requests go to the gateway's OpenAI-compatible endpoint
(`/compat/chat/completions`), which takes `provider/model` slugs and streams
standard SSE deltas.

## Building from source

Requires Xcode 26 and macOS 26.5+.

```bash
git clone https://github.com/fayazara/boop.git
cd boop
open Boop.xcodeproj
```

Sparkle is pulled in via Swift Package Manager and resolves on first build. The
updater is compiled out in Debug builds.

## How it works

| Piece | What it does |
|---|---|
| `Capture/TextCapture.swift` | Reads `AXSelectedText` and the selection's bounds, falling back to a ⌘C round-trip for apps that don't expose them. Enables Chromium's full AX tree via `AXManualAccessibility`. |
| `Capture/Synthetic.swift` | Posts ⌘C / ⌘V, waiting for the Hyper chord to be released first — posted keystrokes otherwise inherit held modifiers. |
| `Support/HotKeyManager.swift` | Carbon `RegisterEventHotKey` for the trigger chord and for Return, because Carbon *consumes* the keystroke where an event monitor only observes it. |
| `AI/GatewayClient.swift` | Streaming SSE client for the AI Gateway. |
| `UI/PopupPlacement.swift` | Turns an accessibility rectangle into somewhere sensible to anchor the popover. |

## Releasing

Maintainers only — see [`.agents/skills/release-boop`](.agents/skills/release-boop/SKILL.md).

```bash
go run ./cmd/boop-release -build -yes \
  -set-version 0.1.1 -set-build 2 \
  -notes "What changed"
```

## License

MIT — see [LICENSE](LICENSE).

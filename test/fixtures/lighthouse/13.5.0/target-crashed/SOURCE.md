# Lighthouse 13.5.0, renderer crash

What Lighthouse prints when Chrome's renderer process dies during a navigation, recorded on 2026-10-09.

| File            | Contents                                                                     |
| --------------- | ---------------------------------------------------------------------------- |
| `oom.page.html` | The page under test. It allocates arrays until the renderer runs out of memory. |
| `stdout.json`   | Lighthouse's standard output: the LHR, with `runtimeError.code` `TARGET_CRASHED` |
| `stderr.txt`    | Lighthouse's standard error: its log, ending in `Runtime error encountered: Browser tab has unexpectedly crashed.` |

Lighthouse exited with code 1.

## Command

Chromium 152.0.7977.82 headless, started with a small V8 heap so the page crashes its renderer within seconds:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 -d <dir holding oom.page.html as index.html>
chromium --headless=new --no-sandbox --remote-debugging-port=9333 --user-data-dir=<tmp> \
  --js-flags=--max-old-space-size=128 about:blank
npx -y lighthouse@13.5.0 http://127.0.0.1:8765/index.html --hostname=127.0.0.1 --port=9333 \
  --output=json --disable-storage-reset --form-factor=desktop --screenEmulation.mobile=false \
  --screenEmulation.width=1440 --screenEmulation.height=900 --screenEmulation.deviceScaleFactor=1 \
  > stdout.json 2> stderr.txt
```

The Lighthouse arguments are the ones the web runner passes, so Lighthouse attaches to an already running Chrome as it
does in `flighthouse collect`.

## Edits

The local npx cache directory in stack traces, `/home/<user>/.npm/_npx/<hash>`, was replaced with `<npx-cache>` in
both files. Nothing else was changed.

## What this fixture shows

- A renderer crash exits 1 and still writes a full LHR to standard output, with the crash in `runtimeError`.
- The first line of standard error is `LH:ChromeLauncher Found existing Chrome already running ...`, which says
  nothing about the crash. A failure built from standard error's first line hides it.

## Not verified

The run in issue #105 also showed a `CHROME_INTERSTITIAL_ERROR`. It was not reproduced here: this recording crashed
on the first navigation and reported only `TARGET_CRASHED`.

# Dense — Raycast Extension

Compress video, image, GIF, and PDF files with [Dense](https://REPLACE-AT-LAUNCH.example)
straight from Finder or your clipboard, without leaving Raycast.

This extension does not talk to Dense over a network — it launches (or
activates) Dense with a `dense://compress` deep link, which Dense's own
`.onOpenURL` handler picks up. All actual compression work happens inside
the Dense app.

## Commands

- **Compress with Dense** — takes the file(s) currently selected in Finder,
  filters out anything Dense doesn't support, and opens a `dense://` link
  for the rest.
- **Compress Clipboard File** — reads the file currently on the clipboard
  (e.g. copied with ⌘C in Finder) and does the same for that one file.

Both commands take an optional **Preset** dropdown argument (defaults to
**Balanced** if left unset).

## The `dense://` contract

This extension is a pure client of the URL scheme Dense registers
(`app.dense.mac`, scheme `dense`). It does not depend on Dense's source —
only on this documented contract, mirrored in
[`DenseCore/Sources/DenseCore/DeepLink.swift`](../../DenseCore/Sources/DenseCore/DeepLink.swift):

```
dense://compress?path=<percent-encoded-absolute-path>&path=<...>&preset=<rawValue>
```

- `path` — one or more absolute filesystem paths, each percent-encoded as a
  full query value (e.g. spaces MUST be encoded as `%20`, **never** `+` —
  Dense's parser follows RFC 3986, where `+` in a query value is a literal
  plus sign, not a space). At least one `path` is required.
- `preset` — optional. One of the raw values below. If omitted, Dense uses
  its own persisted default preset instead. A deep link's preset is
  per-invocation only; it never changes Dense's saved default.

| Preset raw value | Display name           |
| ----------------- | ---------------------- |
| `discord`          | Discord (25 MB)        |
| `discordNitro`      | Discord Nitro (500 MB) |
| `email`            | Email (25 MB)          |
| `youtube`          | YouTube Upload         |
| `webSocial`         | Web / Social           |
| `high`             | High Quality           |
| `balanced`         | Balanced               |
| `small`            | Small File             |

Supported file extensions, mirrored from
[`DenseCore/Sources/DenseCore/FileKind.swift`](../../DenseCore/Sources/DenseCore/FileKind.swift)
(matching is case-insensitive):

- **Video:** mp4, mov, m4v, avi, mkv, webm, flv, wmv, mts, m2ts
- **Image:** jpg, jpeg, png, heic, tiff, tif, webp, bmp
- **GIF:** gif
- **PDF:** pdf

If either source file changes, update the copies in
[`src/dense-link.ts`](src/dense-link.ts) to match.

## Local development

```sh
cd integrations/raycast
npm install
npx ray develop
```

`ray develop` starts Raycast's dev server and hot-reloads the extension
into your local Raycast app so you can run the commands from the Raycast
launcher immediately. You'll need [Raycast](https://raycast.com) installed
and, for the deep link to actually do anything, a local build of Dense
registered for the `dense://` scheme.

Other useful scripts:

```sh
npm run typecheck   # tsc --noEmit
npm run lint         # ray lint
npm run build         # ray build -e dist (production bundle)
```

## Store submission (user-gated — do not run without sign-off)

These steps publish the extension to the public Raycast Store and require
an account with permission to publish under the Dense org, so they're
gated behind explicit user go-ahead:

1. Replace the placeholder `icon.png` in `assets/` with Dense's real
   512×512 app icon (and the `author` field in `package.json` with the
   real Raycast store username/org).
2. Replace every `REPLACE-AT-LAUNCH` placeholder in this extension
   (`DENSE_INSTALL_URL` in `src/dense-link.ts`, `author` in
   `package.json`) with the real, live Dense marketing site URL — the
   Site directory still has its own `REPLACE-AT-LAUNCH` placeholders that
   need filling in first (see `Site/index.html`, `Site/appcast.xml`).
3. Run `npx ray lint` and `npx ray build -e dist` and fix anything they
   flag.
4. Run `npx ray publish` from this directory, authenticated with an
   account authorized to publish to the Dense Raycast org/listing. This
   opens a PR against `raycast/extensions` for Raycast's review team.
5. Respond to any review feedback from the Raycast team on that PR.
6. Once merged, the extension goes live in the Raycast Store automatically
   — no separate release step.

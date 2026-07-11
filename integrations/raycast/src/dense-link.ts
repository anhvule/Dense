/**
 * Shared helpers for building `dense://compress` deep links.
 *
 * Mirrors the contract defined in
 * `DenseCore/Sources/DenseCore/DeepLink.swift` and the supported-extension
 * list in `DenseCore/Sources/DenseCore/FileKind.swift`. If either of those
 * files change, update this one to match.
 */

/** Where to send users who don't have Dense installed yet. */
export const DENSE_INSTALL_URL = "https://REPLACE-AT-LAUNCH.example";

export const PRESET_VALUES = [
  "discord",
  "discordNitro",
  "email",
  "youtube",
  "webSocial",
  "high",
  "balanced",
  "small",
] as const;

export type Preset = (typeof PRESET_VALUES)[number];

/** Matches the brief: the extension defaults to Balanced when no preset argument is given. */
export const DEFAULT_PRESET: Preset = "balanced";

// Mirrors DenseCore/Sources/DenseCore/FileKind.swift (videoExtensions / imageExtensions /
// gifExtensions / pdfExtensions) — keep this list in sync with that file.
const VIDEO_EXTENSIONS = [
  "mp4",
  "mov",
  "m4v",
  "avi",
  "mkv",
  "webm",
  "flv",
  "wmv",
  "mts",
  "m2ts",
];
const IMAGE_EXTENSIONS = [
  "jpg",
  "jpeg",
  "png",
  "heic",
  "tiff",
  "tif",
  "webp",
  "bmp",
];
const GIF_EXTENSIONS = ["gif"];
const PDF_EXTENSIONS = ["pdf"];

const SUPPORTED_EXTENSIONS = new Set<string>([
  ...VIDEO_EXTENSIONS,
  ...IMAGE_EXTENSIONS,
  ...GIF_EXTENSIONS,
  ...PDF_EXTENSIONS,
]);

/** Returns true if `path`'s extension is one Dense knows how to compress (case-insensitive). */
export function isSupportedFile(path: string): boolean {
  const match = /\.([^./]+)$/.exec(path);
  if (!match) return false;
  return SUPPORTED_EXTENSIONS.has(match[1].toLowerCase());
}

export function filterSupportedFiles(paths: string[]): string[] {
  return paths.filter(isSupportedFile);
}

/** Coerces an (optional) dropdown argument value into a known Preset, falling back to Balanced. */
export function normalizePreset(value: string | undefined): Preset {
  if (value && (PRESET_VALUES as readonly string[]).includes(value)) {
    return value as Preset;
  }
  return DEFAULT_PRESET;
}

/**
 * Builds a `dense://compress?path=...&path=...&preset=...` deep link.
 *
 * Spaces in paths MUST be percent-encoded as `%20`, never `+` — Dense's
 * parser follows RFC 3986, where `+` in a query value is a literal plus
 * sign (the plus-means-space convention only applies to
 * `application/x-www-form-urlencoded` form bodies, not generic URLs).
 * `encodeURIComponent` already does the right thing here: it always emits
 * `%20` for a space and never emits `+`.
 */
export function buildDenseUrl(paths: string[], preset?: Preset): string {
  const params = paths.map((path) => `path=${encodeURIComponent(path)}`);
  if (preset) {
    params.push(`preset=${encodeURIComponent(preset)}`);
  }
  return `dense://compress?${params.join("&")}`;
}

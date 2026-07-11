import {
  Clipboard,
  LaunchProps,
  Toast,
  open,
  showHUD,
  showToast,
} from "@raycast/api";
import {
  DENSE_INSTALL_URL,
  buildDenseUrl,
  filterSupportedFiles,
  normalizePreset,
} from "./dense-link";

interface Arguments {
  preset?: string;
}

/** Pulls an absolute filesystem path out of Clipboard.read()'s `file` field, which may be a bare
 * path or a `file://` URL depending on what copied it onto the clipboard. */
function extractClipboardPath(file: string | undefined): string | undefined {
  if (!file) return undefined;
  if (file.startsWith("file://")) {
    try {
      return decodeURIComponent(new URL(file).pathname);
    } catch {
      return undefined;
    }
  }
  return file;
}

/**
 * "Compress Clipboard File" — no-view command.
 *
 * Reads the file currently on the clipboard (e.g. copied with Cmd+C in
 * Finder) and hands it off to Dense via a `dense://` deep link.
 */
export default async function Command(
  props: LaunchProps<{ arguments: Arguments }>,
) {
  const preset = normalizePreset(props.arguments.preset);

  const clipboard = await Clipboard.read();
  const path = extractClipboardPath(clipboard.file);

  if (!path) {
    await showToast({
      style: Toast.Style.Failure,
      title: "No File on Clipboard",
      message: "Copy a file in Finder (⌘C), then run this command again.",
    });
    return;
  }

  const supportedPaths = filterSupportedFiles([path]);

  if (supportedPaths.length === 0) {
    await showToast({
      style: Toast.Style.Failure,
      title: "Unsupported File",
      message:
        "That file type isn't supported yet. Dense compresses video, image, GIF, and PDF files.",
    });
    return;
  }

  const url = buildDenseUrl(supportedPaths, preset);

  try {
    await open(url);
  } catch {
    await showToast({
      style: Toast.Style.Failure,
      title: "Dense Isn't Installed",
      message: `Install Dense from ${DENSE_INSTALL_URL}, then try again.`,
      primaryAction: {
        title: "Open Dense's Website",
        onAction: (toast) => {
          open(DENSE_INSTALL_URL);
          toast.hide();
        },
      },
    });
    return;
  }

  await showHUD("Sent 1 file to Dense");
}

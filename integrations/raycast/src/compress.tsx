import {
  LaunchProps,
  Toast,
  getSelectedFinderItems,
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

/**
 * "Compress with Dense" — no-view command.
 *
 * Takes the files currently selected in Finder, filters them down to the
 * types Dense supports, and hands them off to the app via a `dense://`
 * deep link (opening it launches Dense if it isn't already running, or
 * queues the files if it is).
 */
export default async function Command(
  props: LaunchProps<{ arguments: Arguments }>,
) {
  const preset = normalizePreset(props.arguments.preset);

  let selected: { path: string }[];
  try {
    selected = await getSelectedFinderItems();
  } catch {
    await showToast({
      style: Toast.Style.Failure,
      title: "No Finder Selection",
      message:
        "Select one or more files in Finder, then run this command again.",
    });
    return;
  }

  if (selected.length === 0) {
    await showToast({
      style: Toast.Style.Failure,
      title: "No Finder Selection",
      message:
        "Select one or more files in Finder, then run this command again.",
    });
    return;
  }

  const supportedPaths = filterSupportedFiles(
    selected.map((item) => item.path),
  );

  if (supportedPaths.length === 0) {
    await showToast({
      style: Toast.Style.Failure,
      title: "No Supported Files",
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

  const skipped = selected.length - supportedPaths.length;
  const noun = supportedPaths.length === 1 ? "file" : "files";
  await showHUD(
    skipped > 0
      ? `Sent ${supportedPaths.length} ${noun} to Dense (${skipped} skipped — unsupported type)`
      : `Sent ${supportedPaths.length} ${noun} to Dense`,
  );
}

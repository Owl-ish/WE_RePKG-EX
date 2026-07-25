# Changelog

## WeRePKG-EX - v1.5.0

Extraction is the focus of this release: it now handles every wallpaper type, runs
several at a time, and can be stopped part way. Filtering moved out of the settings
window into the toolbar, and the test suite went from Flutter's default stub to 128
tests.

### Features
- **Filters moved into the top bar.** Type and age rating sit behind a filter button
  next to the search box instead of inside the settings window, so you can see the
  grid change as you tick boxes.
- **Age rating replaces the mature switch.** Three checkboxes, All ages / Questionable
  / Mature, read from each wallpaper's own rating, and your existing mature setting
  carries over. A **Reset filters** action turns everything back on in one click.
- **A running extraction can be cancelled.** The cancel button stops workers picking
  up new wallpapers and kills the RePKG process mid-run. Work already in flight
  finishes, so nothing is left half written.
- **Extract multiple wallpapers at once.** Four at a time by default, adjustable from
  1 to 16 in settings. Lower it on a spinning disk, raise it on fast NVMe. Output paths
  are claimed up front, so two workers can never write to the same file.
- **Every wallpaper type extracts now.** Web, application and other non-scene types
  copy the whole wallpaper folder into a re-importable subfolder, in both wallpaper
  and project mode. The Extract button appears for all of them.
- **Already-unpacked scenes extract** rather than being skipped without a word.
- **Deleting asks first.** A confirmation dialog names the wallpaper, or counts them,
  before anything reaches the Recycle Bin.
- **Selection works like a file manager.** A plain left click selects one wallpaper and
  drops any previous range, clicking that same wallpaper again clears it, and
  right-click delete acts on the whole selection instead of the item under the cursor.
- **Search is no longer case sensitive.**

### Bug Fixes
- **Extraction no longer dies on non-ASCII RePKG output.** RePKG writes in the Windows
  console code page; reading it as UTF-8 threw and failed the whole extraction.
- **Extracted wallpapers keep their preview image.** RePKG does not emit one, so output
  folders had no thumbnail.
- **Grid previews are sharp again.** Landscape previews decoded too small and the cover
  fit stretched them about 1.8x.
- **The delete-transparency option sees every PNG.** Transparent grayscale images
  reported as opaque, and files ending in `.PNG` were skipped.
- **A bad ACF file no longer aborts the library scan.** A malformed or locked
  `appworkshop_431960.acf` is logged and ignored, since it only adds update dates.
- **Uppercase extensions work.** A `.MP4` target, or any uppercase extension in a
  `project.json` `file` entry, was silently ignored.
- **The taskbar icon shows up** instead of a blank square.
- **The loading panel stays its own size.** It no longer stretches down the window, and
  the cancel button no longer overflows it.
- **Delete reports what actually happened.** It removes only the folders that reached
  the Recycle Bin and says "Deleted" rather than "Copy successful".
- **Disk detection replaced `wmic`,** which Windows has deprecated, with a drive-letter
  probe.

### Performance
- **Selecting a range is roughly 5x faster.** Picking 500 wallpapers out of 2000 went
  from 55ms to 10ms, because selection is one state write rather than one per item.
- **The transparency check reads the PNG header** instead of decoding the image, and
  decoding moved off the main thread.
- **Image export no longer scans the file list per image,** which made large exports
  quadratic.
- **Video copying applies backpressure** and throttles progress updates instead of
  reporting every chunk.

### Under the hood
- 128 unit tests, up from Flutter's untouched `widget_test.dart` stub, covering the
  library scan, ACF parsing, filtering and sorting, file copying and the worker pool.
- CI checks formatting, analysis, the Dart and Rust test suites, and clippy on every
  pull request and on pushes to `master` and `publish`.
- The library scan no longer takes a `WidgetRef`, so it runs without a widget tree.
- RePKG is invoked directly rather than through `cmd.exe`, so paths containing spaces
  are safe.
- Debug and error output goes through the localization layer.
- Windows builds filter the engine's `ui::AXTree` log spam out of stderr, pending an
  upstream fix.

## WeRePKG-EX - v1.4.0

WeRePKG-EX is a fork of [WeRePKG](https://github.com/ilgnefz/we_repkg) by **ilgnefz**,
adding bug fixes, performance improvements, and quality-of-life features on top of 1.3.0.

### Bug Fixes
- **Fixed a crash when opening a "myprojects" (user-created) library folder.**
  Wallpapers whose `project.json` is missing a title or preview now load correctly,
  instead of failing the whole scan with "Failed to get wallpaper".
- **Fixed crashes when switching the library folder.** The wallpaper list now reloads
  reliably instead of erroring out, even on large libraries.
- **Fixed video export naming.** Exported videos are now named after the wallpaper's
  title instead of a cryptic source filename, and duplicate-name handling no longer
  breaks on filenames with multiple dots or no extension.

### Performance
- **Faster initial load** — wallpaper folders are now scanned in parallel.
- **Lower memory use and smoother scrolling** — grid thumbnails are decoded at display
  size instead of full resolution.
- **Smoother hovering** — hovering a wallpaper no longer redraws the entire grid.
- **Snappier search** — searching is debounced and filtering runs in a single pass.

### Features
- **The window size is now remembered** between launches. The app opens at a 16:9
  default (1280×720), centered.

### Other
- Renamed to **WeRePKG-EX**.
- Added the GPL-2.0 **LICENSE** file and credited the original author.
- The English README is now the default.

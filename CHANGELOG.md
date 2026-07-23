# Changelog

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

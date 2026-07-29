<p align="center"><img alt="WeRePKG-EX" src="docs/logo.png" width="480px"></p>

<div align="center">
  <h3>Extract your Wallpaper Engine wallpapers back into ordinary files</h3>
</div>

<p align="center">
  <a href="https://github.com/Owl-ish/WE_RePKG-EX/releases">Download</a>
  ·
  <a href="CHANGELOG.md">Changelog</a>
  ·
  <a href="README-CN.md">简体中文</a>
</p>

Wallpaper Engine keeps scene wallpapers packed inside `scene.pkg`, so the images
and videos you subscribed to are not files you can open. WeRePKG-EX unpacks them
for you: point it at your library, pick what you want, and get the artwork out
as PNG, JPG, GIF or MP4.

It is a Windows desktop app built on [RePKG-EX](https://github.com/Owl-ish/RePKG-EX),
and it bundles the extractor, so there is nothing else to install.

<img src="docs/main-window.png" alt="Main window" width="1000"/>


## Getting started

1. Download the latest release and unzip it anywhere.
2. Run `WeRePKG-EX.exe`.
3. The app finds your Wallpaper Engine library on its own. If it guesses wrong,
   set the path in Settings.

Nothing is written to your library. Extraction only ever reads from it.

## Searching a wallpaper

Search by name, filter by type and age rating, and sort by date, size or last
update. The count at the top left tells you how many match. Selecting works the
way it does in a file manager, including click and drag to box in several at
once.

<img src="docs/searching.gif" alt="Searching" width="1000"/>

## Wallpaper Cards

Double click, or right click and choose Details. You get the full preview, the
description, tags, file size, and where it lives on disk.

<img src="docs/wallpaper-card.gif" alt="WallpaperCard" width="1000"/>

## Extracting

The toggle in the bottom left picks what you get:

<img src="docs/extraction-mode.png" alt="ExtractionMode" width="1000"/>

**Wallpaper** gives you the artwork. Images land in one folder, ready to use as
ordinary wallpapers. Effect masks and shader files are skipped.

**Project** gives you the whole wallpaper as a folder Wallpaper Engine can
import again, keeping the scene intact so you can edit it in the editor.

Either mode works on one wallpaper or on everything selected. Right click for
both options, or use the buttons along the bottom for the whole visible list.

<img src="docs/extract.gif" alt="Extracting" width="1000"/>

Large batches run several wallpapers at once. A running extraction shows its
progress and can be cancelled part way without leaving half written files.

## Settings

<img src="docs/Settings.png" alt="SettingsPage" width="1000"/>

Worth knowing about:

- **Save only image files** throws away shaders, models and sounds, leaving just
  the artwork.
- **Delete transparent images** sends fully transparent PNGs to the recycle bin,
  since they are usually masks rather than art.
- **Simultaneous extractions** sets how many wallpapers unpack at once. Lower it
  on a hard drive, raise it on an SSD.
- **Move to the project folder** drops finished projects straight into Wallpaper
  Engine so they show up in the app.
- **Theme** and **Language** follow your system by default. English and 简体中文
  are both supported throughout.

Settings live in `%APPDATA%\WeRePKG-EX`, and the About panel shows the exact
path.

## Credits

A fork of [WeRePKG](https://github.com/ilgnefz/we_repkg) by **ilgnefz**, which
builds on [RePKG](https://github.com/notscuffed/repkg) by **notscuffed**. The
bundled extractor is [RePKG-EX](https://github.com/Owl-ish/RePKG-EX), a fork of
notscuffed's work.

## License

[GPL-2.0](LICENSE)

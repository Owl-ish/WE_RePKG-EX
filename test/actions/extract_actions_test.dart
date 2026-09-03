import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/actions/extract_actions.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/constants/wallpaper_files.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/setting.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/views/states/error.dart';
import 'package:we_repkg/views/states/extraction_progress.dart';

void main() {
  late Directory temp;
  late String exportPath;
  late String projectPath;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('extract_actions');
    exportPath = p.join(temp.path, 'export');
    projectPath = p.join(temp.path, 'projects');
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppKeys.exportPath: exportPath,
      AppKeys.projectPath: projectPath,
      AppKeys.toolPath: p.join(temp.path, 'missing-repkg.exe'),
      AppKeys.extractConcurrency: 1,
      AppKeys.extractMemoryLimit: 1024,
      AppKeys.notificationType: NotificationType.app.index,
    });
    await StorageUtil.initWithoutFile();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  WallpaperInfo wallpaper(String id, String target, {String? title}) {
    final folder = Directory(p.join(temp.path, 'source', id))
      ..createSync(recursive: true);
    return WallpaperInfo(
      id: id,
      title: title ?? id,
      contentRating: 'Everyone',
      tags: const [],
      previews: '',
      type: 'web',
      updateTime: null,
      createTime: DateTime(2026),
      target: p.join(folder.path, target),
      folder: folder.path,
      size: 0,
    );
  }

  Future<(ProviderContainer, WidgetRef)> host(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    late WidgetRef captured;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: BotToastInit(),
          navigatorObservers: [BotToastNavigatorObserver()],
          home: Consumer(
            builder: (context, ref, child) {
              captured = ref;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return (container, captured);
  }

  Future<void> dismissToasts(WidgetTester tester) async {
    BotToast.cleanAll();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> expectRetired(
    WidgetTester tester,
    ProviderContainer container, {
    required int completed,
  }) async {
    expect(container.read(activeCancelTokenProvider), isNull);
    expect(container.read(processingWallpaperProvider), isNull);
    expect(container.read(currentIndexProvider), completed);
    // The batch finishes during real I/O, before the first overlay frame.
    // BotToast queues insertion, mounting, and removal on successive frames.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byType(ExtractionProgressPanel), findsNothing);
    expect(tester.takeException(), isNull);
  }

  for (final mode in ExtractType.values) {
    testWidgets(
      'project action uses the $mode destination and unique folders',
      (tester) async {
        await tester.runAsync(
          () => StorageUtil.setInt(AppKeys.extractType, mode.index),
        );
        final (container, ref) = await host(tester);
        final first = wallpaper('one', 'index.html', title: 'Shared title');
        final second = wallpaper('two', 'index.html', title: 'Shared title');
        File(first.target).writeAsStringSync('first');
        File(second.target).writeAsStringSync('second');

        await tester.runAsync(() => extractProject(ref, [first, second]));

        final destination = mode == ExtractType.project
            ? projectPath
            : exportPath;
        expect(
          File(
            p.join(destination, 'Shared title', 'index.html'),
          ).readAsStringSync(),
          'first',
        );
        expect(
          File(
            p.join(destination, 'Shared title-1', 'index.html'),
          ).readAsStringSync(),
          'second',
        );
        expect(
          Directory(
            mode == ExtractType.project ? exportPath : projectPath,
          ).existsSync(),
          isFalse,
        );
        await expectRetired(tester, container, completed: 2);
        expect(find.byType(ErrorView), findsNothing);
        await dismissToasts(tester);
      },
    );
  }

  testWidgets('wallpaper action copies videos, custom images and web folders', (
    tester,
  ) async {
    final (container, ref) = await host(tester);
    final video = wallpaper('video', 'original.MP4', title: 'Video title');
    final images = wallpaper('images', WallpaperDirectories.custom);
    final web = wallpaper('web', 'index.html');
    File(video.target).writeAsStringSync('video bytes');
    Directory(images.target).createSync();
    File(p.join(images.target, 'image.png')).writeAsStringSync('image bytes');
    File(web.target).writeAsStringSync('web bytes');

    await tester.runAsync(() => extractWallpapers(ref, [video, images, web]));

    expect(
      File(p.join(exportPath, 'Video title.MP4')).readAsStringSync(),
      'video bytes',
    );
    expect(
      File(p.join(exportPath, 'image.png')).readAsStringSync(),
      'image bytes',
    );
    expect(
      File(p.join(exportPath, 'web', 'index.html')).readAsStringSync(),
      'web bytes',
    );
    await expectRetired(tester, container, completed: 3);
    expect(find.byType(ErrorView), findsNothing);
    await dismissToasts(tester);
  });

  testWidgets(
    'current wallpaper keeps wallpaper mode and reports copy progress',
    (tester) async {
      await tester.runAsync(
        () =>
            StorageUtil.setInt(AppKeys.extractType, ExtractType.project.index),
      );
      final (container, ref) = await host(tester);
      final video = wallpaper('video', 'original.mp4');
      File(video.target).writeAsStringSync('video bytes');
      final statuses = <String>[];
      final subscription = container.listen(
        loadingTextProvider,
        (_, next) => statuses.add(next),
      );
      addTearDown(subscription.close);

      await tester.runAsync(() => extractCurrent(ref, video));

      expect(
        File(p.join(exportPath, 'video.mp4')).readAsStringSync(),
        'video bytes',
      );
      expect(Directory(projectPath).existsSync(), isFalse);
      expect(statuses, contains(AppI10n.dialogExtractVideoInfo));
      await expectRetired(tester, container, completed: 1);
      await dismissToasts(tester);
    },
  );

  for (final useTitle in [false, true]) {
    testWidgets(
      'separate folders route all copy types with title naming $useTitle',
      (tester) async {
        await tester.runAsync(() async {
          await StorageUtil.setBool(AppKeys.separateWallpaperFolders, true);
          await StorageUtil.setBool(AppKeys.useTitleName, useTitle);
        });
        final (container, ref) = await host(tester);
        final video = wallpaper('video', 'original.mp4', title: 'Shared');
        final images = wallpaper(
          'images',
          WallpaperDirectories.custom,
          title: 'Shared',
        );
        final web = wallpaper('web', 'index.html', title: 'Shared');
        File(video.target).writeAsStringSync('video bytes');
        Directory(images.target).createSync();
        File(
          p.join(images.target, 'image.png'),
        ).writeAsStringSync('image bytes');
        File(web.target).writeAsStringSync('web bytes');

        await tester.runAsync(
          () => extractWallpapers(ref, [video, images, web]),
        );

        String folder(String id) =>
            p.join(exportPath, useTitle ? 'Shared ($id)' : id);
        // Video filenames keep their existing title-based naming in either mode.
        expect(
          File(p.join(folder('video'), 'Shared.mp4')).readAsStringSync(),
          'video bytes',
        );
        expect(
          File(p.join(folder('images'), 'image.png')).readAsStringSync(),
          'image bytes',
        );
        expect(
          File(p.join(folder('web'), 'index.html')).readAsStringSync(),
          'web bytes',
        );
        expect(Directory(exportPath).listSync().whereType<File>(), isEmpty);
        expect(
          Directory(folder('web')).listSync().whereType<Directory>(),
          isEmpty,
        );
        await expectRetired(tester, container, completed: 3);
        expect(find.byType(ErrorView), findsNothing);
        await dismissToasts(tester);
      },
    );
  }

  for (final overwrite in [false, true]) {
    testWidgets(
      'separate folders preserve repeat-export policy with overwrite $overwrite',
      (tester) async {
        await tester.runAsync(() async {
          await StorageUtil.setBool(AppKeys.separateWallpaperFolders, true);
          await StorageUtil.setBool(AppKeys.replaceFile, overwrite);
        });
        final (container, ref) = await host(tester);
        final first = wallpaper('one', 'clip.mp4', title: 'Same title');
        final second = wallpaper('two', 'clip.mp4', title: 'Same title');
        File(first.target).writeAsStringSync('first');
        File(second.target).writeAsStringSync('second');
        await tester.runAsync(() => extractWallpapers(ref, [second]));
        await dismissToasts(tester);
        await tester.runAsync(() => extractWallpapers(ref, [first]));
        await dismissToasts(tester);
        final original = File(
          p.join(exportPath, 'Same title (one)', 'Same title.mp4'),
        );
        final other = File(
          p.join(exportPath, 'Same title (two)', 'Same title.mp4'),
        );
        final userFile = File(p.join(original.parent.path, 'notes.txt'))
          ..writeAsStringSync('keep');
        File(first.target).writeAsStringSync('updated');

        await tester.runAsync(() => extractWallpapers(ref, [first]));

        expect(original.readAsStringSync(), overwrite ? 'updated' : 'first');
        final extra = File(p.join(original.parent.path, 'Same title-1.mp4'));
        expect(extra.existsSync(), !overwrite);
        if (!overwrite) expect(extra.readAsStringSync(), 'updated');
        expect(other.readAsStringSync(), 'second');
        expect(userFile.readAsStringSync(), 'keep');
        await expectRetired(tester, container, completed: 1);
        await dismissToasts(tester);
      },
    );
  }

  testWidgets('separate folder failure stays with that wallpaper', (
    tester,
  ) async {
    await tester.runAsync(
      () => StorageUtil.setBool(AppKeys.separateWallpaperFolders, true),
    );
    final (container, ref) = await host(tester);
    final blocked = wallpaper('blocked', 'clip.mp4');
    final good = wallpaper('good', 'clip.mp4');
    File(blocked.target).writeAsStringSync('blocked');
    File(good.target).writeAsStringSync('good');
    Directory(exportPath).createSync();
    final obstruction = File(p.join(exportPath, 'blocked (blocked)'))
      ..writeAsStringSync('keep');

    await tester.runAsync(() => extractWallpapers(ref, [blocked, good]));

    expect(obstruction.readAsStringSync(), 'keep');
    expect(
      File(p.join(exportPath, 'good (good)', 'good.mp4')).readAsStringSync(),
      'good',
    );
    await expectRetired(tester, container, completed: 2);
    final errors = tester.widget<ErrorView>(find.byType(ErrorView)).errors;
    expect(errors, hasLength(1));
    expect(errors.single.wallpaper, blocked);
    await dismissToasts(tester);
  });

  testWidgets('separate folders do not change project destinations', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await StorageUtil.setBool(AppKeys.separateWallpaperFolders, true);
      await StorageUtil.setInt(AppKeys.extractType, ExtractType.project.index);
    });
    final (container, ref) = await host(tester);
    final web = wallpaper('one', 'index.html', title: 'Project title');
    File(web.target).writeAsStringSync('web');

    await tester.runAsync(() => extractProject(ref, [web]));

    expect(
      File(
        p.join(projectPath, 'Project title', 'index.html'),
      ).readAsStringSync(),
      'web',
    );
    expect(Directory(exportPath).existsSync(), isFalse);
    await expectRetired(tester, container, completed: 1);
    await dismissToasts(tester);
  });

  test('separate folder preference defaults off and survives reload', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(separateWallpaperFoldersProvider), isFalse);
    for (final enabled in [true, false]) {
      container.read(separateWallpaperFoldersProvider.notifier).update(enabled);
      // Await storage's write queue without altering the preference under test.
      await StorageUtil.setBool(AppKeys.useTitleName, true);
      await StorageUtil.initWithoutFile();
      final reloaded = ProviderContainer();
      expect(reloaded.read(separateWallpaperFoldersProvider), enabled);
      reloaded.dispose();
    }
  });

  testWidgets('cancel leaves later separate folders uncreated', (tester) async {
    await tester.runAsync(
      () => StorageUtil.setBool(AppKeys.separateWallpaperFolders, true),
    );
    final (container, ref) = await host(tester);
    final first = wallpaper('first', 'clip.mp4');
    final second = wallpaper('second', 'clip.mp4');
    File(first.target).writeAsStringSync('first');
    File(second.target).writeAsStringSync('second');
    final subscription = container.listen(currentIndexProvider, (_, next) {
      if (next == 1) container.read(activeCancelTokenProvider)!.cancel();
    });
    addTearDown(subscription.close);

    await tester.runAsync(() => extractWallpapers(ref, [first, second]));

    expect(
      File(p.join(exportPath, 'first (first)', 'first.mp4')).readAsStringSync(),
      'first',
    );
    expect(
      Directory(p.join(exportPath, 'second (second)')).existsSync(),
      isFalse,
    );
    await expectRetired(tester, container, completed: 1);
    expect(find.text(AppI10n.dialogCancelled), findsOneWidget);
    await dismissToasts(tester);
  });

  testWidgets(
    'switching back to shared output does not sweep wallpaper folders',
    (tester) async {
      await tester.runAsync(
        () => StorageUtil.setBool(AppKeys.separateWallpaperFolders, true),
      );
      final (container, ref) = await host(tester);
      final grouped = wallpaper('one', 'clip.mp4', title: '.werepkg-ex-title');
      final shared = wallpaper('two', 'clip.mp4', title: 'Shared');
      File(grouped.target).writeAsStringSync('grouped');
      File(shared.target).writeAsStringSync('shared');
      await tester.runAsync(() => extractWallpapers(ref, [grouped]));
      await dismissToasts(tester);
      container.read(separateWallpaperFoldersProvider.notifier).update(false);

      await tester.runAsync(() => extractWallpapers(ref, [shared]));

      expect(
        File(
          p.join(
            exportPath,
            '_.werepkg-ex-title (one)',
            '.werepkg-ex-title.mp4',
          ),
        ).readAsStringSync(),
        'grouped',
      );
      expect(
        File(p.join(exportPath, 'Shared.mp4')).readAsStringSync(),
        'shared',
      );
      await expectRetired(tester, container, completed: 1);
      await dismissToasts(tester);
    },
  );

  testWidgets(
    'separate scene failure cleans scratch data but keeps existing output',
    (tester) async {
      await tester.runAsync(
        () => StorageUtil.setBool(AppKeys.separateWallpaperFolders, true),
      );
      final (container, ref) = await host(tester);
      final scene = wallpaper('scene', 'scene.pkg');
      File(scene.target).writeAsStringSync('package');
      File(
        container.read(toolPathProvider)!,
      ).writeAsStringSync('not an executable');
      final destination = Directory(p.join(exportPath, 'scene (scene)'))
        ..createSync(recursive: true);
      final existing = File(p.join(destination.path, 'keep.png'))
        ..writeAsStringSync('keep');
      Directory(p.join(destination.path, '.werepkg-ex-stale')).createSync();

      await tester.runAsync(() => extractWallpapers(ref, [scene]));

      expect(destination.listSync().map((entry) => p.basename(entry.path)), [
        'keep.png',
      ]);
      expect(existing.readAsStringSync(), 'keep');
      await expectRetired(tester, container, completed: 1);
      final errors = tester.widget<ErrorView>(find.byType(ErrorView)).errors;
      expect(errors, hasLength(1));
      expect(errors.single.message, contains(destination.path));
      await dismissToasts(tester);
    },
  );

  testWidgets('cancel stops the next wallpaper and retires progress state', (
    tester,
  ) async {
    final (container, ref) = await host(tester);
    final first = wallpaper('first', 'video.mp4');
    final second = wallpaper('second', 'video.mp4');
    File(first.target).writeAsStringSync('first bytes');
    File(second.target).writeAsStringSync('second bytes');
    // Cancel at a completed item, not after a timing-dependent delay.
    final subscription = container.listen(currentIndexProvider, (_, next) {
      if (next == 1) container.read(activeCancelTokenProvider)!.cancel();
    });
    addTearDown(subscription.close);

    await tester.runAsync(() => extractWallpapers(ref, [first, second]));

    expect(
      File(p.join(exportPath, 'first.mp4')).readAsStringSync(),
      'first bytes',
    );
    expect(File(p.join(exportPath, 'second.mp4')).existsSync(), isFalse);
    await expectRetired(tester, container, completed: 1);
    expect(find.text(AppI10n.dialogCancelled), findsOneWidget);
    expect(find.text(AppI10n.dialogOperationCompleted), findsNothing);
    await dismissToasts(tester);
  });

  testWidgets('failed copy is reported without losing the next wallpaper', (
    tester,
  ) async {
    final (container, ref) = await host(tester);
    final missing = wallpaper('missing', 'missing.mp4');
    final good = wallpaper('good', 'video.mp4');
    File(good.target).writeAsStringSync('good bytes');

    await tester.runAsync(() => extractWallpapers(ref, [missing, good]));

    expect(File(p.join(exportPath, 'missing.mp4')).existsSync(), isFalse);
    expect(
      File(p.join(exportPath, 'good.mp4')).readAsStringSync(),
      'good bytes',
    );
    await expectRetired(tester, container, completed: 2);
    final errors = tester.widget<ErrorView>(find.byType(ErrorView)).errors;
    expect(errors, hasLength(1));
    expect(errors.single.wallpaper, missing);
    expect(errors.single.message, contains(AppI10n.errorExportVideoFailed));
    await dismissToasts(tester);
  });

  for (final project in [false, true]) {
    testWidgets(
      '${project ? 'project' : 'wallpaper'} action requires RePKG only for packages',
      (tester) async {
        final (container, ref) = await host(tester);
        final scene = wallpaper('scene', 'scene.pkg');
        File(scene.target).writeAsStringSync('package');

        await tester.runAsync(
          () => project
              ? extractProject(ref, [scene])
              : extractWallpapers(ref, [scene]),
        );

        expect(Directory(exportPath).existsSync(), isFalse);
        await expectRetired(tester, container, completed: 0);
        expect(find.text(AppI10n.toolNoExist), findsOneWidget);
        await dismissToasts(tester);
      },
    );

    testWidgets(
      '${project ? 'project' : 'wallpaper'} worker startup failure reports source and destination',
      (tester) async {
        final (container, ref) = await host(tester);
        final scene = wallpaper('scene', 'scene.pkg');
        File(scene.target).writeAsStringSync('package');
        // An existing but invalid executable passes preflight and exercises the
        // real worker's process-start failure, without invoking an installed tool.
        File(
          container.read(toolPathProvider)!,
        ).writeAsStringSync('not an executable');

        await tester.runAsync(
          () => project
              ? extractProject(ref, [scene])
              : extractWallpapers(ref, [scene]),
        );

        await expectRetired(tester, container, completed: 1);
        final errors = tester.widget<ErrorView>(find.byType(ErrorView)).errors;
        expect(errors, hasLength(1));
        expect(errors.single.wallpaper, scene);
        expect(errors.single.message, contains(scene.target));
        expect(errors.single.message, contains(exportPath));
        expect(
          Directory(exportPath).listSync().whereType<Directory>().where(
            (dir) => p.basename(dir.path).startsWith('.werepkg-'),
          ),
          isEmpty,
        );
        await dismissToasts(tester);
      },
    );
  }
}

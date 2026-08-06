class AppKeys {
  static const String hideUnknown = 'hideUnknown';
  static const String hideScene = 'hideScene';
  static const String hideVideo = 'hideVideo';
  static const String hideWeb = 'hideWeb';
  static const String hideApp = 'hideApp';
  static const String hideEveryone = 'hideEveryone';
  static const String hideQuestionable = 'hideQuestionable';
  static const String hideMature = 'hideMature';

  /// Pre-1.6 three-way mature filter (0 show / 1 hide / 2 only). Read once to
  /// seed the three hide flags above, then never written again.
  static const String matureState = 'matureState';
  static const String onlySaveImage = 'onlySaveImage';
  static const String excludeTexture = 'excludeTexture';
  static const String useTitleName = 'useTitleName';
  static const String replaceFile = 'replaceFile';
  static const String sortAscending = 'sortAscending';
  static const String wallpaperPath = 'wallpaperPath';
  static const String toolPath = 'toolPath';
  static const String exportPath = 'exportPath';
  static const String sortType = 'sortType';
  static const String ctrlPressedIndex = 'ctrlPressedIndex';
  static const String theme = 'theme';
  static const String notificationType = 'notificationType';
  static const String deleteTransparency = 'deleteTransparency';
  static const String useProjectFolder = 'useProjectFolder';
  static const String projectPath = 'projectPath';
  static const String extractType = 'extractType';
  static const String useAcfInfo = 'useAcfInfo';
  static const String acfPath = 'acfPath';
  static const String updateProjectPath = 'updateProjectPath';
  static const String updateAcfPath = 'updateAcfPath';
  static const String maximizeOpen = 'maximizeOpen';
  static const String windowWidth = 'windowWidth';
  static const String windowHeight = 'windowHeight';
  static const String extractConcurrency = 'extractConcurrency';
  static const String extractMemoryLimit = 'extractMemoryLimit';

  /// Root of the backup tree, holding `431960` and
  /// `wallpaper_engine\projects\myprojects` beneath it.
  static const String backupRoot = 'backupRoot';

  /// Which library the grid is browsing, as a `WallpaperLibrary` index, so
  /// reordering that enum changes which library a returning user lands on.
  static const String currentLibrary = 'currentLibrary';

  /// The live myprojects library. Absent until the user overrides the folder
  /// derived from [wallpaperPath], which is what makes the refresh button a
  /// removal rather than a second write.
  static const String myProjectsLibrary = 'myProjectsLibrary';
}

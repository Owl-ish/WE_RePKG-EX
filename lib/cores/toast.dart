import 'package:bot_toast/bot_toast.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/models/error.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/setting.dart';
import 'package:we_repkg/views/states/error.dart';
import 'package:we_repkg/views/states/loading.dart';
import 'package:we_repkg/widgets/toast.dart';

void _toast(IconData icon, Color color, String text, {int seconds = 3}) {
  BotToast.showCustomText(
    duration: Duration(seconds: seconds),
    toastBuilder: (_) => ToastView(icon: icon, iconColor: color, text: text),
  );
}

void showSelectFolderToast(String message) =>
    _toast(Icons.lightbulb_circle_rounded, Colors.blue, message, seconds: 5);

void showCancelledToast() =>
    _toast(Icons.cancel, Colors.orange, tr(AppI10n.dialogCancelled));

void showDeleteToast() =>
    _toast(Icons.check_circle, Colors.green, tr(AppI10n.dialogDeleteSuccess));

void showCopyToast() =>
    _toast(Icons.check_circle, Colors.green, tr(AppI10n.dialogCopySuccess));

void showToolNoExistToast() => _toast(
  Icons.warning_rounded,
  Colors.red,
  tr(AppI10n.toolNoExist),
  seconds: 5,
);

void showErrorToast(String message) =>
    _toast(Icons.warning_rounded, Colors.red, message, seconds: 5);

void showExtractSuccessToast() {
  if (storedNotificationType() == NotificationType.app) {
    return _toast(
      Icons.check_circle,
      Colors.green,
      tr(AppI10n.dialogOperationCompleted),
    );
  }
  LocalNotification(title: tr(AppI10n.dialogOperationCompleted)).show();
}

CancelFunc showLoadingView(List<WallpaperInfo> list) {
  return BotToast.showCustomLoading(
    backgroundColor: Colors.black.withValues(alpha: .6),
    toastBuilder: (void Function() cancelFunc) => LoadingView(list),
  );
}

void showErrorView(List<ErrorInfo> errList) {
  BotToast.showCustomLoading(
    backgroundColor: Colors.black.withValues(alpha: .6),
    toastBuilder: (void Function() cancelFunc) =>
        ErrorView(errList, cancelFunc),
  );
}

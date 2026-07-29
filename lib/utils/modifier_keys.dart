import 'package:flutter/services.dart';

bool get isCtrlPressed {
  final Set<LogicalKeyboardKey> keys =
      HardwareKeyboard.instance.logicalKeysPressed;
  return keys.contains(LogicalKeyboardKey.controlLeft) ||
      keys.contains(LogicalKeyboardKey.controlRight);
}

bool get isShiftPressed {
  final Set<LogicalKeyboardKey> keys =
      HardwareKeyboard.instance.logicalKeysPressed;
  return keys.contains(LogicalKeyboardKey.shiftLeft) ||
      keys.contains(LogicalKeyboardKey.shiftRight);
}

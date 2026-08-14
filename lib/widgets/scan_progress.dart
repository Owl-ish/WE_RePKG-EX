import 'package:flutter/material.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/widgets/progress_bar.dart';

/// What a tab shows while it waits on disk, in the same shape the extraction
/// panel waits in.
class ScanProgress extends StatelessWidget {
  const ScanProgress({super.key, required this.label, this.progress});

  final String label;

  /// Null while there is no count to give, which sweeps rather than fills.
  final double? progress;

  static const double _barWidth = 320;
  static const double _spinner = 28;
  static const double _spinnerStroke = 3;
  static const Duration _progressStep = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: LayoutNums.largeGap,
        children: <Widget>[
          // The animation goes above the words rather than on the end of them:
          // trailing dots grow and shrink, which walks a centred line about.
          const SizedBox(
            width: _spinner,
            height: _spinner,
            child: CircularProgressIndicator(strokeWidth: _spinnerStroke),
          ),
          Text(label),
          SizedBox(
            width: _barWidth,
            // A scan reports every few folders, so the bar has to keep up
            // rather than ease.
            child: ProgressBar(value: progress, step: _progressStep),
          ),
        ],
      ),
    );
  }
}

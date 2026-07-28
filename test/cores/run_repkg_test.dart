@TestOn('windows')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/cores/extract.dart';
import 'package:we_repkg/utils/cancel_token.dart';

/// cmd.exe rather than a fake: the behaviour under test is the pipe draining.
void main() {
  test(
    'drains both streams at once past the pipe buffer',
    () async {
      // Past the ~4KB a pipe holds on both streams, so draining them one after
      // the other blocks forever.
      const int lines = 4000;
      final result = await runRePKG('cmd.exe', [
        '/c',
        'for /L %i in (1,1,$lines) do @(echo out %i padded out a bit'
            ' & echo err %i padded out a bit 1>&2)',
      ], CancelToken());

      expect(result.exitCode, 0);
      expect(
        RegExp('^out 1 ', multiLine: true).hasMatch(result.stdout),
        isTrue,
      );
      expect(
        RegExp('^out $lines ', multiLine: true).hasMatch(result.stdout),
        isTrue,
      );
      expect(
        RegExp('^err $lines ', multiLine: true).hasMatch(result.stderr),
        isTrue,
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('reports lines as they arrive', () async {
    final seen = <String>[];
    await runRePKG(
      'cmd.exe',
      ['/c', '@echo first& @echo second'],
      CancelToken(),
      onStdoutLine: seen.add,
    );

    expect(seen, ['first', 'second']);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test(
    'returns instead of hanging when the token kills the process',
    () async {
      final token = CancelToken();
      // Cancel once output is flowing, so the kill lands mid-stream rather than
      // before the process has started writing.
      final future = runRePKG(
        'cmd.exe',
        ['/c', 'for /L %i in (1,1,100000) do @echo %i'],
        token,
        onStdoutLine: (_) => token.cancel(),
      );

      await expectLater(future, completes);
      expect(token.isCancelled, isTrue);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

import 'dart:io';

import 'package:crypto/crypto.dart';

Future<String> sha1File(File file) async {
  final output = _DigestCollector();
  final input = sha1.startChunkedConversion(output);
  await for (final chunk in file.openRead()) {
    input.add(chunk);
  }
  input.close();
  final digest = output.value;
  if (digest == null) {
    throw StateError('无法计算文件 SHA1');
  }
  return digest.toString();
}

class _DigestCollector implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

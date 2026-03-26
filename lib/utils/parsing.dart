DateTime? parseDateTime(dynamic value) {
  if (value == null || value == '' || value == 0) return null;

  if (value is DateTime) return value.toUtc();

  if (value is int || value is double) {
    final epoch = value is int ? value : value.toInt();
    if (epoch > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true);
    }
    return DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
  }

  final text = value.toString().trim();
  if (text.isEmpty) return null;

  if (RegExp(r'^\d+$').hasMatch(text)) {
    final epoch = int.tryParse(text);
    if (epoch == null) return null;
    if (epoch > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true);
    }
    return DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
  }

  final patterns = <RegExp>[
    RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$'),
    RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$'),
    RegExp(r'^(\d{4})-(\d{2})-(\d{2})$'),
    RegExp(r'^(\d{4})\.(\d{2})\.(\d{2}) (\d{2}):(\d{2}):(\d{2})$'),
    RegExp(r'^(\d{4})\.(\d{2})\.(\d{2}) (\d{2}):(\d{2})$'),
    RegExp(r'^(\d{4})\.(\d{2})\.(\d{2})$'),
    RegExp(r'^(\d{4})\/(\d{2})\/(\d{2}) (\d{2}):(\d{2}):(\d{2})$'),
    RegExp(r'^(\d{4})\/(\d{2})\/(\d{2}) (\d{2}):(\d{2})$'),
    RegExp(r'^(\d{4})\/(\d{2})\/(\d{2})$'),
    RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$'),
    RegExp(r'^(\d{4})(\d{2})(\d{2})$'),
  ];

  for (final pattern in patterns) {
    final m = pattern.firstMatch(text);
    if (m == null) continue;
    final y = int.parse(m[1]!);
    final mo = int.parse(m[2]!);
    final d = int.parse(m[3]!);
    final h = m.groupCount >= 4 ? int.parse(m[4]!) : 0;
    final mi = m.groupCount >= 5 ? int.parse(m[5]!) : 0;
    final s = m.groupCount >= 6 ? int.parse(m[6]!) : 0;
    return DateTime.utc(y, mo, d, h, mi, s);
  }

  final iso = DateTime.tryParse(text.replaceAll('Z', '+00:00'));
  return iso?.toUtc();
}

String safeFilename(String input) {
  final cleaned = input.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]+'), '_').trim();
  final trimmed = cleaned.replaceAll(RegExp(r'^[ ._]+|[ ._]+$'), '');
  return trimmed.isEmpty ? 'activity' : trimmed;
}

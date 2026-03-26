import 'source_adapter.dart';

class SourceRegistry {
  SourceRegistry({required List<SourceAdapter> sources})
      : _sources = Map.fromEntries(sources.map((s) => MapEntry(s.name, s)));

  final Map<String, SourceAdapter> _sources;

  List<SourceAdapter> get all => _sources.values.toList(growable: false);

  SourceAdapter byName(String name) {
    final value = _sources[name];
    if (value == null) {
      throw StateError('Unknown source: $name');
    }
    return value;
  }
}


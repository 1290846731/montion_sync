class Activity {
  Activity({
    required this.source,
    required this.sourceId,
    required this.name,
    required this.sportType,
    required this.startTime,
    required this.raw,
  });

  final String source;
  final String sourceId;
  final String name;
  final String? sportType;
  final DateTime? startTime;
  final Map<String, dynamic> raw;

  Map<String, dynamic> toJson() => {
        'source': source,
        'sourceId': sourceId,
        'name': name,
        'sportType': sportType,
        'startTime': startTime?.millisecondsSinceEpoch,
        'raw': raw,
      };

  factory Activity.fromJson(Map<String, dynamic> json) => Activity(
        source: json['source'] as String,
        sourceId: json['sourceId'] as String,
        name: json['name'] as String,
        sportType: json['sportType'] as String?,
        startTime: json['startTime'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['startTime'] as int, isUtc: true)
            : null,
        raw: json['raw'] as Map<String, dynamic>? ?? {},
      );
}


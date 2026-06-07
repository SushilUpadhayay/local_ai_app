class ModelItem {
  final String id;
  final String name;
  final String fullName;
  final String size;
  final String ram;
  String status; // 'installed', 'available', 'downloading'
  bool active;
  final String category;
  double downloadProgress;
  String? localPath;
  String? url;

  // Additional Metadata
  final String quantization;
  final int contextWindow;
  final String modelFamily;

  /// Computed from contextWindow — no need to hardcode per model.
  ///
  /// Rule: 25% of context window for output tokens, clamped to [512, 2048].
  /// Audio/speech models (contextWindow == 0) return 0.
  ///
  /// Examples:
  ///   2048 ctx  → 512  max output tokens
  ///   4096 ctx  → 1024 max output tokens
  ///   8192 ctx  → 2048 max output tokens (capped)
  ///  32768 ctx  → 2048 max output tokens (capped)
  int get maxOutputTokens {
    if (contextWindow == 0) return 0; // audio/speech model
    return (contextWindow / 4).round().clamp(512, 2048);
  }

  ModelItem({
    required this.id,
    required this.name,
    required this.fullName,
    required this.size,
    required this.ram,
    required this.status,
    this.active = false,
    required this.category,
    this.downloadProgress = 0.0,
    this.localPath,
    this.url,
    required this.quantization,
    required this.contextWindow,
    required this.modelFamily,
  });

  ModelItem copyWith({
    String? id,
    String? name,
    String? fullName,
    String? size,
    String? ram,
    String? status,
    bool? active,
    String? category,
    double? downloadProgress,
    String? localPath,
    String? url,
    String? quantization,
    int? contextWindow,
    String? modelFamily,
  }) {
    return ModelItem(
      id: id ?? this.id,
      name: name ?? this.name,
      fullName: fullName ?? this.fullName,
      size: size ?? this.size,
      ram: ram ?? this.ram,
      status: status ?? this.status,
      active: active ?? this.active,
      category: category ?? this.category,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      localPath: localPath ?? this.localPath,
      url: url ?? this.url,
      quantization: quantization ?? this.quantization,
      contextWindow: contextWindow ?? this.contextWindow,
      modelFamily: modelFamily ?? this.modelFamily,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'fullName': fullName,
      'size': size,
      'ram': ram,
      'status': status,
      'active': active,
      'category': category,
      'downloadProgress': downloadProgress,
      'localPath': localPath,
      'url': url,
      'quantization': quantization,
      'contextWindow': contextWindow,
      // maxOutputTokens is computed — not stored
      'modelFamily': modelFamily,
    };
  }

  factory ModelItem.fromMap(Map<String, dynamic> map) {
    return ModelItem(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      fullName: map['fullName'] ?? '',
      size: map['size'] ?? '',
      ram: map['ram'] ?? '',
      status: map['status'] ?? 'available',
      active: map['active'] ?? false,
      category: map['category'] ?? '',
      downloadProgress: (map['downloadProgress'] as num?)?.toDouble() ?? 0.0,
      localPath: map['localPath'],
      url: map['url'],
      quantization: map['quantization'] ?? 'Q4_K_M',
      contextWindow: (map['contextWindow'] as num?)?.toInt() ?? 2048,
      // maxOutputTokens is computed from contextWindow — not read from map
      modelFamily: map['modelFamily'] ?? 'Unknown',
    );
  }
}

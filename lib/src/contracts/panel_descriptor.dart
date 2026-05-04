class PanelDescriptor {
  const PanelDescriptor({
    required this.id,
    required this.title,
    required this.width,
    required this.height,
    required this.rotation,
    required this.primary,
  });

  factory PanelDescriptor.fromMap(Map<dynamic, dynamic> map) {
    return PanelDescriptor(
      id: map['id'] as int,
      title: (map['title'] ?? '').toString(),
      width: (map['width'] as num).toInt(),
      height: (map['height'] as num).toInt(),
      rotation: (map['rotation'] as num?)?.toInt() ?? 0,
      primary: map['primary'] == true,
    );
  }

  final int id;
  final String title;
  final int width;
  final int height;
  final int rotation;
  final bool primary;

  int get area => width * height;
}

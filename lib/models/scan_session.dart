class ScanPage {
  ScanPage({required this.originalPath, required this.currentPath});

  final String originalPath;
  String currentPath;
}

class ScanSession {
  ScanSession({required this.dirPath});

  static const _months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];

  final String dirPath;
  final List<ScanPage> pages = [];
  String? customTitle;

  String get stamp => dirPath.split(RegExp(r'[/\\]')).last;

  DateTime? get createdAt {
    final millis = int.tryParse(stamp);
    if (millis == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  String get title {
    final custom = customTitle;
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    return defaultTitle;
  }

  String get defaultTitle {
    final date = createdAt;
    if (date == null) {
      return 'Escaneo $stamp';
    }
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return 'Escaneo ${date.day} ${_months[date.month - 1]} ${date.year}, $hour:$minute';
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ImportProgressDialog extends StatelessWidget {
  const ImportProgressDialog({
    super.key,
    required this.progress,
    required this.total,
  });

  final ValueListenable<int> progress;
  final int total;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (context, done, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Importando PDF… $done/$total'),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: total == 0 ? null : done / total,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

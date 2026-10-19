import 'dart:io';

import 'package:flutter/material.dart';

import '../models/scan_session.dart';
import '../services/session_store.dart';
import '../theme/app_theme.dart';

class MoveCopyTarget {
  const MoveCopyTarget.newDocument() : session = null;

  const MoveCopyTarget.existing(ScanSession this.session);

  final ScanSession? session;

  bool get isNew => session == null;
}

Future<MoveCopyTarget?> showMoveCopyTargetSheet(
  BuildContext context, {
  required ScanSession current,
  required String title,
}) {
  return showModalBottomSheet<MoveCopyTarget>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _MoveCopyTargetSheet(current: current, title: title),
  );
}

class _MoveCopyTargetSheet extends StatefulWidget {
  const _MoveCopyTargetSheet({required this.current, required this.title});

  final ScanSession current;
  final String title;

  @override
  State<_MoveCopyTargetSheet> createState() => _MoveCopyTargetSheetState();
}

class _MoveCopyTargetSheetState extends State<_MoveCopyTargetSheet> {
  late final Future<List<ScanSession>> _sessions = _load();

  Future<List<ScanSession>> _load() async {
    final currentPath = _normalize(widget.current.dirPath);
    final all = await SessionStore.loadAll();
    return [
      for (final session in all)
        if (_normalize(session.dirPath) != currentPath) session,
    ];
  }

  static String _normalize(String path) =>
      path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                widget.title,
                style: AppTheme.display(20, color: AppColors.ink),
              ),
            ),
            ListTile(
              minTileHeight: 64,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.chip,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.note_add_outlined, color: colors.primary),
              ),
              title: const Text(
                'Documento nuevo',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              onTap: () => Navigator.of(
                context,
              ).pop(const MoveCopyTarget.newDocument()),
            ),
            const Divider(height: 1),
            Flexible(
              child: FutureBuilder<List<ScanSession>>(
                future: _sessions,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  final sessions = snapshot.data ?? const <ScanSession>[];
                  if (sessions.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No hay otros documentos',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: sessions.length,
                    itemBuilder: (context, index) =>
                        _buildTile(context, sessions[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(BuildContext context, ScanSession session) {
    final colors = Theme.of(context).colorScheme;
    final count = session.pages.length;
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(session.pages.first.currentPath),
          width: 40,
          height: 52,
          cacheWidth: 120,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => SizedBox(
            width: 40,
            height: 52,
            child: Icon(
              Icons.broken_image_outlined,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
      title: Text(
        session.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(count == 1 ? '1 página' : '$count páginas'),
      onTap: () => Navigator.of(context).pop(MoveCopyTarget.existing(session)),
    );
  }
}

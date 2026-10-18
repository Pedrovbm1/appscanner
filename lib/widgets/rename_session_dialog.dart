import 'package:flutter/material.dart';

import '../models/scan_session.dart';
import '../services/session_store.dart';

Future<bool> showRenameSessionDialog(
  BuildContext context,
  ScanSession session,
) async {
  final value = await showDialog<String>(
    context: context,
    builder: (_) => _RenameSessionDialog(initial: session.title),
  );
  if (value == null) {
    return false;
  }
  final trimmed = value.trim();
  final next = trimmed.isEmpty || trimmed == session.defaultTitle
      ? null
      : trimmed;
  if (next == session.customTitle) {
    return false;
  }
  final previous = session.customTitle;
  session.customTitle = next;
  try {
    await SessionStore.save(session);
  } catch (_) {
    session.customTitle = previous;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo renombrar el escaneo.')),
      );
    }
    return false;
  }
  return true;
}

class _RenameSessionDialog extends StatefulWidget {
  const _RenameSessionDialog({required this.initial});

  final String initial;

  @override
  State<_RenameSessionDialog> createState() => _RenameSessionDialogState();
}

class _RenameSessionDialogState extends State<_RenameSessionDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  )..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Renombrar escaneo'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          hintText: 'Déjalo vacío para usar la fecha',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}

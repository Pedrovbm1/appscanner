import 'package:flutter/material.dart';

class AnnotateTextDialog extends StatefulWidget {
  const AnnotateTextDialog({super.key});

  @override
  State<AnnotateTextDialog> createState() => _AnnotateTextDialogState();
}

class _AnnotateTextDialogState extends State<AnnotateTextDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Texto'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Escribe el texto'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}

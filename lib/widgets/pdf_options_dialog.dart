import 'package:flutter/material.dart';

import '../models/pdf_options.dart';

Future<PdfOptions?> showPdfOptionsDialog(BuildContext context) {
  return showDialog<PdfOptions>(
    context: context,
    builder: (_) => const _PdfOptionsDialog(),
  );
}

class _PdfOptionsDialog extends StatefulWidget {
  const _PdfOptionsDialog();

  @override
  State<_PdfOptionsDialog> createState() => _PdfOptionsDialogState();
}

class _PdfOptionsDialogState extends State<_PdfOptionsDialog> {
  final _watermarkController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _includeOcr = true;
  bool _compress = true;
  bool _protect = false;
  bool _showPassword = false;
  PdfDestination _destination = PdfDestination.share;
  String? _passwordError;

  @override
  void dispose() {
    _watermarkController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _passwordController.text;
    if (_protect && password.isEmpty) {
      setState(() => _passwordError = 'Escribe una contraseña.');
      return;
    }
    Navigator.of(context).pop(
      PdfOptions(
        includeOcr: _includeOcr,
        compress: _compress,
        watermark: _watermarkController.text.trim(),
        protect: _protect,
        password: _protect ? password : '',
        destination: _destination,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Opciones del PDF'),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SegmentedButton<PdfDestination>(
                segments: const [
                  ButtonSegment(
                    value: PdfDestination.share,
                    icon: Icon(Icons.share),
                    label: Text('Compartir'),
                  ),
                  ButtonSegment(
                    value: PdfDestination.save,
                    icon: Icon(Icons.download),
                    label: Text('Guardar en el teléfono'),
                  ),
                ],
                showSelectedIcon: false,
                selected: {_destination},
                onSelectionChanged: (selection) =>
                    setState(() => _destination = selection.first),
              ),
            ),
            SwitchListTile(
              title: const Text('Incluir texto OCR (capa invisible)'),
              value: _includeOcr,
              onChanged: (value) => setState(() => _includeOcr = value),
            ),
            SwitchListTile(
              title: const Text('Comprimir'),
              subtitle: const Text('JPEG calidad 72, máx. 2000 px'),
              value: _compress,
              onChanged: (value) => setState(() => _compress = value),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _watermarkController,
                maxLength: 60,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Marca de agua (opcional)',
                ),
              ),
            ),
            SwitchListTile(
              title: const Text('Proteger con contraseña'),
              value: _protect,
              onChanged: (value) => setState(() {
                _protect = value;
                _passwordError = null;
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _passwordController,
                enabled: _protect,
                obscureText: !_showPassword,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onChanged: (_) {
                  if (_passwordError != null) {
                    setState(() => _passwordError = null);
                  }
                },
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  errorText: _passwordError,
                  suffixIcon: IconButton(
                    tooltip: _showPassword
                        ? 'Ocultar contraseña'
                        : 'Mostrar contraseña',
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: _protect
                        ? () => setState(() => _showPassword = !_showPassword)
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Crear PDF')),
      ],
    );
  }
}

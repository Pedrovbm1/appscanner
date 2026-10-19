import 'package:flutter/material.dart';

import '../models/pdf_options.dart';
import '../theme/app_theme.dart';

Future<PdfOptions?> showPdfOptionsSheet(BuildContext context) {
  return showModalBottomSheet<PdfOptions>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _PdfOptionsSheet(),
  );
}

class _PdfOptionsSheet extends StatefulWidget {
  const _PdfOptionsSheet();

  @override
  State<_PdfOptionsSheet> createState() => _PdfOptionsSheetState();
}

class _PdfOptionsSheetState extends State<_PdfOptionsSheet> {
  final _watermarkController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
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
    _passwordFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _passwordController.text;
    if (_protect && password.isEmpty) {
      setState(() => _passwordError = 'Escribe una contraseña.');
      _passwordFocus.requestFocus();
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

  void _setProtect(bool value) {
    setState(() {
      _protect = value;
      _passwordError = null;
    });
    if (value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _protect) {
          _passwordFocus.requestFocus();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Opciones del PDF',
                  style: AppTheme.display(24, color: AppColors.ink),
                ),
              ),
              const SizedBox(height: 18),
              _DestinationToggle(
                value: _destination,
                onChanged: (value) => setState(() => _destination = value),
              ),
              const SizedBox(height: 8),
              _SwitchRow(
                label: 'Texto buscable',
                hint: 'Podrás buscar y copiar el texto',
                value: _includeOcr,
                onChanged: (value) => setState(() => _includeOcr = value),
              ),
              _SwitchRow(
                label: 'Comprimir',
                hint: 'JPEG calidad 72, máx. 2000 px',
                value: _compress,
                onChanged: (value) => setState(() => _compress = value),
              ),
              _SwitchRow(
                label: 'Proteger con contraseña',
                hint: 'Cifrado AES de 256 bits',
                value: _protect,
                onChanged: _setProtect,
              ),
              if (_protect) ...[
                const SizedBox(height: 18),
                _FieldLabel(
                  text: 'Contraseña',
                  color: _passwordError == null
                      ? AppColors.tealDark
                      : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 6),
                Semantics(
                  label: 'Contraseña',
                  child: TextField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    obscureText: !_showPassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(fontSize: 16, color: AppColors.ink),
                    onChanged: (_) {
                      if (_passwordError != null) {
                        setState(() => _passwordError = null);
                      }
                    },
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      errorText: _passwordError,
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: IconButton(
                          tooltip: _showPassword
                              ? 'Ocultar contraseña'
                              : 'Mostrar contraseña',
                          color: AppColors.inkSoft,
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const _FieldLabel(
                text: 'Marca de agua (opcional)',
                color: AppColors.inkSoft,
              ),
              const SizedBox(height: 6),
              Semantics(
                label: 'Marca de agua (opcional)',
                child: TextField(
                  controller: _watermarkController,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 16, color: AppColors.ink),
                  decoration: const InputDecoration(
                    hintText: 'Ej. CONFIDENCIAL',
                    hintStyle: TextStyle(color: _hintColor),
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(64, 56),
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _submit,
                      icon: Icon(
                        _protect
                            ? Icons.lock_outline
                            : Icons.picture_as_pdf_outlined,
                        size: 20,
                      ),
                      label: Text(
                        _protect ? 'Crear PDF protegido' : 'Crear PDF',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DestinationToggle extends StatelessWidget {
  const _DestinationToggle({required this.value, required this.onChanged});

  final PdfDestination value;
  final ValueChanged<PdfDestination> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.tile,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          _segment(PdfDestination.share, Icons.share_outlined, 'Compartir'),
          _segment(PdfDestination.save, Icons.download_outlined, 'Guardar'),
        ],
      ),
    );
  }

  Widget _segment(PdfDestination option, IconData icon, String label) {
    final selected = option == value;
    final color = selected ? AppColors.ink : AppColors.inkSoft;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            boxShadow: selected ? _segmentShadow : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => onChanged(option),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _rowDivider)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Switch(
                value: value,
                onChanged: onChanged,
                activeTrackColor: AppColors.teal,
                activeThumbColor: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

const _rowDivider = Color(0xFFE3ECE9);
const _hintColor = Color(0xFF5A706C);
const _segmentShadow = [
  BoxShadow(color: Color(0x2E0E2522), blurRadius: 3, offset: Offset(0, 1)),
];

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'app_strings.dart';
import 'rename_filename.dart';

class RenameAudioDialog extends StatefulWidget {
  const RenameAudioDialog({super.key, required this.filename});
  final String filename;
  @override
  State<RenameAudioDialog> createState() => _RenameAudioDialogState();
}

class _RenameAudioDialogState extends State<RenameAudioDialog> {
  final _form = GlobalKey<FormState>();
  late final String _extension = p.extension(widget.filename);
  late final TextEditingController _controller = TextEditingController(
    text: widget.filename.substring(
      0,
      widget.filename.length - _extension.length,
    ),
  );
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.appStrings;
    return AlertDialog(
      title: Text(strings.renameFileTitle),
      content: Form(
        key: _form,
        child: TextFormField(
          key: const ValueKey('rename-file-input'),
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: strings.renameFileName,
            suffixText: _extension,
            helperText: strings.renameFileHelp,
          ),
          validator: (value) {
            try {
              renamedAudioFilename(widget.filename, value ?? '');
              return null;
            } catch (_) {
              return strings.renameFileInvalid;
            }
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.uiCancel228),
        ),
        FilledButton(
          key: const ValueKey('rename-file-confirm'),
          onPressed: () {
            if (_form.currentState!.validate()) {
              Navigator.pop(context, _controller.text.trim());
            }
          },
          child: Text(strings.uiRename),
        ),
      ],
    );
  }
}

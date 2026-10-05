import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/backup/backup_service.dart';
import '../../services/export/file_sharer.dart';
import '../providers.dart';

/// Settings rows: save a full backup / restore one.
class BackupTiles extends ConsumerWidget {
  const BackupTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(l.backupSection,
              style: Theme.of(context).textTheme.titleSmall),
        ),
        ListTile(
          leading: const Icon(Icons.save_alt),
          title: Text(l.backupExport),
          subtitle: Text(l.backupExportHint),
          onTap: () => _export(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.settings_backup_restore),
          title: Text(l.backupRestore),
          subtitle: Text(l.backupRestoreHint),
          onTap: () => _restore(context, ref),
        ),
      ],
    );
  }

  Future<T> _busy<T>(BuildContext context, Future<T> Function() work) async {
    final l = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(child: Text(l.backupWorking)),
        ]),
      ),
    );
    try {
      return await work();
    } finally {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final password = await showDialog<String>(
        context: context, builder: (_) => const _NewPasswordDialog());
    if (password == null || !context.mounted) return; // cancelled
    final service = ref.read(backupServiceProvider);
    final bytes = await _busy(context,
        () => service.export(password: password.isEmpty ? null : password));
    final d = DateTime.now();
    final day =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    await const FileSharer().share(bytes,
        fileName: 'pistak_hockey_backup_$day.pistak',
        mimeType: 'application/octet-stream');
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final picked = await FilePicker.pickFiles(type: FileType.any);
    if (picked.isEmpty || !context.mounted) return;
    final Uint8List bytes = await picked.first.readAsBytes();
    if (!context.mounted) return;
    final service = ref.read(backupServiceProvider);
    String? password;
    String? error;
    while (true) {
      if (!context.mounted) return;
      if (BackupService.isEncrypted(bytes)) {
        password = await showDialog<String>(
            context: context, builder: (_) => _AskPasswordDialog(error: error));
        if (password == null || !context.mounted) return;
      }
      try {
        final report = await _busy(
            context, () => service.restore(bytes, password: password));
        messenger.showSnackBar(
            SnackBar(content: Text(l.backupRestored(report.matches))));
        return;
      } on BackupWrongPassword {
        error = l.backupWrongPassword;
        if (!context.mounted) return;
      } on BackupInvalid {
        messenger.showSnackBar(SnackBar(content: Text(l.backupInvalidFile)));
        return;
      } on BackupPasswordRequired {
        error = null;
      }
    }
  }
}

/// Returns '' for "without password", the password, or null if cancelled.
class _NewPasswordDialog extends StatefulWidget {
  const _NewPasswordDialog();

  @override
  State<_NewPasswordDialog> createState() => _NewPasswordDialogState();
}

class _NewPasswordDialogState extends State<_NewPasswordDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final mismatch = _b.text.isNotEmpty && _a.text != _b.text;
    final ok = _a.text.isNotEmpty && _a.text == _b.text;
    return AlertDialog(
      title: Text(l.backupPasswordTitle),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(l.backupPasswordHint),
          const SizedBox(height: 12),
          TextField(
            controller: _a,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: l.password),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            controller: _b,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
                labelText: l.passwordRepeat,
                errorText: mismatch ? l.passwordsDontMatch : null),
            onChanged: (_) => setState(() {}),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: Text(l.backupWithoutPassword)),
        FilledButton(
            onPressed: ok ? () => Navigator.pop(context, _a.text) : null,
            child: Text(l.backupCreate)),
      ],
    );
  }
}

class _AskPasswordDialog extends StatefulWidget {
  const _AskPasswordDialog({this.error});
  final String? error;

  @override
  State<_AskPasswordDialog> createState() => _AskPasswordDialogState();
}

class _AskPasswordDialogState extends State<_AskPasswordDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.backupRestore),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(l.backupEnterPassword),
        TextField(
          controller: _c,
          obscureText: true,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration:
              InputDecoration(labelText: l.password, errorText: widget.error),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(
            onPressed: () => Navigator.pop(context, _c.text),
            child: Text(l.restore)),
      ],
    );
  }
}

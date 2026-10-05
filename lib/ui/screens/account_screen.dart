import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../auth/remote_auth_service.dart';
import '../../core/time_format.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';

String authErrorText(AppLocalizations l, Object e) => switch (e) {
      AuthError(code: 'invalid_credentials') => l.errInvalidCredentials,
      AuthError(code: 'email_taken') => l.errEmailTaken,
      AuthError(code: 'weak_password') => l.errWeakPassword,
      AuthError(code: 'invalid_email') => l.errInvalidEmail,
      AuthError(code: 'too_many_attempts') => l.errTooManyAttempts,
      _ => l.errNetwork,
    };

/// Sign in / create account / account status. Entirely optional.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit(RemoteAuthService account, AppLocalizations l) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await account.register(_email.text, _password.text);
      } else {
        await account.signIn(_email.text, _password.text);
      }
      _password.clear();
      await _syncNow(l);
    } catch (e) {
      setState(() => _error = authErrorText(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow(AppLocalizations l) async {
    final r = await ref.read(syncEngineProvider).syncOnce();
    if (!mounted) return;
    setState(() => _info = r.ok
        ? l.syncDone(r.matches + r.events, r.pulled)
        : l.errNetwork);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final account = ref.watch(accountProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.account)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: account == null
                ? [Text(l.backendNotConfigured)]
                : account.isSignedIn
                    ? _signedIn(l, account)
                    : _form(l, account),
          ),
        ),
      ),
    );
  }

  List<Widget> _signedIn(AppLocalizations l, RemoteAuthService account) {
    final last = ref.read(syncEngineProvider).lastSuccess;
    return [
      const Icon(Icons.cloud_done_outlined,
          size: 56, color: PistakColors.synced),
      const SizedBox(height: 12),
      Text(l.signedInAs(account.email ?? ''),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium),
      if (last != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(l.lastSync(formatClockTime(last.toUtc())),
              textAlign: TextAlign.center,
              style: const TextStyle(color: PistakColors.textMuted)),
        ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: _busy ? null : () => _syncNow(l),
        icon: const Icon(Icons.sync),
        label: Text(l.syncNow),
      ),
      if (_info != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_info!, textAlign: TextAlign.center),
        ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: () async {
          ref.read(syncEngineProvider).stop();
          await account.signOut();
        },
        icon: const Icon(Icons.logout),
        label: Text(l.signOut),
      ),
    ];
  }

  List<Widget> _form(AppLocalizations l, RemoteAuthService account) => [
        Text(l.accountBenefits,
            style: const TextStyle(color: PistakColors.textMuted)),
        const SizedBox(height: 20),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: InputDecoration(labelText: l.email),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: [
            _register ? AutofillHints.newPassword : AutofillHints.password
          ],
          decoration: InputDecoration(labelText: l.password, errorText: _error),
          onSubmitted: (_) => _submit(account, l),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : () => _submit(account, l),
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_register ? l.createAccount : l.signIn),
        ),
        TextButton(
          onPressed: () => setState(() {
            _register = !_register;
            _error = null;
          }),
          child: Text(_register ? l.haveAccount : l.noAccountYet),
        ),
      ];
}

import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import '../core/app_controller.dart';
import '../core/language_picker.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/repository.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.app});
  final AppController app;
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  bool _hide = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await performAction(context, widget.app, () async {
      if (_register) {
        await widget.app.repository.register(
          _name.text.trim(),
          _email.text.trim(),
          _password.text,
        );
      } else {
        await widget.app.repository.login(_email.text.trim(), _password.text);
      }
    });
  }

  void _demoAccounts() => showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SectionLabel(l10n(context).authDemoAccounts),
            const Gap(8),
            InfoNote(l10n(context).authDemoInfo),
            const Gap(16),
            for (final entry in [
              (l10n(context).authTryCustomer, 'customer@opc.demo'),
              (l10n(context).authTryMember, 'member@opc.demo'),
            ]) ...[
              PrimaryButton(
                label: entry.$1,
                secondary: true,
                onPressed: () {
                  setState(() {
                    _register = false;
                    _email.text = entry.$2;
                    _password.text = 'demo1234';
                  });
                  Navigator.pop(context);
                },
              ),
              const Gap(10),
            ],
          ],
        ),
      ),
    ),
  );

  void _forgot() => showDetailSheet(
    context,
    l10n(context).authResetTitle,
    widget.app.repository is RemoteOpcRepository
        ? l10n(context).apiPasswordHelp
        : l10n(context).authResetHelp,
  );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: LocalizedForm(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 4,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: c.dark ? c.primary : c.hero,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.code,
                            size: 21,
                            color: c.dark ? c.onPrimary : c.mint,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Text('OPC', style: t.titleLarge),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: l10n(context).authTheme,
                          icon: Icon(
                            c.dark
                                ? Icons.light_mode_outlined
                                : Icons.dark_mode_outlined,
                            size: 20,
                          ),
                          onPressed: () => widget.app.setTheme(
                            c.dark ? ThemeMode.light : ThemeMode.dark,
                          ),
                        ),
                        LanguagePicker(app: widget.app),
                      ],
                    ),
                  ],
                ),
                const Gap(24),
                Text(
                  l10n(context).authEyebrow,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: c.primary,
                  ),
                ),
                const Gap(10),
                Text(
                  _register
                      ? l10n(context).authRegisterHero
                      : l10n(context).authLoginHero,
                  style: t.headlineLarge,
                ),
                const Gap(10),
                Text(
                  l10n(context).authIntro,
                  style: t.bodyMedium?.copyWith(color: c.secondary),
                ),
                const Gap(20),
                OpcCard(
                  color: c.soft,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          Icons.shield_outlined,
                          color: c.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n(context).authNoExpertise,
                              style: t.titleSmall?.copyWith(color: c.primary),
                            ),
                            Text(
                              l10n(context).authReviewHelp,
                              style: t.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(20),
                if (_register) ...[
                  Text(l10n(context).authName, style: t.titleSmall),
                  const Gap(6),
                  TextFormField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: l10n(context).authNameHint,
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? l10n(context).authNameRequired
                        : null,
                  ),
                  const Gap(12),
                ],
                Text(l10n(context).authEmail, style: t.titleSmall),
                const Gap(6),
                TextFormField(
                  key: const Key('login-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    hintText: 'you@example.jp',
                    suffixIcon: Icon(Icons.email_outlined, size: 18),
                  ),
                  validator: (v) =>
                      RegExp(
                        r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                      ).hasMatch((v ?? '').trim())
                      ? null
                      : l10n(context).authEmailInvalid,
                ),
                const Gap(12),
                Text(l10n(context).authPassword, style: t.titleSmall),
                const Gap(6),
                TextFormField(
                  key: const Key('login-password'),
                  controller: _password,
                  obscureText: _hide,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  autofillHints: [
                    _register
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  decoration: InputDecoration(
                    hintText: _register
                        ? (widget.app.repository is RemoteOpcRepository
                              ? l10n(context).apiPasswordLength
                              : l10n(context).authPasswordNewHint)
                        : l10n(context).authPasswordHint,
                    suffixIcon: IconButton(
                      tooltip: _hide
                          ? l10n(context).authShowPassword
                          : l10n(context).authHidePassword,
                      icon: Icon(
                        _hide
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                      ),
                      onPressed: () => setState(() => _hide = !_hide),
                    ),
                  ),
                  validator: (v) =>
                      (v ?? '').length <
                          (_register
                              ? (widget.app.repository is RemoteOpcRepository
                                    ? 12
                                    : 8)
                              : 1)
                      ? (widget.app.repository is RemoteOpcRepository &&
                                _register
                            ? l10n(context).apiPasswordLength
                            : l10n(context).authPasswordRequired)
                      : null,
                ),
                if (!_register)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _forgot,
                      child: Text(
                        l10n(context).authForgot,
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                const Gap(8),
                PrimaryButton(
                  key: const Key('auth-submit'),
                  label: widget.app.busy
                      ? l10n(context).authBusy
                      : _register
                      ? l10n(context).authRegisterSubmit
                      : l10n(context).authLogin,
                  icon: Icons.arrow_forward,
                  onPressed: widget.app.busy ? null : _submit,
                ),
                const Gap(16),
                Text(
                  _register
                      ? l10n(context).authExisting
                      : l10n(context).authNew,
                  style: t.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const Gap(8),
                PrimaryButton(
                  label: _register
                      ? l10n(context).authBackLogin
                      : l10n(context).authRegister,
                  secondary: true,
                  onPressed: widget.app.busy
                      ? null
                      : () {
                          setState(() => _register = !_register);
                          _form.currentState?.reset();
                        },
                ),
                const Gap(20),
                Text(
                  l10n(context).authInternalLogin,
                  style: t.labelSmall,
                  textAlign: TextAlign.center,
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => showDetailSheet(
                        context,
                        l10n(context).authLegalTitle,
                        l10n(context).authLegalHelp,
                      ),
                      child: Text(
                        l10n(context).authLegalTitle,
                        style: TextStyle(fontSize: 10),
                      ),
                    ),
                    if (widget.app.repository is! RemoteOpcRepository)
                      TextButton(
                        onPressed: _demoAccounts,
                        child: Text(
                          l10n(context).authDemoAccounts,
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

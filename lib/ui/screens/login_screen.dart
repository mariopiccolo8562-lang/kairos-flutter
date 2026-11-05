import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/brand.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/sources/xtream_source.dart';
import '../widgets/brand_mark.dart';
import '../widgets/tv_button.dart';
import '../widgets/tv_focusable.dart';

enum _LoginMode { choose, xtream, m3u }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  _LoginMode _mode = _LoginMode.choose;
  bool _busy = false;
  String? _error;

  final TextEditingController _server = TextEditingController();
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  final TextEditingController _m3u = TextEditingController();

  final FocusNode _firstChoice = FocusNode();
  final FocusNode _serverNode = FocusNode();
  final FocusNode _userNode = FocusNode();
  final FocusNode _passNode = FocusNode();
  final FocusNode _m3uNode = FocusNode();
  final FocusNode _submitNode = FocusNode();

  @override
  void dispose() {
    for (final c in [_server, _user, _pass, _m3u]) {
      c.dispose();
    }
    for (final n in [_firstChoice, _serverNode, _userNode, _passNode, _m3uNode, _submitNode]) {
      n.dispose();
    }
    super.dispose();
  }

  void _setMode(_LoginMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
    });
    final target = switch (mode) {
      _LoginMode.choose => _firstChoice,
      _LoginMode.xtream => _serverNode,
      _LoginMode.m3u => _m3uNode,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) target.requestFocus();
    });
  }

  Future<void> _login(Account account) async {
    final app = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await app.login(account);
    if (!mounted) return; // accesso riuscito: la schermata è già stata sostituita
    setState(() {
      _busy = false;
      _error = error;
    });
    final retry = _mode == _LoginMode.choose ? _firstChoice : _submitNode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) retry.requestFocus();
    });
  }

  void _submitXtream() {
    final server = XtreamSource.normalizeServer(_server.text);
    final user = _user.text.trim();
    final pass = _pass.text.trim();
    if (server.isEmpty || user.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Compila server, nome utente e password');
      return;
    }
    _login(Account(type: AccountType.xtream, server: server, username: user, password: pass));
  }

  void _submitM3u() {
    final url = _m3u.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Inserisci il link della lista');
      return;
    }
    // Se è il link di un server Xtream usiamo le sue API: dati molto più completi.
    final xtream = XtreamSource.accountFromM3uUrl(url);
    _login(xtream ?? Account(type: AccountType.m3u, m3uUrl: url.contains('://') ? url : 'http://$url'));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _mode == _LoginMode.choose && !_busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_busy) _setMode(_LoginMode.choose);
      },
      child: Scaffold(
        body: Row(
          children: [
            const Expanded(flex: 4, child: _BrandPanel()),
            Expanded(
              flex: 6,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 56, 24),
                child: ExcludeFocus(
                  excluding: _busy,
                  child: switch (_mode) {
                    _LoginMode.choose => _chooser(),
                    _LoginMode.xtream => _xtreamForm(),
                    _LoginMode.m3u => _m3uForm(),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chooser() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Come vuoi accedere?', style: AppText.title),
        const SizedBox(height: 18),
        _ChoiceTile(
          focusNode: _firstChoice,
          autofocus: true,
          icon: Icons.dns_rounded,
          title: 'Xtream Codes',
          subtitle: 'Server, nome utente e password',
          onSelect: () => _setMode(_LoginMode.xtream),
        ),
        const SizedBox(height: 10),
        _ChoiceTile(
          icon: Icons.link_rounded,
          title: 'Link M3U',
          subtitle: 'Incolla l\'indirizzo della tua lista',
          onSelect: () => _setMode(_LoginMode.m3u),
        ),
        const SizedBox(height: 10),
        _ChoiceTile(
          icon: Icons.play_circle_outline_rounded,
          title: 'Prova la demo',
          subtitle: 'Contenuti di prova, senza account',
          onSelect: () => _login(const Account.demo()),
        ),
        ..._feedback(),
      ],
    );
  }

  Widget _xtreamForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Accedi con Xtream Codes', style: AppText.title),
        const SizedBox(height: 18),
        _field(
          controller: _server,
          node: _serverNode,
          label: 'Server',
          hint: 'http://indirizzo:porta',
          keyboard: TextInputType.url,
          next: _userNode,
        ),
        const SizedBox(height: 12),
        _field(controller: _user, node: _userNode, label: 'Nome utente', next: _passNode),
        const SizedBox(height: 12),
        _field(controller: _pass, node: _passNode, label: 'Password', obscure: true, onDone: _submitXtream),
        const SizedBox(height: 18),
        Row(
          children: [
            TvButton(focusNode: _submitNode, icon: Icons.login_rounded, label: 'Accedi', onPressed: _submitXtream),
            const SizedBox(width: 12),
            TvButton(label: 'Indietro', onPressed: () => _setMode(_LoginMode.choose)),
          ],
        ),
        ..._feedback(),
      ],
    );
  }

  Widget _m3uForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Usa un link M3U', style: AppText.title),
        const SizedBox(height: 8),
        const Text(
          'Se incolli il link di un server Xtream (get.php?username=…) l\'app usa '
          'automaticamente le sue API, con locandine e trame.',
          style: AppText.small,
        ),
        const SizedBox(height: 18),
        _field(
          controller: _m3u,
          node: _m3uNode,
          label: 'Link della lista',
          hint: 'http://…/lista.m3u',
          keyboard: TextInputType.url,
          onDone: _submitM3u,
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            TvButton(focusNode: _submitNode, icon: Icons.login_rounded, label: 'Carica la lista', onPressed: _submitM3u),
            const SizedBox(width: 12),
            TvButton(label: 'Indietro', onPressed: () => _setMode(_LoginMode.choose)),
          ],
        ),
        ..._feedback(),
      ],
    );
  }

  List<Widget> _feedback() {
    final error = _error;
    return [
      if (_busy) ...[
        const SizedBox(height: 18),
        const Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
            SizedBox(width: 12),
            Text('Accesso e download del catalogo…', style: AppText.meta),
          ],
        ),
      ],
      if (error != null) ...[
        const SizedBox(height: 18),
        Text(error, style: const TextStyle(fontSize: 13, color: Color(0xFFFF6B6B), fontWeight: FontWeight.w600)),
      ],
    ];
  }

  Widget _field({
    required TextEditingController controller,
    required FocusNode node,
    required String label,
    String? hint,
    TextInputType? keyboard,
    bool obscure = false,
    FocusNode? next,
    VoidCallback? onDone,
  }) {
    return TextField(
      controller: controller,
      focusNode: node,
      keyboardType: keyboard,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: next != null ? TextInputAction.next : TextInputAction.done,
      onSubmitted: (_) {
        if (next != null) {
          next.requestFocus();
        } else {
          onDone?.call();
        }
      },
      style: const TextStyle(fontSize: 16),
      decoration: tvInputDecoration(label: label, hint: hint),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B2A3A), Brand.background],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const BrandMark(fontSize: 40),
            const SizedBox(height: 14),
            const Text(
              'Film, serie e TV in diretta.\nFluida su ogni televisore.',
              style: TextStyle(fontSize: 16, height: 1.4, color: Color(0xCCFFFFFF)),
            ),
            const SizedBox(height: 24),
            Text(Brand.version, style: AppText.small),
          ],
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onSelect,
    this.focusNode,
    this.autofocus = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onSelect;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      autoScroll: false,
      onSelect: onSelect,
      builder: (context, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: focused ? Colors.white : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 28, color: focused ? Colors.black : Brand.accent),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: focused ? Colors.black : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: focused ? Colors.black54 : Colors.white60),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

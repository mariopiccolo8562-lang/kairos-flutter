import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../app/app_scope.dart';
import '../../app/brand.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../navigation.dart';
import '../widgets/tv_focusable.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.entryNode});

  final FocusNode entryNode;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _refreshing = false;
  String? _refreshMessage;
  String? _cacheMessage;

  Future<void> _refresh() async {
    if (_refreshing) return;
    final app = AppScope.of(context);
    setState(() {
      _refreshing = true;
      _refreshMessage = null;
    });
    final error = await app.refreshCatalog();
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      _refreshMessage = error ?? 'Catalogo aggiornato';
    });
  }

  Future<void> _clearImages() async {
    await DefaultCacheManager().emptyCache();
    PaintingBinding.instance.imageCache.clear();
    if (mounted) setState(() => _cacheMessage = 'Cache svuotata');
  }

  Future<void> _logout() async {
    final app = AppScope.of(context);
    final confirmed = await showTvConfirm(
      context,
      title: 'Uscire dall\'account?',
      message: 'Su questo dispositivo verranno cancellati catalogo, preferiti e progressi.',
      confirmLabel: 'Esci',
    );
    if (confirmed) await app.logout();
  }

  String _accountType(AccountType type) => switch (type) {
        AccountType.xtream => 'Xtream Codes',
        AccountType.m3u => 'Lista M3U',
        AccountType.demo => 'Demo',
      };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final account = app.account;
    final isXtream = account?.type == AccountType.xtream;
    final fetchedAt = app.catalog.value?.fetchedAt ?? 0;
    final updated = fetchedAt <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(fetchedAt);

    return ListView(
      padding: const EdgeInsets.fromLTRB(Layout.pagePadding, Layout.safeTop, Layout.pagePadding, 40),
      children: [
        const Text('Impostazioni', style: AppText.title),
        const SizedBox(height: 18),
        const _SectionTitle('Account'),
        if (account != null) _InfoLine(label: 'Tipo', value: _accountType(account.type)),
        if (account != null && account.server != null) _InfoLine(label: 'Server', value: account.server!),
        if (account != null && account.username != null) _InfoLine(label: 'Utente', value: account.username!),
        if (account != null && account.m3uUrl != null) _InfoLine(label: 'Lista', value: account.m3uUrl!),
        ValueListenableBuilder<AccountInfo?>(
          valueListenable: app.accountInfo,
          builder: (context, info, child) {
            if (info == null) return const SizedBox.shrink();
            final status = info.status;
            final expires = info.expiresAt;
            final max = info.maxConnections;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (status != null) _InfoLine(label: 'Stato', value: status),
                _InfoLine(label: 'Scadenza', value: expires == null ? 'Nessuna' : formatDate(expires)),
                if (max != null) _InfoLine(label: 'Connessioni', value: '${info.activeConnections ?? 0} di $max'),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        const _SectionTitle('Riproduzione'),
        if (isXtream)
          ValueListenableBuilder<String>(
            valueListenable: app.liveFormat,
            builder: (context, format, child) => _SettingTile(
              focusNode: widget.entryNode,
              title: 'Formato dei canali in diretta',
              value: format == 'm3u8' ? 'HLS (m3u8)' : 'MPEG-TS (consigliato)',
              onSelect: () => app.setLiveFormat(format == 'm3u8' ? 'ts' : 'm3u8'),
            ),
          ),
        _SettingTile(
          focusNode: isXtream ? null : widget.entryNode,
          title: 'Aggiorna il catalogo',
          value: _refreshing
              ? 'Aggiornamento in corso…'
              : (_refreshMessage ??
                  (updated == null
                      ? 'Scarica di nuovo canali, film e serie'
                      : 'Ultimo aggiornamento: ${formatDate(updated)} alle ${formatClock(updated)}')),
          onSelect: _refresh,
        ),
        _SettingTile(
          title: 'Svuota la cache delle immagini',
          value: _cacheMessage ?? 'Libera spazio sul dispositivo',
          onSelect: _clearImages,
        ),
        const SizedBox(height: 20),
        const _SectionTitle('Uscita'),
        _SettingTile(
          title: 'Esci dall\'account',
          value: 'Torna alla schermata di accesso',
          onSelect: _logout,
        ),
        const SizedBox(height: 24),
        Text('${Brand.appName} · ${Brand.version}', style: AppText.small),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: AppText.meta)),
          Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body)),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.title, required this.value, required this.onSelect, this.focusNode});

  final String title;
  final String value;
  final VoidCallback onSelect;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        builder: (context, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: focused ? Colors.white : const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: focused ? Colors.black : Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13, color: focused ? Colors.black54 : Colors.white60),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

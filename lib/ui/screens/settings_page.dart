import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../app/app_scope.dart';
import '../../app/brand.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../panel/panel.dart';
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

  Future<void> _choosePlaylist() async {
    final app = AppScope.of(context);
    final all = app.playlists;
    final current = app.playlist?.id;
    final index = await showTvChoice(
      context,
      title: 'Playlist',
      options: [for (final p in all) p.name],
      selected: all.indexWhere((p) => p.id == current),
    );
    if (index == null || index < 0 || index >= all.length || all[index].id == current) return;
    await app.choosePlaylist(all[index].id);
  }

  Future<void> _linkTv() async {
    final app = AppScope.of(context);
    try {
      final pin = await app.createLinkCode();
      if (!mounted) return;
      final pretty = pin.length == 6 ? '${pin.substring(0, 3)} ${pin.substring(3)}' : pin;
      await showTvCode(
        context,
        title: 'Collega un\'altra TV',
        code: pretty,
        message: 'Sulla nuova TV apri l\'app, scegli «Collega con codice a 6 cifre» e scrivi questo codice.\n'
            'Vale 10 minuti e si usa una volta sola.',
      );
    } on PanelException catch (e) {
      if (mounted) await showTvMessage(context, title: 'Collega un\'altra TV', message: e.message);
    }
  }

  Future<void> _showMessages(List<PanelMessage> messages) async {
    final app = AppScope.of(context);
    await showTvMessage(
      context,
      title: 'Messaggi',
      message: messages.map((m) => m.title.isEmpty ? m.body : '${m.title}\n${m.body}').join('\n\n'),
    );
    await app.markMessagesSeen(messages);
  }

  Future<void> _showPrivacy() async {
    final app = AppScope.of(context);
    final text = await app.privacyText();
    if (!mounted) return;
    await showTvMessage(context, title: 'Privacy e condizioni', message: text, button: 'Ho capito');
    await app.acceptPrivacy();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ValueListenableBuilder<PanelState?>(
      valueListenable: app.panelState,
      builder: (context, state, child) {
        final account = app.account;
        final isXtream = account?.type == AccountType.xtream;
        final fetchedAt = app.catalog.value?.fetchedAt ?? 0;
        final updated = fetchedAt <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(fetchedAt);
        final messages = state?.messages ?? const <PanelMessage>[];
        final acc = state?.account;
        var entryUsed = false;
        FocusNode? entry() {
          if (entryUsed) return null;
          entryUsed = true;
          return widget.entryNode;
        }

        // il punto d'ingresso dalla barra laterale è la prima voce selezionabile
        final playlistNode = app.canSwitchPlaylist ? entry() : null;
        final linkNode = app.canLinkTv ? entry() : null;
        final messagesNode = messages.isNotEmpty ? entry() : null;
        final formatNode = isXtream ? entry() : null;
        final refreshNode = entry();

        final expires = state == null
            ? ''
            : (state.expires.isEmpty ? 'Abbonamento attivo' : 'Attivo fino al ${state.expiresLabel}');

        return ListView(
          padding: const EdgeInsets.fromLTRB(Layout.pagePadding, Layout.safeTop, Layout.pageRight, 40),
          children: [
            const Text('Impostazioni', style: AppText.title),
            const SizedBox(height: 18),
            const _SectionTitle('Abbonamento'),
            if (expires.isNotEmpty) _InfoLine(label: 'Stato', value: expires),
            if (state != null && state.name.isNotEmpty) _InfoLine(label: 'Cliente', value: state.name),
            _InfoLine(label: 'Codice TV', value: app.deviceCode),
            if (app.playlist != null) _InfoLine(label: 'Playlist', value: app.playlist!.name),
            const SizedBox(height: 12),
            if (app.canSwitchPlaylist)
              _SettingTile(
                focusNode: playlistNode,
                title: 'Cambia playlist',
                value: app.playlist?.name ?? '',
                onSelect: _choosePlaylist,
              ),
            if (app.canLinkTv)
              _SettingTile(
                focusNode: linkNode,
                title: 'Collega un\'altra TV',
                value: acc == null ? 'Codice a 6 cifre' : 'Connessioni: ${acc.conns} di ${acc.maxConn}',
                onSelect: _linkTv,
              ),
            if (messages.isNotEmpty)
              _SettingTile(
                focusNode: messagesNode,
                title: 'Messaggi del fornitore',
                value: messages.length == 1 ? '1 messaggio' : '${messages.length} messaggi',
                onSelect: () => _showMessages(messages),
              ),
            const SizedBox(height: 12),
            const _SectionTitle('Riproduzione'),
            if (isXtream)
              ValueListenableBuilder<String>(
                valueListenable: app.liveFormat,
                builder: (context, format, child) => _SettingTile(
                  focusNode: formatNode,
                  title: 'Formato dei canali in diretta',
                  value: format == 'm3u8' ? 'HLS (m3u8)' : 'MPEG-TS (consigliato)',
                  onSelect: () => app.setLiveFormat(format == 'm3u8' ? 'ts' : 'm3u8'),
                ),
              ),
            _SettingTile(
              focusNode: refreshNode,
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
            const SizedBox(height: 12),
            const _SectionTitle('Informazioni'),
            _SettingTile(
              title: 'Privacy e condizioni',
              value: 'Condizioni del servizio',
              onSelect: _showPrivacy,
            ),
            const SizedBox(height: 18),
            Text(
              '${Brand.appName} ${app.appVersion} · ${app.lite ? 'modalità leggera' : 'grafica completa'} · ${app.device.model}',
              style: AppText.small,
            ),
          ],
        );
      },
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
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Brand.accent),
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
          SizedBox(width: 130, child: Text(label, style: AppText.meta)),
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
          duration: const Duration(milliseconds: 110),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.2,
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
                  style: TextStyle(fontSize: 13, height: 1.2, color: focused ? Colors.black54 : Colors.white60),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

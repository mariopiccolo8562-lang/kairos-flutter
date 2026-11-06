import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/brand.dart';
import '../../app/perf.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import '../navigation.dart';
import '../screens/browse_page.dart';
import '../screens/home_page.dart';
import '../screens/live_page.dart';
import '../screens/search_page.dart';
import '../screens/settings_page.dart';
import '../widgets/brand_mark.dart';
import '../widgets/tv_focusable.dart';
import '../widgets/tv_text_field.dart';

enum ShellTab { home, live, movies, series, search, settings }

extension on ShellTab {
  IconData get icon => switch (this) {
        ShellTab.home => Icons.home_rounded,
        ShellTab.live => Icons.live_tv_rounded,
        ShellTab.movies => Icons.movie_rounded,
        ShellTab.series => Icons.video_library_rounded,
        ShellTab.search => Icons.search_rounded,
        ShellTab.settings => Icons.settings_rounded,
      };

  String get label => switch (this) {
        ShellTab.home => 'Home',
        ShellTab.live => 'TV in diretta',
        ShellTab.movies => 'Film',
        ShellTab.series => 'Serie TV',
        ShellTab.search => 'Cerca',
        ShellTab.settings => 'Impostazioni',
      };
}

/// Struttura principale: barra laterale (si allarga quando ci entri, come su
/// Netflix) e pagina della sezione scelta.
///
/// Uscendo dalla barra con ▶ si torna esattamente dove si era nella pagina.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  ShellTab _tab = ShellTab.home;
  bool _railHasFocus = false;
  FocusNode? _lastContent;
  late final AppController _app;
  bool _messagesOpen = false;

  final FocusNode _railArea = FocusNode(debugLabel: 'barra', canRequestFocus: false, skipTraversal: true);
  final FocusNode _contentArea = FocusNode(debugLabel: 'contenuto', canRequestFocus: false, skipTraversal: true);
  // le voci della barra non partecipano allo spostamento con le frecce: la barra
  // le gestisce da sola (▲▼ tra le voci, ▶ nella pagina), così il focus non salta
  // dalla barra alla pagina e viceversa
  final Map<ShellTab, FocusNode> _tabNodes = {
    for (final t in ShellTab.values) t: FocusNode(debugLabel: 'voce-${t.name}', skipTraversal: true),
  };
  final Map<ShellTab, FocusNode> _entryNodes = {
    for (final t in ShellTab.values) t: FocusNode(debugLabel: 'ingresso-${t.name}'),
  };

  @override
  void initState() {
    super.initState();
    _app = AppScope.of(context);
    FocusManager.instance.addListener(_onFocusChanged);
    _app.notice.addListener(_onNotice);
    _app.panelState.addListener(_onPanelState);
    _focusContent();
    // avvisi del fornitore non ancora letti
    Timer(const Duration(milliseconds: 900), () {
      if (mounted) _showUnseenMessages();
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    _app.notice.removeListener(_onNotice);
    _app.panelState.removeListener(_onPanelState);
    _railArea.dispose();
    _contentArea.dispose();
    for (final node in _tabNodes.values) {
      node.dispose();
    }
    for (final node in _entryNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Ricorda l'ultimo elemento selezionato nella pagina.
  void _onFocusChanged() {
    final focused = FocusManager.instance.primaryFocus;
    if (focused != null && focused != _contentArea && _contentArea.hasFocus) _lastContent = focused;
  }

  void _onNotice() {
    final message = _app.notice.value;
    if (message == null || !mounted) return;
    _app.notice.value = null;
    showTvMessage(context, title: 'Visione interrotta', message: message);
  }

  void _onPanelState() => _showUnseenMessages();

  Future<void> _showUnseenMessages() async {
    if (_messagesOpen || !mounted) return;
    final unseen = _app.unseenMessages();
    if (unseen.isEmpty) return;
    _messagesOpen = true;
    await _app.markMessagesSeen(unseen);
    if (mounted) {
      await showTvMessage(
        context,
        title: unseen.length == 1 && unseen.first.title.isNotEmpty ? unseen.first.title : 'Messaggio del fornitore',
        message: unseen
            .map((m) => unseen.length == 1 || m.title.isEmpty ? m.body : '${m.title}\n${m.body}')
            .join('\n\n'),
      );
    }
    _messagesOpen = false;
  }

  void _select(ShellTab tab) {
    if (tab != _tab) {
      setState(() {
        _tab = tab;
        _lastContent = null;
      });
    }
    _focusContent();
  }

  /// Dopo aver cambiato sezione il focus entra nel contenuto.
  void _focusContent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _enterContent(preferLast: false);
    });
  }

  /// Entra nella pagina: sull'ultimo elemento selezionato, altrimenti sul primo.
  bool _enterContent({required bool preferLast}) {
    final last = _lastContent;
    if (preferLast && last != null && last.context != null && last.canRequestFocus) {
      last.requestFocus();
      return true;
    }
    final entry = _entryNodes[_tab]!;
    if (entry.context != null) {
      entry.requestFocus();
      return true;
    }
    if (last != null && last.context != null && last.canRequestFocus) {
      last.requestFocus();
      return true;
    }
    return false;
  }

  void _onRailFocusChange(bool hasFocus) {
    if (hasFocus == _railHasFocus) return;
    setState(() => _railHasFocus = hasFocus);
    // Entrando nella barra il focus va sempre sulla sezione attuale.
    if (hasFocus) {
      final current = _tabNodes[_tab]!;
      if (!current.hasFocus) current.requestFocus();
    }
  }

  KeyEventResult _onRailKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      _enterContent(preferLast: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      // ▲▼ solo tra le voci della barra (prima ▲ su «Impostazioni» finiva a destra nella pagina)
      final tabs = ShellTab.values;
      var index = tabs.indexWhere((t) => _tabNodes[t]!.hasPrimaryFocus);
      if (index < 0) index = _tab.index;
      final next = index + (key == LogicalKeyboardKey.arrowUp ? -1 : 1);
      if (next >= 0 && next < tabs.length) _tabNodes[tabs[next]]!.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  /// ◀ nella pagina: si va all'elemento a sinistra; se non c'è, nella barra laterale.
  /// ▲▼ restano nella pagina (le voci della barra non sono raggiungibili con le frecce).
  KeyEventResult _onContentKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.arrowLeft) return KeyEventResult.ignored;
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null || TvTextField.isEditing(focused)) return KeyEventResult.ignored; // cursore nel testo
    if (!focused.focusInDirection(TraversalDirection.left)) _tabNodes[_tab]!.requestFocus();
    return KeyEventResult.handled;
  }

  Future<void> _handleBack() async {
    // mentre si scrive, Indietro chiude solo la scrittura
    if (TvTextField.handleBack()) return;
    if (_railArea.hasFocus) {
      final exit = await showTvConfirm(
        context,
        title: 'Vuoi uscire?',
        message: 'L\'app verrà chiusa.',
        confirmLabel: 'Esci',
      );
      if (exit) await SystemNavigator.pop();
    } else {
      _tabNodes[_tab]!.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              left: Layout.railWidth,
              child: Focus(
                focusNode: _contentArea,
                onKeyEvent: _onContentKey,
                child: KeyedSubtree(key: ValueKey<ShellTab>(_tab), child: _page(_tab)),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Focus(
                focusNode: _railArea,
                onFocusChange: _onRailFocusChange,
                onKeyEvent: _onRailKey,
                child: _NavRail(
                  current: _tab,
                  expanded: _railHasFocus,
                  nodes: _tabNodes,
                  onSelect: _select,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _page(ShellTab tab) {
    final entry = _entryNodes[tab]!;
    return switch (tab) {
      ShellTab.home => HomePage(entryNode: entry),
      ShellTab.live => LivePage(entryNode: entry),
      ShellTab.movies => BrowsePage(kind: MediaKind.movie, entryNode: entry),
      ShellTab.series => BrowsePage(kind: MediaKind.series, entryNode: entry),
      ShellTab.search => SearchPage(entryNode: entry),
      ShellTab.settings => SettingsPage(entryNode: entry),
    };
  }
}

class _NavRail extends StatelessWidget {
  const _NavRail({
    required this.current,
    required this.expanded,
    required this.nodes,
    required this.onSelect,
  });

  final ShellTab current;
  final bool expanded;
  final Map<ShellTab, FocusNode> nodes;
  final ValueChanged<ShellTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Perf.lite ? Duration.zero : const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      width: expanded ? Layout.railExpandedWidth : Layout.railWidth,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: expanded
              ? const [Color(0xFA07050C), Color(0xF007050C), Color(0x0007050C)]
              : const [Color(0xCC07050C), Color(0x8807050C), Color(0x0007050C)],
          stops: const [0.0, 0.72, 1.0],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Le etichette compaiono solo quando c'è spazio (anche durante l'animazione).
          final showLabels = constraints.maxWidth > 150;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 22),
              SizedBox(
                height: 40,
                child: Padding(
                  padding: const EdgeInsets.only(left: 18),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: BrandMark(size: 36, showName: showLabels),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              for (final tab in ShellTab.values)
                _RailItem(
                  tab: tab,
                  node: nodes[tab]!,
                  selected: tab == current,
                  showLabel: showLabels,
                  onSelect: () => onSelect(tab),
                ),
              const Spacer(flex: 2),
            ],
          );
        },
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.tab,
    required this.node,
    required this.selected,
    required this.showLabel,
    required this.onSelect,
  });

  final ShellTab tab;
  final FocusNode node;
  final bool selected;
  final bool showLabel;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: node,
      autoScroll: false,
      onSelect: onSelect,
      builder: (context, focused) {
        final iconColor = focused ? Colors.black : (selected ? Brand.accent : const Color(0x99FFFFFF));
        final textColor = focused ? Colors.black : (selected ? Colors.white : const Color(0x99FFFFFF));
        return Container(
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: focused ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(tab.icon, size: 20, color: iconColor),
              if (showLabel) ...[
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    tab.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: selected || focused ? FontWeight.w700 : FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

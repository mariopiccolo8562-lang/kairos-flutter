import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/brand.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../navigation.dart';
import '../screens/browse_page.dart';
import '../screens/home_page.dart';
import '../screens/live_page.dart';
import '../screens/search_page.dart';
import '../screens/settings_page.dart';
import '../widgets/tv_focusable.dart';

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
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  ShellTab _tab = ShellTab.home;
  bool _railHasFocus = false;

  final FocusNode _railArea = FocusNode(debugLabel: 'barra', canRequestFocus: false, skipTraversal: true);
  final Map<ShellTab, FocusNode> _tabNodes = {
    for (final t in ShellTab.values) t: FocusNode(debugLabel: 'voce-${t.name}'),
  };
  final Map<ShellTab, FocusNode> _entryNodes = {
    for (final t in ShellTab.values) t: FocusNode(debugLabel: 'ingresso-${t.name}'),
  };

  @override
  void initState() {
    super.initState();
    _focusContent();
  }

  @override
  void dispose() {
    _railArea.dispose();
    for (final node in _tabNodes.values) {
      node.dispose();
    }
    for (final node in _entryNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _select(ShellTab tab) {
    if (tab != _tab) setState(() => _tab = tab);
    _focusContent();
  }

  /// Dopo aver cambiato sezione il focus entra nel contenuto.
  void _focusContent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final entry = _entryNodes[_tab]!;
      if (entry.context != null) entry.requestFocus();
    });
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

  Future<void> _handleBack() async {
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
              child: KeyedSubtree(key: ValueKey<ShellTab>(_tab), child: _page(_tab)),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Focus(
                focusNode: _railArea,
                onFocusChange: _onRailFocusChange,
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
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: expanded ? Layout.railExpandedWidth : Layout.railWidth,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: expanded
              ? const [Color(0xF5000000), Color(0xE6000000), Color(0x00000000)]
              : const [Color(0xB3000000), Color(0x66000000), Color(0x00000000)],
          stops: const [0.0, 0.7, 1.0],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Le etichette compaiono solo quando c'è spazio (anche durante l'animazione).
          final showLabels = constraints.maxWidth > 120;
          return Column(
            children: [
              const SizedBox(height: 26),
              SizedBox(
                height: 30,
                child: Center(
                  child: Text(
                    showLabels ? Brand.appName.toUpperCase() : Brand.appName.substring(0, 1),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(
                      color: Brand.accent,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
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
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12),
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

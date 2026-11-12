import 'package:flutter_test/flutter_test.dart';
import 'package:kairos_plus/panel/panel.dart';
import 'package:kairos_plus/panel/portals.dart';

void main() {
  test('FNV-1a offsets match the Kotlin UTF-16 vectors', () {
    for (final (code, expected) in <(String, List<int>)>[
      ('ABC123', [1, 0, 1]),
      ('K7Q2ZP', [0, 2, 2]),
      ('', [1, 0, 1]),
      ('000000', [1, 2, 1]),
    ]) {
      expect([2, 3, 4].map((n) => PortalRotation.offset(code, n)), expected);
    }
  });

  test('selection modes respect candidates, saved choices, and health', () {
    const candidates = [
      'http://main.test',
      'https://alt1.test',
      'http://alt2.test',
    ];
    const now = 1000;
    expect(
      PortalRotation.select(
        mode: 'main',
        candidates: candidates,
        code: 'ABC123',
        nowMs: now,
      ),
      candidates.first,
    );
    expect(
      PortalRotation.select(
        mode: 'alt',
        candidates: candidates,
        code: 'ABC123',
        nowMs: now,
      ),
      candidates[1],
    );
    expect(
      PortalRotation.select(
        mode: 'alt',
        candidates: [candidates.first],
        code: '',
        nowMs: now,
      ),
      candidates.first,
    );
    expect(
      PortalRotation.select(
        mode: 'auto',
        candidates: candidates,
        code: 'ABC123',
        nowMs: now,
      ),
      candidates.first,
    );
    expect(
      PortalRotation.select(
        mode: 'auto',
        candidates: candidates,
        code: 'ABC123',
        savedChoice: candidates[2],
        nowMs: now,
      ),
      candidates[2],
    );
    expect(
      PortalRotation.select(
        mode: 'auto',
        candidates: candidates,
        code: 'ABC123',
        savedChoice: candidates[2],
        badUntil: {PortalRotation.hostKey(candidates[2]): 2000},
        nowMs: now,
      ),
      candidates.first,
    );
    expect(
      PortalRotation.select(
        mode: 'rot',
        candidates: candidates,
        code: 'ABC123',
        nowMs: now,
      ),
      candidates.first,
    );
    expect(
      PortalRotation.select(
        mode: 'rot',
        candidates: candidates,
        code: 'ABC123',
        savedChoice: candidates[1],
        nowMs: now,
      ),
      candidates[1],
    );
  });

  test(
    'next advances in mode order, skips unhealthy choices, and is mode-gated',
    () {
      const candidates = [
        'http://main.test',
        'https://alt1.test',
        'http://alt2.test',
      ];
      const now = 1000;
      expect(
        PortalRotation.next(
          mode: 'auto',
          candidates: candidates,
          code: '',
          current: candidates.first,
          nowMs: now,
        ),
        candidates[1],
      );
      expect(
        PortalRotation.next(
          mode: 'auto',
          candidates: candidates,
          code: '',
          current: candidates.first,
          badUntil: {PortalRotation.hostKey(candidates[1]): 2000},
          nowMs: now,
        ),
        candidates[2],
      );
      final rotated = PortalRotation.order(candidates, 'ABC123');
      expect(
        PortalRotation.next(
          mode: 'rot',
          candidates: candidates,
          code: 'ABC123',
          current: rotated.first,
          nowMs: now,
        ),
        rotated[1],
      );
      expect(
        PortalRotation.next(
          mode: 'main',
          candidates: candidates,
          code: '',
          current: candidates.first,
        ),
        isNull,
      );
      expect(
        PortalRotation.next(
          mode: 'rot',
          candidates: [candidates.first],
          code: '',
          current: candidates.first,
        ),
        isNull,
      );
    },
  );

  test('normalizes and deduplicates reserve hosts and rewrites M3U get.php origins', () {
    expect(
      PortalRotation.candidates(
        host: 'main.test/',
        url: '',
        alts: ['https://ALT.test/path/', 'https://alt.test', 'alt2.test'],
      ),
      ['http://main.test', 'https://alt.test', 'http://alt2.test'],
    );
    final playlist = PanelPlaylist.fromJson({
      'id': 'provider',
      'name': 'Provider',
      'type': 'm3u',
      'url': 'http://main.test/get.php?username=u&password=p&type=m3u_plus',
      'host': 'http://main.test',
      'alts': ['https://alt.test'],
      'altNames': ['Reserve'],
      'mainName': 'Main',
      'mode': 'rot',
    });
    expect(playlist.alts, ['https://alt.test']);
    expect(playlist.altNames, ['Reserve']);
    expect(playlist.mainName, 'Main');
    expect(playlist.mode, 'rot');
    expect(
      playlist.toAccount(portalHost: 'https://alt.test')?.server,
      'https://alt.test',
    );
    expect(
      PanelPlaylist.fromJson({
        'id': 'x',
        'name': 'x',
        'type': 'xtream',
        'mode': 'unknown',
      }).mode,
      'auto',
    );
  });
}

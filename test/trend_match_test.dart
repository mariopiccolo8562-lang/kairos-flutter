import 'package:flutter_test/flutter_test.dart';
import 'package:kairos_plus/data/models.dart';
import 'package:kairos_plus/data/trend_match.dart';

MediaItem _movie(String id, String name, {String? year}) =>
    MediaItem(kind: MediaKind.movie, id: id, name: name, categoryId: '1', year: year);

void main() {
  test('legge la classifica del pannello', () {
    final t = TrendList.parse(<String, dynamic>{
      'movies': [
        {'t': 'Interstellar', 'y': 2014},
        {'t': '  ', 'y': 2020},
        {'t': 'Dune'},
      ],
      'series': [
        {'t': 'Dark', 'y': 0},
      ],
    })!;
    expect(t.movies.map((x) => x.title), ['Interstellar', 'Dune']);
    expect(t.movies.first.year, 2014);
    expect(t.movies.last.year, isNull);
    expect(t.series.single.year, isNull);
    expect(TrendList.parse(<String, dynamic>{'x': 1}), isNull);
    expect(TrendList.parse('nulla'), isNull);
  });

  test('titoli ridotti all\'essenziale', () {
    expect(normTitle('IT | Il Padrino (1972)'), 'il padrino');
    expect(normTitle('4K | Amélie'), 'amelie');
    expect(normTitle('Dune: Parte Due FHD'), 'dune parte due');
  });

  test('anno uguale o vicino', () {
    expect(titleMatches('Dune', 2021, 'Dune', 2022), isTrue);
    expect(titleMatches('Dune', 1984, 'Dune', 2021), isFalse);
    expect(titleMatches('Dune', null, 'Dune', 2021), isTrue);
  });

  test('nell\'ordine della classifica, solo quelli che la linea ha', () {
    final items = [
      _movie('1', 'IT | Dune', year: '2021'),
      _movie('2', 'Interstellar (2014)', year: '2014'),
      _movie('3', 'Dune', year: '1984'),
      _movie('4', 'Oppenheimer', year: '2023'),
    ];
    final out = matchTrend(const [
      TrendTitle('Interstellar', 2014),
      TrendTitle('Dune', 2021),
      TrendTitle('Barbie', 2023),
    ], items);
    expect(out.map((x) => x.id), ['2', '1']);
    expect(matchTrend(const [TrendTitle('Dune', 2021)], items, limit: 0), isEmpty);
  });
}

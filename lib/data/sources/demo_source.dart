import '../models.dart';
import 'content_source.dart';

const String _base = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample';

/// Contenuti di prova pubblici: servono a vedere l'app funzionare senza account.
class DemoSource extends ContentSource {
  const DemoSource();

  @override
  Future<Catalog> fetchCatalog() async => buildDemoCatalog();

  @override
  Future<MovieDetails?> movieDetails(MediaItem movie) async => MovieDetails(
        plot: movie.plot,
        backdrop: movie.backdrop ?? movie.image,
        genre: movie.genre,
        year: movie.year,
      );

  @override
  Future<SeriesDetails?> seriesDetails(MediaItem series) async {
    switch (series.id) {
      case 'demo-open-movies':
        return SeriesDetails(
          seasons: const [1],
          episodes: {
            1: [
              _episode('ElephantsDream', 1, 1, 'Elephants Dream'),
              _episode('BigBuckBunny', 1, 2, 'Big Buck Bunny'),
              _episode('Sintel', 1, 3, 'Sintel'),
              _episode('TearsOfSteel', 1, 4, 'Tears of Steel'),
            ],
          },
          plot: series.plot,
          backdrop: series.backdrop,
          genre: series.genre,
          year: series.year,
        );
      case 'demo-spot':
        return SeriesDetails(
          seasons: const [1, 2],
          episodes: {
            1: [
              _episode('ForBiggerBlazes', 1, 1, 'Blazes'),
              _episode('ForBiggerEscapes', 1, 2, 'Escapes'),
              _episode('ForBiggerFun', 1, 3, 'Fun'),
            ],
            2: [
              _episode('ForBiggerJoyrides', 2, 1, 'Joyrides'),
              _episode('ForBiggerMeltdowns', 2, 2, 'Meltdowns'),
            ],
          },
          plot: series.plot,
          backdrop: series.backdrop,
          genre: series.genre,
        );
    }
    return null;
  }

  @override
  String urlFor(MediaItem item, {String liveFormat = 'ts'}) => item.url ?? '';
}

Episode _episode(String file, int season, int number, String title) => Episode(
      id: 'demo-$file',
      season: season,
      number: number,
      title: title,
      image: '$_base/images/$file.jpg',
      url: '$_base/$file.mp4',
      extension: 'mp4',
    );

MediaItem _movie(String file, String title, String category, {String? year, String? genre, String? plot}) =>
    MediaItem(
      kind: MediaKind.movie,
      id: 'demo-$file',
      name: title,
      categoryId: category,
      image: '$_base/images/$file.jpg',
      backdrop: '$_base/images/$file.jpg',
      plot: plot,
      genre: genre,
      year: year,
      url: '$_base/$file.mp4',
      extension: 'mp4',
    );

Catalog buildDemoCatalog() {
  const open = 'demo-open';
  const spot = 'demo-spot-cat';
  const cars = 'demo-cars';
  const spotPlot = 'Breve video dimostrativo in alta definizione.';
  const carPlot = 'Video dimostrativo a tema motori.';

  final movies = <MediaItem>[
    _movie('BigBuckBunny', 'Big Buck Bunny', open,
        year: '2008',
        genre: 'Animazione · Commedia',
        plot: 'Un coniglio gigante e gentile viene preso di mira da tre roditori dispettosi '
            'e decide di fargliela pagare. Il celebre corto della Blender Foundation.'),
    _movie('ElephantsDream', 'Elephants Dream', open,
        year: '2006',
        genre: 'Animazione · Fantascienza',
        plot: 'Due personaggi attraversano un\'enorme macchina surreale in cui nulla è come sembra. '
            'Il primo film realizzato interamente con software libero.'),
    _movie('Sintel', 'Sintel', open,
        year: '2010',
        genre: 'Animazione · Fantasy',
        plot: 'Una giovane guerriera attraversa terre ostili alla ricerca del drago '
            'che aveva salvato e cresciuto da cucciolo.'),
    _movie('TearsOfSteel', 'Tears of Steel', open,
        year: '2012',
        genre: 'Fantascienza',
        plot: 'In un futuro vicino, un gruppo di scienziati tenta di fermare un\'invasione di robot. '
            'Riprese reali ed effetti visivi.'),
    _movie('ForBiggerBlazes', 'For Bigger Blazes', spot, genre: 'Spot', plot: spotPlot),
    _movie('ForBiggerEscapes', 'For Bigger Escapes', spot, genre: 'Spot', plot: spotPlot),
    _movie('ForBiggerFun', 'For Bigger Fun', spot, genre: 'Spot', plot: spotPlot),
    _movie('ForBiggerJoyrides', 'For Bigger Joyrides', spot, genre: 'Spot', plot: spotPlot),
    _movie('ForBiggerMeltdowns', 'For Bigger Meltdowns', spot, genre: 'Spot', plot: spotPlot),
    _movie('SubaruOutbackOnStreetAndDirt', 'Subaru Outback su strada e sterrato', cars,
        genre: 'Motori', plot: carPlot),
    _movie('VolkswagenGTIReview', 'Volkswagen GTI: la prova', cars, genre: 'Motori', plot: carPlot),
    _movie('WeAreGoingOnBullrun', 'We Are Going On Bullrun', cars, genre: 'Motori', plot: carPlot),
    _movie('WhatCarCanYouGetForAGrand', 'What Car Can You Get For A Grand?', cars,
        genre: 'Motori', plot: carPlot),
  ];

  final series = <MediaItem>[
    const MediaItem(
      kind: MediaKind.series,
      id: 'demo-open-movies',
      name: 'Open Movies',
      categoryId: 'demo-series',
      image: '$_base/images/Sintel.jpg',
      backdrop: '$_base/images/TearsOfSteel.jpg',
      plot: 'I cortometraggi open source della Blender Foundation raccolti in una serie: '
          'un film per episodio.',
      genre: 'Animazione',
      year: '2006',
    ),
    const MediaItem(
      kind: MediaKind.series,
      id: 'demo-spot',
      name: 'Spot in alta definizione',
      categoryId: 'demo-series',
      image: '$_base/images/ForBiggerEscapes.jpg',
      backdrop: '$_base/images/ForBiggerBlazes.jpg',
      plot: 'Una raccolta di brevi video dimostrativi, divisi in due stagioni.',
      genre: 'Spot',
    ),
  ];

  const live = <MediaItem>[
    MediaItem(
      kind: MediaKind.live,
      id: 'demo-mux',
      name: 'Mux · Test HLS',
      categoryId: 'demo-live',
      number: 1,
      url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    ),
    MediaItem(
      kind: MediaKind.live,
      id: 'demo-apple',
      name: 'Apple · Bip Bop',
      categoryId: 'demo-live',
      number: 2,
      url: 'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8',
    ),
    MediaItem(
      kind: MediaKind.live,
      id: 'demo-akamai',
      name: 'Akamai · Diretta di prova',
      categoryId: 'demo-live',
      number: 3,
      url: 'https://cph-p2p-msl.akamaized.net/hls/live/2000341/test/master.m3u8',
    ),
  ];

  return Catalog.build(
    liveCategories: const [Category(id: 'demo-live', name: 'Canali di prova')],
    movieCategories: const [
      Category(id: open, name: 'Cinema open source'),
      Category(id: spot, name: 'Spot in alta definizione'),
      Category(id: cars, name: 'Motori'),
    ],
    seriesCategories: const [Category(id: 'demo-series', name: 'Serie di prova')],
    live: live,
    movies: movies,
    series: series,
    fetchedAt: DateTime.now().millisecondsSinceEpoch,
  );
}

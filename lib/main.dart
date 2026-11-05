import 'package:flutter/material.dart';

import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Le Fire Stick hanno poca RAM: limitiamo la cache delle immagini decodificate.
  final imageCache = PaintingBinding.instance.imageCache;
  imageCache.maximumSize = 250;
  imageCache.maximumSizeBytes = 80 << 20; // 80 MB
  runApp(const StreamingApp());
}

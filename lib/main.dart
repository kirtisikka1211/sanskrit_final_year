import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart'
    as mlkit;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sanskrit Handwriting',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const HandwritingPage(title: 'Sanskrit Handwriting (ML Kit)'),
    );
  }
}

class HandwritingPage extends StatefulWidget {
  const HandwritingPage({super.key, required this.title});

  final String title;

  @override
  State<HandwritingPage> createState() => _HandwritingPageState();
}

class _HandwritingPageState extends State<HandwritingPage> {
  final List<List<_TimedPoint>> _strokes = <List<_TimedPoint>>[]; // list of strokes, each is list of timed points
  final List<_TimedPoint> _currentStroke = <_TimedPoint>[];
  mlkit.DigitalInkRecognizer? _recognizer;
  String _recognized = '';
  bool _modelReady = false;
  bool _isRecognizing = false;
  double _strokeWidth = 3.0;
  List<String> _topCandidates = <String>[];

  @override
  void initState() {
    super.initState();
    _initRecognizer();
  }

  Future<void> _initRecognizer() async {
    try {
      const String languageCode = 'sa-Deva-IN';
      final mlkit.DigitalInkRecognizerModelManager modelManager =
          mlkit.DigitalInkRecognizerModelManager();
      final bool isDownloaded = await modelManager.isModelDownloaded(languageCode);
      if (!isDownloaded) {
        await modelManager.downloadModel(languageCode, isWifiRequired: false);
      }
      _recognizer = mlkit.DigitalInkRecognizer(languageCode: languageCode);
      setState(() {
        _modelReady = true;
      });
    } catch (e) {
      setState(() {
        _recognized = 'Model init failed: $e';
      });
    }
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _currentStroke.clear();
      _recognized = '';
    });
  }

  Future<void> _recognize() async {
    if (_recognizer == null || !_modelReady) return;
    if (_isRecognizing) return;
    setState(() {
      _isRecognizing = true;
    });

    try {
      final mlkit.Ink ink = _buildInk();
      final List<mlkit.RecognitionCandidate> candidates =
          await _recognizer!.recognize(ink);
      setState(() {
        _recognized = candidates.isNotEmpty ? candidates.first.text : '';
        _topCandidates = candidates.take(5).map((c) => c.text).toList();
      });
    } catch (e) {
      setState(() {
        _recognized = 'Recognition error: $e';
        _topCandidates = <String>[];
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRecognizing = false;
        });
      }
    }
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() {
      _strokes.removeLast();
    });
  }

  mlkit.Ink _buildInk() {
    final mlkit.Ink ink = mlkit.Ink();
    final List<mlkit.Stroke> strokes = <mlkit.Stroke>[];
    for (final List<_TimedPoint> strokePoints in _strokes) {
      final List<mlkit.StrokePoint> points = <mlkit.StrokePoint>[];
      for (final _TimedPoint p in strokePoints) {
        points.add(mlkit.StrokePoint(
            x: p.position.dx, y: p.position.dy, t: p.t));
      }
      final mlkit.Stroke stroke = mlkit.Stroke();
      stroke.points = points;
      strokes.add(stroke);
    }
    ink.strokes = strokes;
    return ink;
  }

  @override
  void dispose() {
    _recognizer?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: <Widget>[
          IconButton(
            onPressed: _modelReady && _strokes.isNotEmpty ? _recognize : null,
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Recognize',
          ),
          IconButton(
            onPressed: _strokes.isNotEmpty || _recognized.isNotEmpty ? _clear : null,
            icon: const Icon(Icons.clear),
            tooltip: 'Clear',
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Listener(
                onPointerDown: (PointerDownEvent e) {
                  setState(() {
                    _currentStroke.clear();
                    _currentStroke.add(_TimedPoint(position: e.localPosition, t: DateTime.now().millisecondsSinceEpoch));
                    _strokes.add(List<_TimedPoint>.from(_currentStroke));
                  });
                },
                onPointerMove: (PointerMoveEvent e) {
                  setState(() {
                    _currentStroke.add(_TimedPoint(position: e.localPosition, t: DateTime.now().millisecondsSinceEpoch));
                    _strokes.last = List<_TimedPoint>.from(_currentStroke);
                  });
                },
                onPointerUp: (PointerUpEvent e) {
                  setState(() {
                    _currentStroke.clear();
                  });
                },
                child: CustomPaint(
                  painter: _StrokePainter(strokes: _strokes, currentStroke: _currentStroke),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.grey.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(_modelReady ? 'Model: Sanskrit Devanagari (sa-Deva-IN) ready' : 'Downloading model...'),
                const SizedBox(height: 8),
                Text(_isRecognizing ? 'Recognizing...' : 'Result: $_recognized'),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    ElevatedButton(
                      onPressed: _modelReady && _strokes.isNotEmpty && !_isRecognizing ? _recognize : null,
                      child: const Text('Recognize'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _strokes.isNotEmpty || _recognized.isNotEmpty ? _clear : null,
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter({required this.strokes, required this.currentStroke});

  final List<List<_TimedPoint>> strokes;
  final List<_TimedPoint> currentStroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Draw completed strokes
    for (final List<_TimedPoint> stroke in strokes) {
      if (stroke.length < 2) continue;
      final Path path = Path()..moveTo(stroke.first.position.dx, stroke.first.position.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].position.dx, stroke[i].position.dy);
      }
      canvas.drawPath(path, paint);
    }

    // Draw current stroke being drawn
    if (currentStroke.length > 1) {
      final Path path = Path()..moveTo(currentStroke.first.position.dx, currentStroke.first.position.dy);
      for (int i = 1; i < currentStroke.length; i++) {
        path.lineTo(currentStroke[i].position.dx, currentStroke[i].position.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) {
    return oldDelegate.strokes != strokes || oldDelegate.currentStroke != currentStroke;
  }
}

class _TimedPoint {
  _TimedPoint({required this.position, required this.t});
  final Offset position;
  final int t;
}

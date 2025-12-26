import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart'
    as mlkit;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:open_filex/open_filex.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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
      home: const HomePage(),
      routes: <String, WidgetBuilder>{
        '/write': (_) => const HandwritingPage(title: 'Write in Devanagari'),
        '/recognitions': (_) => const RecognitionsPage(),
        '/mode': (_) => const ModeSelectPage(),
        '/qp/setup': (_) => const QuestionPaperSetupPage(),
      },
    );
  }
}

class HandwritingPage extends StatefulWidget {
  const HandwritingPage({super.key, required this.title});
  static const String route = '/write';

  final String title;

  @override
  State<HandwritingPage> createState() => _HandwritingPageState();
}

class _HandwritingPageState extends State<HandwritingPage> {
  final List<List<_TimedPoint>> _strokes = <List<_TimedPoint>>[]; // list of strokes, each is list of timed points
  List<_TimedPoint> _currentStroke = <_TimedPoint>[];
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
      if (_recognized.trim().isNotEmpty) {
        RecognitionsStore.instance.add(_recognized.trim());
      }
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
            onPressed: () {
              Navigator.of(context).pushNamed('/recognitions');
            },
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: 'View recognized',
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
                behavior: HitTestBehavior.opaque,
                onPointerDown: (PointerDownEvent e) {
                  setState(() {
                    _currentStroke = <_TimedPoint>[];
                    _currentStroke.add(_TimedPoint(position: e.localPosition, t: DateTime.now().millisecondsSinceEpoch));
                    _strokes.add(_currentStroke);
                  });
                },
                onPointerMove: (PointerMoveEvent e) {
                  setState(() {
                    _currentStroke.add(_TimedPoint(position: e.localPosition, t: DateTime.now().millisecondsSinceEpoch));
                  });
                },
                onPointerUp: (PointerUpEvent e) {
                  setState(() {
                    _currentStroke = <_TimedPoint>[];
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
                Text(_modelReady ? 'Model: Sanskrit Devanagari  ready' : 'Downloading model...'),
                const SizedBox(height: 8),
                Text(_isRecognizing ? 'Recognizing...' : 'Result: $_recognized'),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    ElevatedButton.icon(
                      onPressed: _modelReady && _strokes.isNotEmpty && !_isRecognizing ? _recognize : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Recognize'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _strokes.isNotEmpty || _recognized.isNotEmpty ? _clear : null,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Clear'),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pushNamed('/recognitions'),
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('View All'),
                    ),
                  ],
                ),
                if (_topCandidates.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _topCandidates
                        .map((String t) => InputChip(
                              label: Text(t),
                              onPressed: () {
                                setState(() {
                                  _recognized = t;
                                });
                                RecognitionsStore.instance.add(t);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Selected: $t')),
                                );
                              },
                            ))
                        .toList(),
                  ),
                ],
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

// ---------------------------
// Mode Selection Page
// ---------------------------

class ModeSelectPage extends StatelessWidget {
  const ModeSelectPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Mode'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            _ModeTile(
              icon: Icons.brush,
              title: 'Scribble',
              subtitle: 'Open the canvas to write and recognize',
              color: scheme.primaryContainer,
              onTap: () => Navigator.of(context).pushNamed('/write'),
            ),
            const SizedBox(height: 12),
            _ModeTile(
              icon: Icons.menu_book_outlined,
              title: 'View Recognized',
              subtitle: 'See all recognized results',
              color: scheme.secondaryContainer,
              onTap: () => Navigator.of(context).pushNamed('/recognitions'),
            ),
            const SizedBox(height: 12),
            _ModeTile(
              icon: Icons.assignment,
              title: 'Question Paper',
              subtitle: 'Specify number of questions and write answers',
              color: scheme.tertiaryContainer,
              onTap: () => Navigator.of(context).pushNamed('/qp/setup'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({required this.icon, required this.title, required this.subtitle, required this.onTap, required this.color});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(subtitle),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

// ---------------------------
// Question Paper Setup Page
// ---------------------------

class QuestionPaperSetupPage extends StatefulWidget {
  const QuestionPaperSetupPage({super.key});
  @override
  State<QuestionPaperSetupPage> createState() => _QuestionPaperSetupPageState();
}

class _QuestionPaperSetupPageState extends State<QuestionPaperSetupPage> {
  final TextEditingController _questionController = TextEditingController(text: '5');
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _timeController = TextEditingController(text: '3');
  final TextEditingController _sectionsController = TextEditingController(text: '1');
  @override
  void dispose() {
    _questionController.dispose();
    _titleController.dispose();
    _timeController.dispose();
    _sectionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Question Paper Setup')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Question Paper Title', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter question paper title (optional)',
              ),
            ),
            const SizedBox(height: 24),
            const Text('How many questions?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _questionController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Enter number of questions'),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('Time (Hours)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _timeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Hours'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('Sections', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _sectionsController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Sections'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final int n = int.tryParse(_questionController.text.trim()) ?? 0;
                  final int time = int.tryParse(_timeController.text.trim()) ?? 3;
                  final int sections = int.tryParse(_sectionsController.text.trim()) ?? 1;
                  if (n <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter valid number of questions')));
                    return;
                  }
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => QuestionPaperFlowPage(
                      numQuestions: n,
                      title: _titleController.text.trim().isEmpty ? null : _titleController.text.trim(),
                      timeHours: time,
                      sections: sections,
                    ),
                  ));
                },
                child: const Text('Continue'),
              ),
            ),
            const SizedBox(height: 16),
            const Text('You can write questions for each question on its own canvas and recognize them one by one.'),
          ],
        ),
      ),
    );
  }
}

// ---------------------------
// Question Paper Flow Page
// ---------------------------

class QuestionPaperFlowPage extends StatefulWidget {
  const QuestionPaperFlowPage({super.key, required this.numQuestions, this.title, this.timeHours = 3, this.sections = 1});
  final int numQuestions;
  final String? title;
  final int timeHours;
  final int sections;
  @override
  State<QuestionPaperFlowPage> createState() => _QuestionPaperFlowPageState();
}

class _QuestionPaperFlowPageState extends State<QuestionPaperFlowPage> with TickerProviderStateMixin {
  late final TabController _tabController = TabController(length: widget.numQuestions, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _goToNext() {
    if (_tabController.index < _tabController.length - 1) {
      _tabController.animateTo(_tabController.index + 1);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => QuestionPaperSummaryPage(
            totalQuestions: widget.numQuestions,
            title: widget.title,
            timeHours: widget.timeHours,
            sections: widget.sections,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Question Paper • Q${_tabController.index + 1}/${widget.numQuestions}'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: List<Widget>.generate(widget.numQuestions, (int i) => Tab(text: 'Q${i + 1}')),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: List<Widget>.generate(
          widget.numQuestions,
          (int i) => _QuestionPane(
            questionIndex: i + 1,
            isLast: i == widget.numQuestions - 1,
            onNext: _goToNext,
          ),
        ),
      ),
    );
  }
}

// ---------------------------
// Question Paper Summary Page
// ---------------------------

class QuestionPaperSummaryPage extends StatefulWidget {
  const QuestionPaperSummaryPage({super.key, required this.totalQuestions, this.title, this.timeHours = 3, this.sections = 1});
  final int totalQuestions;
  final String? title;
  final int timeHours;
  final int sections;
  @override
  State<QuestionPaperSummaryPage> createState() => _QuestionPaperSummaryPageState();
}

class _QuestionPaperSummaryPageState extends State<QuestionPaperSummaryPage> {
  static pw.Font? _devanagariFont;
  static bool _fontLoading = false;
  final Map<int, int> _marks = <int, int>{}; // Store marks for each question

  Future<pw.Font> _loadDevanagariFont() async {
    if (_devanagariFont != null) {
      return _devanagariFont!;
    }

    if (_fontLoading) {
      // Wait a bit if font is being loaded
      int attempts = 0;
      while (_fontLoading && attempts < 10) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        attempts++;
        if (_devanagariFont != null) {
          return _devanagariFont!;
        }
      }
    }

    try {
      _fontLoading = true;
      // Load font from app assets
      final ByteData fontData = await rootBundle.load('assets/fonts/NotoSansDevanagari-VariableFont_wdth,wght.ttf');
      _devanagariFont = pw.Font.ttf(fontData.buffer.asByteData());

      _fontLoading = false;
      return _devanagariFont!;
    } catch (e) {
      _fontLoading = false;
      // If font loading fails, use default font (may not render Devanagari correctly)
      return pw.Font.courier();
    }
  }

  Map<int, String> _getQuestionsMap() {
    final Map<int, String> byQ = <int, String>{};
    for (int i = 1; i <= widget.totalQuestions; i++) {
      final List<RecognizedEntry> list = RecognitionsStore.instance.byQuestion(i);
      final String combined = list.map((RecognizedEntry e) => e.text.replaceFirst('Q$i: ', '')).join(' ');
      byQ[i] = combined;
    }
    return byQ;
  }

  String _getGeneratedPaperContent() {
    final Map<int, String> byQ = _getQuestionsMap();
    return List<int>.generate(widget.totalQuestions, (int i) => i + 1)
        .map((int q) => 'Q$q: ${byQ[q] ?? ''}')
        .join('\n\n');
  }

  Future<void> _showMarksDialog(int questionNumber) async {
    final TextEditingController controller = TextEditingController(
      text: _marks[questionNumber]?.toString() ?? '',
    );
    
    final int? result = await showDialog<int>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Enter Marks for Q$questionNumber'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Marks',
            hintText: 'Enter marks',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              setState(() {
                _marks.remove(questionNumber);
              });
              Navigator.of(context).pop();
            },
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final String text = controller.text.trim();
              if (text.isNotEmpty) {
                final int? marks = int.tryParse(text);
                if (marks != null && marks >= 0) {
                  Navigator.of(context).pop(marks);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid number')),
                  );
                }
              } else {
                Navigator.of(context).pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        _marks[questionNumber] = result;
      });
    }
  }

  void _showLoadingDialog([String message = 'Generating document...']) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showFormatDialog() async {
    final String? selectedFormat = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Choose Format'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('PDF'),
              subtitle: const Text('Read-only format, perfect for sharing'),
              onTap: () => Navigator.of(context).pop('pdf'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.description, color: Colors.blue),
              title: const Text('Document (DOC)'),
              subtitle: const Text('Editable format, can be opened in Word/Google Docs'),
              onTap: () => Navigator.of(context).pop('doc'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selectedFormat != null) {
      if (selectedFormat == 'pdf') {
        await _downloadPaperAsPdf();
      } else if (selectedFormat == 'doc') {
        await _downloadPaperAsDoc();
      }
    }
  }

  String _escapeRtfText(String text) {
    // Escape RTF special characters and convert to Unicode escape sequences
    final StringBuffer buffer = StringBuffer();
    final Runes runes = text.runes;
    for (final int codePoint in runes) {
      if (codePoint < 128) {
        // ASCII characters - escape special RTF characters
        if (codePoint == 0x5C || codePoint == 0x7B || codePoint == 0x7D) {
          // Escape \, {, }
          buffer.write('\\${String.fromCharCode(codePoint)}');
        } else if (codePoint == 0x0A) {
          // Newline
          buffer.write('\\par\n');
        } else {
          buffer.writeCharCode(codePoint);
        }
      } else {
        // Unicode characters - use \u escape sequence
        // RTF uses signed 16-bit integers, but we'll handle full Unicode range
        if (codePoint <= 32767) {
          buffer.write('\\u${codePoint}?');
        } else {
          // For characters outside 16-bit range, use UTF-16 surrogate pairs
          final int hi = 0xD800 + ((codePoint - 0x10000) >> 10);
          final int lo = 0xDC00 + ((codePoint - 0x10000) & 0x3FF);
          buffer.write('\\u${hi - 65536}?\\u${lo - 65536}?');
        }
      }
    }
    return buffer.toString();
  }

  String _generateDocContent() {
    final Map<int, String> byQ = _getQuestionsMap();
    final StringBuffer rtf = StringBuffer();
    
    // RTF header
    rtf.writeln('{\\rtf1\\ansi\\ansicpg1252\\deff0\\nouicompat\\deflang1033');
    rtf.writeln('{\\fonttbl{\\f0\\fnil\\fcharset0 Noto Sans Devanagari;}}');
    rtf.writeln('{\\*\\generator Sanskrit Handwriting App}');
    rtf.writeln('\\viewkind4\\uc1 ');
    rtf.writeln('\\pard\\sa200\\sl276\\slmult1\\f0\\fs22\\lang9\\par');
    
    // Standard Question Paper Header
    final String title = widget.title?.isNotEmpty ?? false ? widget.title! : 'QUESTION PAPER';
    final int totalMarks = _marks.values.fold(0, (sum, marks) => sum + marks);
    
    rtf.writeln('\\pard\\qc{\\b\\fs28 ${_escapeRtfText(title)}\\par}');
    rtf.writeln('\\par');
    rtf.writeln('\\trowd\\trgaph108\\trleft-108');
    rtf.writeln('\\cellx4500\\cellx9000');
    rtf.write('Time: ${widget.timeHours} Hour${widget.timeHours > 1 ? 's' : ''}\\cell');
    rtf.write('Maximum Marks: $totalMarks\\cell\\row');
    rtf.writeln('\\par');
    
    rtf.writeln('\\pard\\ql{\\b INSTRUCTIONS:\\par}');
    rtf.writeln('1. All questions are compulsory.\\par');
    rtf.writeln('2. Write your answers in the space provided.\\par');
    rtf.writeln('3. Figures to the right indicate full marks.\\par');
    rtf.writeln('\\par');
    
    // Generate sections
    final int questionsPerSection = (widget.totalQuestions / widget.sections).ceil();
    int currentQuestion = 1;
    
    for (int section = 1; section <= widget.sections; section++) {
      final String sectionName = widget.sections == 1 ? 'SECTION - A' : 'SECTION - ${String.fromCharCode(64 + section)}';
      rtf.writeln('\\pard\\qc{\\b\\fs20 $sectionName\\par}');
      rtf.writeln('\\par');
      
      final int endQuestion = (currentQuestion + questionsPerSection - 1).clamp(currentQuestion, widget.totalQuestions);
      
      for (int q = currentQuestion; q <= endQuestion && q <= widget.totalQuestions; q++) {
        final String text = byQ[q] ?? '';
        final String content = text.isEmpty ? '[Write your question here]' : text;
        final int marks = _marks[q] ?? 5;
        
        rtf.writeln('\\trowd\\trgaph108\\trleft-108');
        rtf.writeln('\\cellx8000\\cellx9000');
        rtf.write('{\\b Q.$q} ${_escapeRtfText(content)}\\cell');
        rtf.write('{\\b [$marks]}\\cell\\row');
        rtf.writeln('\\par');
        rtf.writeln('\\par');
        rtf.writeln('\\par');
      }
      
      currentQuestion = endQuestion + 1;
      if (currentQuestion > widget.totalQuestions) break;
    }
    
    rtf.write('}');
    return rtf.toString();
  }

  Future<void> _downloadPaperAsDoc() async {
    _showLoadingDialog('Generating Document...');
    try {
      final String docContent = _generateDocContent();
      
      // Save DOC document to file
      final Directory directory = await getApplicationDocumentsDirectory();
      final String fileName = 'question_paper_${DateTime.now().millisecondsSinceEpoch}.doc';
      final String filePath = '${directory.path}/$fileName';
      final File file = File(filePath);
      await file.writeAsString(docContent, encoding: utf8);
      
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
        
        // Show success dialog with option to open
        showDialog(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('Document Downloaded'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('Question paper document has been saved successfully.'),
                const SizedBox(height: 8),
                Text(
                  'Location: $filePath',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                const Text(
                  'You can open and edit this file in Microsoft Word, Google Docs, or any word processor.',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  final OpenResult result = await OpenFilex.open(filePath);
                  if (result.type != ResultType.done && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not open file: ${result.message}')),
                    );
                  }
                },
                child: const Text('Open Document'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // Close loading dialog if still open
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  Future<void> _downloadPaperAsPdf() async {
    _showLoadingDialog('Generating PDF...');
    try {
      final Map<int, String> byQ = _getQuestionsMap();
      
      // Load Devanagari font from assets
      final pw.Font devanagariFont = await _loadDevanagariFont();
      
      // Create PDF document
      final pw.Document pdf = pw.Document(
  theme: pw.ThemeData.withFont(
    base: devanagariFont,
    bold: devanagariFont,
  ),
);

      
      // Add content to PDF
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            final int totalMarks = _marks.values.fold(0, (sum, marks) => sum + marks);
            return <pw.Widget>[
              // Standard Question Paper Header
              pw.Center(
                child: pw.Text(
                  widget.title?.isNotEmpty ?? false ? widget.title!.toUpperCase() : 'QUESTION PAPER',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    font: devanagariFont,
                  ),
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: <pw.Widget>[
                  pw.Text('Time: ${widget.timeHours} Hour${widget.timeHours > 1 ? 's' : ''}', style: pw.TextStyle(fontSize: 12, font: devanagariFont)),
                  pw.Text('Maximum Marks: $totalMarks', style: pw.TextStyle(fontSize: 12, font: devanagariFont)),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                'INSTRUCTIONS:',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, font: devanagariFont),
              ),
              pw.Text('1. All questions are compulsory.', style: pw.TextStyle(fontSize: 10, font: devanagariFont)),
              pw.Text('2. Write your answers in the space provided.', style: pw.TextStyle(fontSize: 10, font: devanagariFont)),
              pw.Text('3. Figures to the right indicate full marks.', style: pw.TextStyle(fontSize: 10, font: devanagariFont)),
              pw.SizedBox(height: 20),
              
              // Generate sections
              ...() {
                final List<pw.Widget> widgets = <pw.Widget>[];
                final int questionsPerSection = (widget.totalQuestions / widget.sections).ceil();
                int currentQuestion = 1;
                
                for (int section = 1; section <= widget.sections; section++) {
                  final String sectionName = widget.sections == 1 ? 'SECTION - A' : 'SECTION - ${String.fromCharCode(64 + section)}';
                  widgets.add(
                    pw.Center(
                      child: pw.Text(
                        sectionName,
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, font: devanagariFont),
                      ),
                    ),
                  );
                  widgets.add(pw.SizedBox(height: 20));
                  
                  final int endQuestion = (currentQuestion + questionsPerSection - 1).clamp(currentQuestion, widget.totalQuestions);
                  
                  for (int q = currentQuestion; q <= endQuestion && q <= widget.totalQuestions; q++) {
                    final String text = byQ[q] ?? '';
                    final String content = text.isEmpty ? '[Write your question here]' : text;
                    final int marks = _marks[q] ?? 5;
                    widgets.add(
                      pw.Container(
                        margin: const pw.EdgeInsets.only(bottom: 30),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: <pw.Widget>[
                            pw.Expanded(
                              child: pw.Text(
                                'Q.$q $content',
                                style: pw.TextStyle(
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                  font: devanagariFont,
                                ),
                              ),
                            ),
                            pw.Text(
                              '[$marks]',
                              style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                                font: devanagariFont,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  
                  currentQuestion = endQuestion + 1;
                  if (currentQuestion > widget.totalQuestions) break;
                }
                return widgets;
              }(),
            ];
          },
        ),
      );
      
      // Save PDF to file
      final Directory directory = await getApplicationDocumentsDirectory();
      final String fileName = 'question_paper_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final String filePath = '${directory.path}/$fileName';
      final File file = File(filePath);
      await file.writeAsBytes(await pdf.save());
      
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
        
        // Show success dialog with option to view
        showDialog(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('Paper Downloaded'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('Question paper has been saved successfully.'),
                const SizedBox(height: 8),
                Text(
                  'Location: $filePath',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PdfViewerPage(filePath: filePath, fileName: fileName),
                    ),
                  );
                },
                child: const Text('View Paper'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // Close loading dialog if still open
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<int, String> byQ = _getQuestionsMap();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Question Paper Summary'),
        actions: <Widget>[
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              onPressed: _showFormatDialog,
              icon: const Icon(Icons.download),
              label: const Text('Download'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: 'Copy all',
            onPressed: () async {
              final String entire = _getGeneratedPaperContent();
              await Clipboard.setData(ClipboardData(text: entire));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All copied')));
              }
            },
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: widget.totalQuestions,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (BuildContext context, int index) {
          final int q = index + 1;
          final String text = byQ[q] ?? '';
          final int? marks = _marks[q];
          return Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              onTap: () => _showMarksDialog(q),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text('Q$q', style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (marks != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(Icons.star, size: 16, color: Colors.blue.shade900),
                                const SizedBox(width: 4),
                                Text(
                                  '$marks marks',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              border: Border.all(color: Colors.green.shade300),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(Icons.add_circle_outline, size: 16, color: Colors.green.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  'Add Marks',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green.shade700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(text.isEmpty ? '(No Question)' : text, style: const TextStyle(fontSize: 16, height: 1.4)),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: text));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                          }
                        },
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('Copy'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------
// PDF Viewer Page
// ---------------------------

class PdfViewerPage extends StatelessWidget {
  const PdfViewerPage({super.key, required this.filePath, required this.fileName});
  final String filePath;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Question Paper PDF'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Open in external app',
            onPressed: () async {
              final OpenResult result = await OpenFilex.open(filePath);
              if (result.type != ResultType.done && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not open file: ${result.message}')),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share PDF',
            onPressed: () async {
              final File file = File(filePath);
              if (await file.exists()) {
                await Printing.sharePdf(
                  bytes: await file.readAsBytes(),
                  filename: fileName,
                );
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<Uint8List>(
        future: File(filePath).readAsBytes().then((List<int> bytes) => Uint8List.fromList(bytes)),
        builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error loading PDF: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            );
          }
          if (snapshot.hasData) {
            return PdfPreview(
              build: (PdfPageFormat format) async => snapshot.data!,
              allowPrinting: true,
              allowSharing: true,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
            );
          }
          return const Center(child: Text('No data available'));
        },
      ),
    );
  }
}

class _QuestionPane extends StatefulWidget {
  const _QuestionPane({required this.questionIndex, required this.isLast, required this.onNext});
  final int questionIndex;
  final bool isLast;
  final VoidCallback onNext;
  @override
  State<_QuestionPane> createState() => _QuestionPaneState();
}

class _QuestionPaneState extends State<_QuestionPane> {
  final GlobalKey<_HandwritingCanvasState> _canvasKey = GlobalKey<_HandwritingCanvasState>();
  String _result = '';
  List<String> _candidates = <String>[];
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _speechText = '';

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
  }
    return Column(
      children: <Widget>[
        Expanded(child: HandwritingCanvas(key: _canvasKey)),
        Container(
          width: double.infinity,
          color: Colors.grey.shade100,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Result (Q${widget.questionIndex}): $_result'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.start,
                children: <Widget>[
                  ElevatedButton.icon(
                    onPressed: () async {
                      final List<String> cands = await _canvasKey.currentState!.recognizeCandidates();
                      final String text = cands.isNotEmpty ? cands.first : '';
                      setState(() {
                        _result = text;
                        _candidates = cands;
                      });
                      if (text.trim().isNotEmpty) {
                        RecognitionsStore.instance.add('Q${widget.questionIndex}: $text');
                      }
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Recognize'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _canvasKey.currentState!.clear(),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => QuestionAnswerViewPage(questionIndex: widget.questionIndex),
                        ),
                      );
                    },
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('View'),
                  ),
                  ElevatedButton.icon(
                    onPressed: widget.onNext,
                    icon: Icon(widget.isLast ? Icons.check : Icons.arrow_forward),
                    label: Text(widget.isLast ? 'Finish' : 'Next'),
                  ),
                ],
              ),
              if (_candidates.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _candidates
                      .map((String t) => InputChip(
                            label: Text(t),
                            onPressed: () {
                              setState(() {
                                _result = t;
                              });
                              RecognitionsStore.instance.add('Q${widget.questionIndex}: $t');
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Selected: $t')),
                              );
                            },
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// A reusable canvas widget using the same stroke logic and recognizer
class HandwritingCanvas extends StatefulWidget {
  const HandwritingCanvas({super.key});
  @override
  State<HandwritingCanvas> createState() => _HandwritingCanvasState();
}

class _HandwritingCanvasState extends State<HandwritingCanvas> {
  final List<List<_TimedPoint>> _strokes = <List<_TimedPoint>>[];
  List<_TimedPoint> _currentStroke = <_TimedPoint>[];
  mlkit.DigitalInkRecognizer? _recognizer;
  bool _modelReady = false;

  @override
  void initState() {
    super.initState();
    _initRecognizer();
  }

  Future<void> _initRecognizer() async {
    try {
      const String languageCode = 'sa-Deva-IN';
      final mlkit.DigitalInkRecognizerModelManager modelManager = mlkit.DigitalInkRecognizerModelManager();
      final bool isDownloaded = await modelManager.isModelDownloaded(languageCode);
      if (!isDownloaded) {
        await modelManager.downloadModel(languageCode, isWifiRequired: false);
      }
      _recognizer = mlkit.DigitalInkRecognizer(languageCode: languageCode);
      setState(() => _modelReady = true);
    } catch (_) {
      setState(() => _modelReady = false);
    }
  }

  Future<String> recognize() async {
    if (_recognizer == null || !_modelReady) return '';
    final mlkit.Ink ink = _buildInk();
    final List<mlkit.RecognitionCandidate> candidates = await _recognizer!.recognize(ink);
    return candidates.isNotEmpty ? candidates.first.text : '';
  }

  Future<List<String>> recognizeCandidates({int maxResults = 5}) async {
    if (_recognizer == null || !_modelReady) return <String>[];
    final mlkit.Ink ink = _buildInk();
    final List<mlkit.RecognitionCandidate> candidates = await _recognizer!.recognize(ink);
    return candidates.take(maxResults).map((mlkit.RecognitionCandidate c) => c.text).toList();
  }

  void clear() {
    setState(() {
      _strokes.clear();
      _currentStroke.clear();
    });
  }

  mlkit.Ink _buildInk() {
    final mlkit.Ink ink = mlkit.Ink();
    final List<mlkit.Stroke> strokes = <mlkit.Stroke>[];
    for (final List<_TimedPoint> strokePoints in _strokes) {
      final List<mlkit.StrokePoint> points = <mlkit.StrokePoint>[];
      for (final _TimedPoint p in strokePoints) {
        points.add(mlkit.StrokePoint(x: p.position.dx, y: p.position.dy, t: p.t));
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
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (PointerDownEvent e) {
          setState(() {
            _currentStroke = <_TimedPoint>[];
            _currentStroke.add(_TimedPoint(position: e.localPosition, t: DateTime.now().millisecondsSinceEpoch));
            _strokes.add(_currentStroke);
          });
        },
        onPointerMove: (PointerMoveEvent e) {
          setState(() {
            _currentStroke.add(_TimedPoint(position: e.localPosition, t: DateTime.now().millisecondsSinceEpoch));
          });
        },
        onPointerUp: (PointerUpEvent e) {
          setState(() {
            _currentStroke = <_TimedPoint>[];
          });
        },
        child: CustomPaint(
          painter: _StrokePainter(strokes: _strokes, currentStroke: _currentStroke),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
// ---------------------------
// Home Page
// ---------------------------

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.inversePrimary,
        title: const Text('Sanskrit Handwriting'),
      ),
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              scheme.surfaceVariant.withOpacity(0.4),
              scheme.surface,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                const SizedBox(height: 12),
                CircleAvatar(
                  radius: 44,
                  backgroundColor: scheme.primaryContainer,
                  child: Text('ॐ', style: TextStyle(fontSize: 40, color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 14),
                Text(
                  'Sanskrit Handwriting',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                const Text(
                  'संस्कृत हस्तलेखन (देवनागरी)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Write in Devanagari and get instant on-device recognition.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: const <Widget>[
                          Icon(Icons.gesture, size: 20),
                          SizedBox(width: 8),
                          Expanded(child: Text('Smooth strokes with tap-to-choose suggestions')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: const <Widget>[
                          Icon(Icons.translate, size: 20),
                          SizedBox(width: 8),
                          Expanded(child: Text('Focused on Sanskrit • देवनागरी लिपि')),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: const <Widget>[
                          Chip(label: Text('संस्कृत')),
                          Chip(label: Text('देवनागरी')),
                          Chip(label: Text('On-device')),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pushNamed('/mode'),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('Start'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pushNamed('/recognitions'),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('View Recognized Texts'),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------
// Recognitions Store
// ---------------------------

class RecognitionsStore {
  RecognitionsStore._internal();
  static final RecognitionsStore instance = RecognitionsStore._internal();

  final ValueNotifier<List<RecognizedEntry>> entries =
      ValueNotifier<List<RecognizedEntry>>(<RecognizedEntry>[]);

  void add(String text) {
    final List<RecognizedEntry> updated = List<RecognizedEntry>.from(entries.value)
      ..insert(0, RecognizedEntry(text: text, time: DateTime.now()));
    entries.value = updated;
  }

  void clear() {
    entries.value = <RecognizedEntry>[];
  }

  List<RecognizedEntry> byQuestion(int questionIndex) {
    final String prefix = 'Q$questionIndex:';
    final List<RecognizedEntry> filtered = entries.value
        .where((RecognizedEntry e) => e.text.startsWith(prefix))
        .toList();
    filtered.sort((RecognizedEntry a, RecognizedEntry b) => a.time.compareTo(b.time));
    return filtered;
  }
}

class RecognizedEntry {
  RecognizedEntry({required this.text, required this.time});
  final String text;
  final DateTime time;
}

// ---------------------------
// Recognitions Page
// ---------------------------

class RecognitionsPage extends StatefulWidget {
  const RecognitionsPage({super.key});

  @override
  State<RecognitionsPage> createState() => _RecognitionsPageState();
}

class _RecognitionsPageState extends State<RecognitionsPage> {
  int _tabIndex = 0; // 0: entries, 1: paragraph

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recognized Texts'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear all',
            onPressed: () => RecognitionsStore.instance.clear(),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<int>(
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(value: 0, label: Text('Entries'), icon: Icon(Icons.list)),
                ButtonSegment<int>(value: 1, label: Text('Paragraph'), icon: Icon(Icons.subject)),
              ],
              selected: <int>{_tabIndex},
              onSelectionChanged: (Set<int> s) {
                setState(() => _tabIndex = s.first);
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ValueListenableBuilder<List<RecognizedEntry>>(
              valueListenable: RecognitionsStore.instance.entries,
              builder: (BuildContext context, List<RecognizedEntry> list, Widget? _) {
                if (list.isEmpty) {
                  return const Center(child: Text('No recognized texts yet.'));
                }
                if (_tabIndex == 0) {
                  return ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) {
                      final RecognizedEntry entry = list[index];
                      return Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          title: Text(entry.text, style: const TextStyle(fontSize: 18)),
                          subtitle: Text(_formatTime(entry.time), style: const TextStyle(fontSize: 12)),
                          trailing: IconButton(
                            icon: const Icon(Icons.copy_all_outlined),
                            tooltip: 'Copy',
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: entry.text));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Copied to clipboard')),
                                );
                              }
                            },
                          ),
                        ),
                      );
                    },
                  );
                }
                // Paragraph mode
                final String combined = list.map((RecognizedEntry e) => e.text).join(' ');
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                          ),
                          child: SingleChildScrollView(
                            child: Text(
                              combined,
                              style: const TextStyle(fontSize: 18, height: 1.5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: combined));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Paragraph copied')),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy_all_outlined),
                          label: const Text('Copy Paragraph'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

}

// ---------------------------
// Question Answer View Page
// ---------------------------

class QuestionAnswerViewPage extends StatefulWidget {
  const QuestionAnswerViewPage({super.key, required this.questionIndex});
  final int questionIndex;

  @override
  State<QuestionAnswerViewPage> createState() => _QuestionAnswerViewPageState();
}

class _QuestionAnswerViewPageState extends State<QuestionAnswerViewPage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final List<RecognizedEntry> list = RecognitionsStore.instance.byQuestion(widget.questionIndex);
    final String combined = list.map((RecognizedEntry e) => e.text.replaceFirst('Q${widget.questionIndex}: ', '')).join(' ');
    _controller = TextEditingController(text: combined);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Question ${widget.questionIndex}')
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Append or edit your answer here',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _controller.text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paragraph copied')));
                    }
                  },
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Copy Paragraph'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    final String value = _controller.text.trim();
                    if (value.isEmpty) return;
                    RecognitionsStore.instance.add('Q${widget.questionIndex}: $value');
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appended to end')));
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Append'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// removed extension; route is now defined on HandwritingPage
String _formatTimeLocal(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

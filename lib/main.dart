import 'package:flutter/material.dart';

void main() => runApp(const FlipleafApp());

class FlipleafApp extends StatelessWidget {
  const FlipleafApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flipleaf',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0A4A2E))),
      home: const FlipleafEditor(),
    );
  }
}

class FormatRange {
  int start, end;
  bool bold, italic, underline;
  Color? color;
  double? fontSize;
  FormatRange(this.start, this.end, {this.bold = false, this.italic = false, this.underline = false, this.color, this.fontSize});
}

class FlipleafEditor extends StatefulWidget {
  const FlipleafEditor({super.key});
  @override
  State<FlipleafEditor> createState() => _FlipleafEditorState();
}

class _FlipleafEditorState extends State<FlipleafEditor> {
  final TextEditingController _controller = TextEditingController(text: "Welcome to Flipleaf. Select any text here, then tap B, I, U or colors to format it.");
  List<FormatRange> _formats = [];
  double _baseFontSize = 18;
  Color _selectedColor = Colors.black;

  // Timer
  int _seconds = 0;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (_isRunning && mounted) {
        setState(() => _seconds++);
      }
      return mounted;
    });
  }

  void _applyFormat({bool? bold, bool? italic, bool? underline, Color? color, double? fontSizeChange}) {
    final sel = _controller.selection;
    if (!sel.isValid || sel.isCollapsed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("First highlight/select text, then tap B/I/U"), duration: Duration(seconds: 2)));
      return;
    }
    setState(() {
      if (fontSizeChange!= null) {
        _formats.add(FormatRange(sel.start, sel.end, fontSize: _baseFontSize + fontSizeChange));
      } else {
        _formats.add(FormatRange(sel.start, sel.end, bold: bold?? false, italic: italic?? false, underline: underline?? false, color: color));
      }
    });
  }

  List<TextSpan> _buildSpans() {
    String text = _controller.text;
    if (text.isEmpty) return [TextSpan(text: "", style: TextStyle(fontSize: _baseFontSize))];

    List<TextSpan> spans = [];
    for (int i = 0; i < text.length; i++) {
      bool b = false, it = false, u = false;
      Color col = _selectedColor;
      double fs = _baseFontSize;
      for (var f in _formats) {
        if (i >= f.start && i < f.end) {
          if (f.bold) b = true;
          if (f.italic) it = true;
          if (f.underline) u = true;
          if (f.color!= null) col = f.color!;
          if (f.fontSize!= null) fs = f.fontSize!;
        }
      }
      spans.add(TextSpan(
        text: text[i],
        style: TextStyle(
          fontWeight: b? FontWeight.bold : FontWeight.normal,
          fontStyle: it? FontStyle.italic : FontStyle.normal,
          decoration: u? TextDecoration.underline : TextDecoration.none,
          color: col,
          fontSize: fs,
        ),
      ));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    String dateStr = "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}";
    return Scaffold(
      appBar: AppBar(
        title: Text("Flipleaf - $dateStr - ${_seconds}s"),
        backgroundColor: const Color(0xFF0A4A2E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: Icon(_isRunning? Icons.pause : Icons.play_arrow), onPressed: () => setState(() => _isRunning =!_isRunning)),
          IconButton(icon: const Icon(Icons.restart_alt), onPressed: () => setState(() => _seconds = 0)),
        ],
      ),
      body: Column(
        children: [
          // Formatting Toolbar
          Container(
            color: Colors.grey[100],
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 6,
              children: [
                _toolBtn("B", FontWeight.bold, () => _applyFormat(bold: true)),
                _toolBtn("I", FontWeight.normal, () => _applyFormat(italic: true), italic: true),
                _toolBtn("U", FontWeight.normal, () => _applyFormat(underline: true), underline: true),
                const VerticalDivider(),
                IconButton(icon: const Icon(Icons.text_increase), onPressed: () => _applyFormat(fontSizeChange: 2), tooltip: "Increase font"),
                IconButton(icon: const Icon(Icons.text_decrease), onPressed: () => _applyFormat(fontSizeChange: -2), tooltip: "Decrease font"),
                IconButton(icon: const Icon(Icons.format_size), onPressed: () { setState(() => _formats.clear()); }, tooltip: "Clear formatting"),
                // Colors
               ...[Colors.black, Colors.red, Colors.blue, const Color(0xFF0A4A2E), Colors.purple, Colors.orange].map((c) =>
                  GestureDetector(onTap: () => _applyFormat(color: c), child: Container(width: 28, height: 28, margin: const EdgeInsets.all(2), decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all()))))
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // Editable area
                  TextField(
                    controller: _controller,
                    maxLines: 5,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "Type here, then SELECT text to format"),
                  ),
                  const SizedBox(height: 12),
                  const Align(alignment: Alignment.centerLeft, child: Text("Preview (with highlight formatting):", style: TextStyle(fontWeight: FontWeight.bold))),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
                      child: SingleChildScrollView(child: RichText(text: TextSpan(children: _buildSpans()))),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolBtn(String label, FontWeight fw, VoidCallback onTap, {bool italic = false, bool underline = false}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(border: Border.all(), borderRadius: BorderRadius.circular(4)),
        child: Text(label, style: TextStyle(fontWeight: fw, fontStyle: italic? FontStyle.italic : FontStyle.normal, decoration: underline? TextDecoration.underline : null)),
      ),
    );
  }
}

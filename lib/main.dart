import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const FlipleafApp());
}

class FlipleafApp extends StatelessWidget {
  const FlipleafApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FlipleafEditor(),
    );
  }
}

class FormatRange {
  int start;
  int end;
  bool bold;
  bool italic;
  bool underline;
  double? fontSize;
  FormatRange(this.start, this.end, {this.bold = false, this.italic = false, this.underline = false, this.fontSize});
}

class PageData {
  String text;
  List<FormatRange> formats;
  double fontSize;
  PageData({this.text = "", List<FormatRange>? formats, this.fontSize = 18}) : formats = formats?? [];
  PageData copy() {
    List<FormatRange> newList = [];
    for (var e in formats) {
      newList.add(FormatRange(e.start, e.end, bold: e.bold, italic: e.italic, underline: e.underline, fontSize: e.fontSize));
    }
    return PageData(text: text, formats: newList, fontSize: fontSize);
  }
}

class RichController extends TextEditingController {
  List<FormatRange> formats;
  double baseSize;
  RichController({String? text, required this.formats, required this.baseSize}) : super(text: text);

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (text.isEmpty) {
      return TextSpan(text: "", style: style);
    }
    List<TextSpan> children = [];
    for (int i = 0; i < text.length; i++) {
      bool b = false;
      bool it = false;
      bool u = false;
      double fs = baseSize;
      for (var f in formats) {
        if (i >= f.start && i < f.end) {
          if (f.bold) b = true;
          if (f.italic) it = true;
          if (f.underline) u = true;
          if (f.fontSize!= null) fs = f.fontSize!;
        }
      }
      children.add(TextSpan(
        text: text[i],
        style: TextStyle(
          fontWeight: b? FontWeight.bold : FontWeight.normal,
          fontStyle: it? FontStyle.italic : FontStyle.normal,
          decoration: u? TextDecoration.underline : TextDecoration.none,
          fontSize: fs,
        ),
      ));
    }
    return TextSpan(children: children, style: style);
  }
}

class FlipleafEditor extends StatefulWidget {
  const FlipleafEditor({super.key});
  @override
  State<FlipleafEditor> createState() => _FlipleafEditorState();
}

class _FlipleafEditorState extends State<FlipleafEditor> {
  List<PageData> pages = [PageData(text: "I want to build a new and a different app. This time it's a note-pad app.")];
  int cur = 0;
  late RichController ctrl;
  List<PageData> undoStack = [];
  List<PageData> redoStack = [];

  Map<String, Color> bgColors = {
    "White": Colors.white,
    "Black": const Color(0xFFE0E0E0),
    "Blue": const Color(0xFFE3F2FD),
    "Green": const Color(0xFFE8F5E9),
    "Pink": const Color(0xFFFCE4EC),
    "Yellow": const Color(0xFFFFF9C4),
    "Brown": const Color(0xFFEFEBE9),
    "Purple": const Color(0xFFF3E5F5),
  };
  String bgName = "White";
  int timerSec = 5;
  int elapsed = 0;
  bool playing = false;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    initCtrl();
  }

  void initCtrl() {
    ctrl = RichController(text: pages[cur].text, formats: pages[cur].formats, baseSize: pages[cur].fontSize);
    ctrl.addListener(() {
      pages[cur].text = ctrl.text;
    });
  }

  void saveUndo() {
    undoStack.add(pages[cur].copy());
    redoStack.clear();
  }

  void applyStyle({bool? bold, bool? italic, bool? underline}) {
    var sel = ctrl.selection;
    if (!sel.isValid || sel.isCollapsed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Highlight text first, then tap B/I/U"), duration: Duration(seconds: 1)));
      return;
    }
    saveUndo();
    setState(() {
      pages[cur].formats.add(FormatRange(sel.start, sel.end, bold: bold?? false, italic: italic?? false, underline: underline?? false));
      ctrl.formats = pages[cur].formats;
    });
  }

  void changeFont(double d) {
    var sel = ctrl.selection;
    saveUndo();
    setState(() {
      if (sel.isValid &&!sel.isCollapsed) {
        pages[cur].formats.add(FormatRange(sel.start, sel.end, fontSize: pages[cur].fontSize + d));
      } else {
        pages[cur].fontSize = (pages[cur].fontSize + d).clamp(12, 40);
      }
      ctrl.baseSize = pages[cur].fontSize;
      ctrl.formats = pages[cur].formats;
    });
  }

  void undo() {
    if (undoStack.isEmpty) return;
    setState(() {
      redoStack.add(pages[cur].copy());
      pages[cur] = undoStack.removeLast();
      initCtrl();
    });
  }

  void redo() {
    if (redoStack.isEmpty) return;
    setState(() {
      undoStack.add(pages[cur].copy());
      pages[cur] = redoStack.removeLast();
      initCtrl();
    });
  }

  void nextPage() {
    setState(() {
      if (cur < pages.length - 1) {
        cur++;
      } else {
        pages.add(PageData());
        cur++;
      }
      initCtrl();
      elapsed = 0;
    });
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();
  }

  void startTimer() {
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!playing) return;
      setState(() {
        elapsed++;
        if (elapsed >= timerSec) {
          elapsed = 0;
          if (cur < pages.length - 1) {
            cur++;
            initCtrl();
            SystemSound.play(SystemSoundType.alert);
          } else {
            playing = false;
          }
        }
      });
    });
  }

  void showTimerDialog() {
    var tc = TextEditingController(text: timerSec.toString());
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text("Timer per page"),
      content: Row(children: [Expanded(child: TextField(controller: tc, keyboardType: TextInputType.number)), const Text(" sec")]),
      actions: [TextButton(onPressed: () { setState(() { timerSec = int.tryParse(tc.text)?? 5; }); Navigator.pop(context); }, child: const Text("OK"))],
    ));
  }

  void showSearch() {
    var sc = TextEditingController();
    List<int> results = [];
    showDialog(context: context, builder: (_) => StatefulBuilder(builder: (ctx, setSt) => AlertDialog(
      title: const Text("Search"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: sc, decoration: const InputDecoration(hintText: "Enter word", prefixIcon: Icon(Icons.search)), onChanged: (v) {
          setSt(() {
            results = [];
            for (int i = 0; i < pages.length; i++) {
              if (pages[i].text.toLowerCase().contains(v.toLowerCase()) && v.isNotEmpty) {
                results.add(i);
              }
            }
          });
        }),
        const SizedBox(height: 8),
        for (int i in results) ListTile(dense: true, title: Text("Found in Page ${i+1}"), onTap: () { Navigator.pop(context); setState(() { cur = i; initCtrl(); }); }),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))],
    )));
  }

  @override
  void dispose() {
    timer?.cancel();
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String date = "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}";
    return Scaffold(
      backgroundColor: bgColors[bgName],
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text("Flipleaf - $date", style: const TextStyle(fontSize: 14)),
        actions: [
          IconButton(icon: const Icon(Icons.search, size: 20), onPressed: showSearch),
          Text("${elapsed ~/ 60}:${(elapsed % 60).toString().padLeft(2, '0')}", style: const TextStyle(fontSize: 11)),
          IconButton(icon: Icon(playing? Icons.pause : Icons.play_arrow, size: 20), onPressed: () { setState(() { playing =!playing; }); startTimer(); }),
          PopupMenuButton<String>(icon: const Icon(Icons.palette, size: 20), onSelected: (v) => setState(() => bgName = v), itemBuilder: (_) => bgColors.keys.map((k) => PopupMenuItem(value: k, child: Text(k))).toList()),
          IconButton(icon: const Icon(Icons.timer, size: 20), onPressed: showTimerDialog),
        ],
      ),
      body: Column(children: [
        Container(color: Colors.black12, child: Row(children: [
          iconBtn("B", FontWeight.bold, () => applyStyle(bold: true)),
          iconBtn("I", FontWeight.normal, () => applyStyle(italic: true), italic: true),
          iconBtn("U", FontWeight.normal, () => applyStyle(underline: true), underline: true),
          IconButton(icon: const Icon(Icons.undo, size: 18), onPressed: undo),
          IconButton(icon: const Icon(Icons.redo, size: 18), onPressed: redo),
          const Spacer(),
          IconButton(icon: const Text("A-", style: TextStyle(fontSize: 12)), onPressed: () => changeFont(-1)),
          Text("${pages[cur].fontSize.toInt()}", style: const TextStyle(fontSize: 11)),
          IconButton(icon: const Text("A+", style: TextStyle(fontSize: 12)), onPressed: () => changeFont(1)),
          InkWell(onTap: nextPage, child: Padding(padding: const EdgeInsets.all(8), child: Text("+ ${cur+1}/${pages.length}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))),
        ])),
        Expanded(child: Container(margin: const EdgeInsets.all(8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: bgColors[bgName], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black26)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Page ${cur+1}", style: TextStyle(fontSize: 10, color: Colors.grey[600])),
            Expanded(child: TextField(controller: ctrl, maxLines: null, expands: true, style: TextStyle(fontSize: pages[cur].fontSize), decoration: const InputDecoration(border: InputBorder.none, hintText: "Type here. Select text then B/I/U"))),
            if (playing) LinearProgressIndicator(value: elapsed / timerSec, color: Colors.orange, minHeight: 3),
          ]),
        )),
      ]),
    );
  }

  Widget iconBtn(String label, FontWeight fw, VoidCallback tap, {bool italic = false, bool underline = false}) {
    return InkWell(onTap: tap, child: Container(width: 28, height: 28, margin: const EdgeInsets.all(2), alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.black45), borderRadius: BorderRadius.circular(4), color: Colors.white), child: Text(label, style: TextStyle(fontWeight: fw, fontStyle: italic? FontStyle.italic : FontStyle.normal, decoration: underline? TextDecoration.underline : null, fontSize: 12))));
  }
}

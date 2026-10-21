import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const FlipleafApp());

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
  int start, end;
  bool bold, italic, underline;
  double? fontSize;
  FormatRange(this.start, this.end, {this.bold = false, this.italic = false, this.underline = false, this.fontSize});
  Map<String, dynamic> toJson() => {"s": start, "e": end, "b": bold, "i": italic, "u": underline, "fs": fontSize};
  static FormatRange fromJson(Map<String, dynamic> j) {
    return FormatRange(
      j["s"] as int,
      j["e"] as int,
      bold: j["b"] == true,
      italic: j["i"] == true,
      underline: j["u"] == true,
      fontSize: (j["fs"] as num?)?.toDouble(),
    );
  }
}

class PageData {
  String text;
  List<FormatRange> formats;
  double fontSize;
  PageData({this.text = "", List<FormatRange>? formats, this.fontSize = 18}) : formats = formats?? [];
  Map<String, dynamic> toJson() => {"text": text, "formats": formats.map((e) => e.toJson()).toList(), "fs": fontSize};
  static PageData fromJson(Map<String, dynamic> j) {
    List<FormatRange> fmt = [];
    var raw = j["formats"];
    if (raw is List) {
      for (var e in raw) {
        try {
          fmt.add(FormatRange.fromJson(Map<String, dynamic>.from(e as Map)));
        } catch (_) {}
      }
    }
    String txt = "";
    if (j["text"] is String) txt = j["text"];
    double fs = 18;
    if (j["fs"] is num) fs = (j["fs"] as num).toDouble();
    return PageData(text: txt, formats: fmt, fontSize: fs);
  }
  PageData copy() {
    List<FormatRange> nl = [];
    for (var e in formats) {
      nl.add(FormatRange(e.start, e.end, bold: e.bold, italic: e.italic, underline: e.underline, fontSize: e.fontSize));
    }
    return PageData(text: text, formats: nl, fontSize: fontSize);
  }
}

class RichController extends TextEditingController {
  List<FormatRange> formats;
  double baseSize;
  RichController({String? text, required this.formats, required this.baseSize}) : super(text: text);
  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (text.isEmpty) return TextSpan(text: "", style: style);
    List<TextSpan> ch = [];
    for (int i = 0; i < text.length; i++) {
      bool b = false, it = false, u = false;
      double fs = baseSize;
      for (var f in formats) {
        if (i >= f.start && i < f.end) {
          if (f.bold) b = true;
          if (f.italic) it = true;
          if (f.underline) u = true;
          if (f.fontSize!= null) fs = f.fontSize!;
        }
      }
      ch.add(TextSpan(
          text: text[i],
          style: TextStyle(
              fontWeight: b? FontWeight.bold : FontWeight.normal,
              fontStyle: it? FontStyle.italic : FontStyle.normal,
              decoration: u? TextDecoration.underline : TextDecoration.none,
              fontSize: fs)));
    }
    return TextSpan(children: ch, style: style);
  }
}

class FlipleafEditor extends StatefulWidget {
  const FlipleafEditor({super.key});
  @override
  State<FlipleafEditor> createState() => _FlipleafEditorState();
}

class _FlipleafEditorState extends State<FlipleafEditor> with WidgetsBindingObserver {
  List<PageData> pages = [PageData()];
  int cur = 0;
  late RichController ctrl;
  List<PageData> undoStack = [], redoStack = [];
  Future<void> _saveQueue = Future<void>.value();
  Map<String, Color> bgColors = {
    "White": Colors.white,
    "Black": const Color(0xFFE0E0E0),
    "Blue": const Color(0xFFE3F2FD),
    "Green": const Color(0xFFE8F5E9),
    "Pink": const Color(0xFFFCE4EC),
    "Yellow": const Color(0xFFFFF9C4),
    "Brown": const Color(0xFFEFEBE9),
    "Purple": const Color(0xFFF3E5F5)
  };
  String bgName = "White";
  int timerSec = 5, elapsed = 0;
  bool playing = false;
  Timer? timer;
  String docTitle = "";
  String createdDate = "";
  final titleCtrl = TextEditingController();
  String currentDocId = "doc_1";
  List<Map<String, String>> allDocs = [];
  String _paginationDiagnostic = "Paste text to measure this page.";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ctrl = RichController(text: "", formats: [], baseSize: 18);
    createdDate = "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}";
    loadAll();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (cur >= 0 && cur < pages.length) {
        pages[cur].text = ctrl.text;
        pages[cur].formats = ctrl.formats;
      }
      docTitle = titleCtrl.text;
      // Await the write when Android backgrounds the app; do not rely on
      // dispose(), which is not guaranteed to finish asynchronous work.
      await saveDoc();
    }
  }

  Future<void> loadAll() async {
    final p = await SharedPreferences.getInstance();
    String? listStr = p.getString("flipleaf_all_list");
    if (listStr!= null) {
      try {
        var l = jsonDecode(listStr) as List;
        allDocs = l.map((e) => Map<String, String>.from(e as Map)).toList();
      } catch (_) {}
    }
    if (allDocs.isEmpty) {
      allDocs = [{"id": "doc_1", "title": "House Fellowship", "created": createdDate}];
      await p.setString("flipleaf_all_list", jsonEncode(allDocs));
    }
    currentDocId = p.getString("flipleaf_current_id")?? allDocs.first["id"]!;
    await loadDoc(currentDocId);
  }

  Future<void> loadDoc(String id) async {
    final p = await SharedPreferences.getInstance();
    String? saved = p.getString("flipleaf_$id");
    if (saved == null && id == "doc_1") saved = p.getString("flipleaf_doc_v3");
    if (saved!= null) {
      try {
        var j = jsonDecode(saved) as Map<String, dynamic>;
        List<PageData> loaded = [];
        var plist = j["pages"];
        if (plist is List) {
          for (var item in plist) {
            loaded.add(PageData.fromJson(Map<String, dynamic>.from(item as Map)));
          }
        }
        setState(() {
          if (j["title"] is String) docTitle = j["title"];
          if (j["created"] is String) createdDate = j["created"];
          titleCtrl.text = docTitle;
          if (loaded.isNotEmpty) pages = loaded;
          cur = 0;
          if (j["bg"] is String) bgName = j["bg"];
          final docIndex = allDocs.indexWhere((d) => d["id"] == id);
          if (docIndex >= 0 && bgColors.containsKey(allDocs[docIndex]["color"])) bgName = allDocs[docIndex]["color"]!;
          if (j["timer"] is int) timerSec = j["timer"];
        });
      } catch (_) {}
    } else {
      setState(() {
        pages = [PageData()];
        cur = 0;
        docTitle = "";
        titleCtrl.text = "";
        final docIndex = allDocs.indexWhere((d) => d["id"] == id);
        bgName = docIndex >= 0 && bgColors.containsKey(allDocs[docIndex]["color"])
            ? allDocs[docIndex]["color"]! : "White";
      });
    }
    initCtrl();
    currentDocId = id;
    await p.setString("flipleaf_current_id", id);
  }

  Future<void> saveDoc() async {
    final id = currentDocId;
    if (cur >= 0 && cur < pages.length) {
      // Snapshot the live controller explicitly; do not depend only on its listener.
      pages[cur].text = ctrl.text;
      pages[cur].formats = ctrl.formats;
    }
    docTitle = titleCtrl.text.isNotEmpty ? titleCtrl.text : docTitle;
    final title = docTitle;
    final created = createdDate;
    final background = bgName;
    final seconds = timerSec;
    final pageSnapshot = pages.map((page) => page.copy().toJson()).toList();
    final documentJson = jsonEncode({
      "title": title,
      "created": created,
      "bg": background,
      "timer": seconds,
      "pages": pageSnapshot,
    });
    final p = await SharedPreferences.getInstance();
    // Recover from an earlier failed write so the queue remains usable.
    _saveQueue = _saveQueue.catchError((Object _) {}).then((_) async {
      final saved = await p.setString("flipleaf_$id", documentJson);
      if (!saved) {
        throw StateError("Flipleaf document write failed for $id");
      }
      await p.setString("flipleaf_current_id", id);
      final idx = allDocs.indexWhere((entry) => entry["id"] == id);
      if (idx >= 0) {
        allDocs[idx]["title"] = title.isEmpty ? "Untitled" : title;
        allDocs[idx]["color"] = background;
        await p.setString("flipleaf_all_list", jsonEncode(allDocs));
      }
    });
    await _saveQueue;
  }

  bool _autoPaginating = false;

  TextSpan _pageSpan(PageData page, String value) {
    final children = <TextSpan>[];
    for (int i = 0; i < value.length; i++) {
      bool bold = false, italic = false, underline = false;
      double size = page.fontSize;
      for (final format in page.formats) {
        if (i >= format.start && i < format.end) {
          bold = bold || format.bold;
          italic = italic || format.italic;
          underline = underline || format.underline;
          if (format.fontSize != null) size = format.fontSize!;
        }
      }
      children.add(TextSpan(
        text: value[i],
        style: TextStyle(
          fontSize: size,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          decoration: underline ? TextDecoration.underline : TextDecoration.none,
        ),
      ));
    }
    return TextSpan(children: children);
  }

  double _measurePage(PageData page, String value, double width) {
    final painter = TextPainter(
      text: _pageSpan(page, value),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  int? _findPageBreak(PageData page, double width, double height) {
    final value = page.text;
    if (value.isEmpty || _measurePage(page, value, width) <= height) return null;
    int low = 1, high = value.length, fit = 1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (_measurePage(page, value.substring(0, mid), width) <= height) {
        fit = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    // Prefer a natural word/paragraph boundary, without discarding whitespace.
    int cut = fit;
    final boundary = value.lastIndexOf(RegExp(r'\s'), fit - 1);
    if (boundary > 0) cut = boundary + 1;
    if (cut > 0 && cut < value.length &&
        value.codeUnitAt(cut - 1) >= 0xD800 && value.codeUnitAt(cut - 1) <= 0xDBFF) {
      cut--;
    }
    return cut.clamp(1, value.length - 1);
  }

  List<FormatRange> _sliceFormats(List<FormatRange> formats, int start, int end, {int shift = 0}) {
    final result = <FormatRange>[];
    for (final format in formats) {
      final a = format.start > start ? format.start : start;
      final b = format.end < end ? format.end : end;
      if (a < b) {
        result.add(FormatRange(
          a - start + shift,
          b - start + shift,
          bold: format.bold,
          italic: format.italic,
          underline: format.underline,
          fontSize: format.fontSize,
        ));
      }
    }
    return result;
  }

  void _paginateOverflow(double width, double height) {
    if (_autoPaginating || !mounted || width <= 0 || height <= 0 ||
        cur < 0 || cur >= pages.length) return;

    _autoPaginating = true;
    try {
      // Measure against the visible writing box. The TextField decoration
      // below uses zero content padding, so only a small safety inset is needed.
      final usableWidth = (width - 4).clamp(40.0, width);
      final usableHeight = (height - 4).clamp(24.0, height);
      final originalSelection = ctrl.selection;
      int pageIndex = cur;
      bool changed = false;

      // Keep distributing until the overflow fits, creating pages as needed.
      // Do not stop merely because the next page existed already.
      while (pageIndex < pages.length && pageIndex < cur + 100) {
        final page = pages[pageIndex];
        final cut = _findPageBreak(page, usableWidth, usableHeight);
        if (cut == null) break;

        final original = page.text;
        if (cut <= 0 || cut >= original.length) break;
        final tail = original.substring(cut);
        final tailFormats = _sliceFormats(page.formats, cut, original.length);
        final kept = original.substring(0, cut).trimRight();
        page.text = kept;
        page.formats = _sliceFormats(page.formats, 0, kept.length);

        if (pageIndex + 1 >= pages.length) {
          pages.add(PageData(fontSize: page.fontSize));
        }
        final next = pages[pageIndex + 1];
        final existingText = next.text;
        final existingFormats = next.formats;
        final leadingTail = tail.trimLeft();
        final removedLeading = tail.length - leadingTail.length;
        final separator = existingText.isEmpty ? "" : "\n";
        next.text = leadingTail + separator + existingText;
        next.formats = <FormatRange>[
          ..._sliceFormats(tailFormats, removedLeading, tail.length),
          ..._sliceFormats(
            existingFormats, 0, existingText.length,
            shift: leadingTail.length + separator.length,
          ),
        ];
        changed = true;
        pageIndex++;
      }

      if (changed) {
        // Update the active controller only once, after all page segments have
        // been calculated. This avoids recursively reacting to every split.
        final activeText = pages[cur].text;
        final oldOffset = originalSelection.isValid
            ? originalSelection.baseOffset
            : activeText.length;
        final offset = oldOffset.clamp(0, activeText.length);
        ctrl.formats = pages[cur].formats;
        ctrl.value = TextEditingValue(
          text: activeText,
          selection: TextSelection.collapsed(offset: offset),
        );
        saveDoc();
        if (mounted) setState(() {});
      }
    } finally {
      _autoPaginating = false;
    }
  }

  void initCtrl() {
    ctrl.dispose();
    ctrl = RichController(text: pages[cur].text, formats: pages[cur].formats, baseSize: pages[cur].fontSize);
    ctrl.addListener(() {
      if (cur < 0 || cur >= pages.length) return;
      final page = pages[cur];
      if (page.text != ctrl.text) {
        // Capture the previous page state before each text edit so undo/redo
        // works for ordinary typing, deletion, and paste as well as formatting.
        if (!_autoPaginating) {
          undoStack.add(page.copy());
          if (undoStack.length > 50) undoStack.removeAt(0);
          redoStack.clear();
        }
        page.text = ctrl.text;
        saveDoc();
      }
    });
    setState(() {});
  }

  Future<void> createNewDoc() async {
    final p = await SharedPreferences.getInstance();
    String newId = "doc_${DateTime.now().millisecondsSinceEpoch}";
    String date = "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}";
    allDocs.add({"id": newId, "title": "New Document", "created": date});
    await p.setString("flipleaf_all_list", jsonEncode(allDocs));
    await loadDoc(newId);
  }

  Future<void> deleteDoc(String id) async {
    if (allDocs.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Keep at least 1 doc")));
      return;
    }
    final p = await SharedPreferences.getInstance();
    await p.remove("flipleaf_$id");
    allDocs.removeWhere((e) => e["id"] == id);
    await p.setString("flipleaf_all_list", jsonEncode(allDocs));
    if (currentDocId == id) {
      await loadDoc(allDocs.first["id"]!);
    } else {
      setState(() {});
    }
  }


  Future<void> deleteCurrentPage() async {
    if (pages.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("A document must keep at least one page.")));
      return;
    }
    final pageNumber = cur + 1;
    final hasText = pages[cur].text.trim().isNotEmpty;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Delete page $pageNumber?"),
        content: Text(hasText
          ? "This page contains text. Deleting it will permanently remove its content from this document."
          : "This page is blank. Do you want to delete it?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      pages.removeAt(cur);
      if (cur >= pages.length) cur = pages.length - 1;
      initCtrl();
    });
    await saveDoc();
  }

  Future<void> shareDocument(String id) async {
    final prefs = await SharedPreferences.getInstance();
    String title = "Untitled";
    List<PageData> sharePages = [];
    if (id == currentDocId) {
      title = docTitle.trim().isEmpty ? "Untitled" : docTitle.trim();
      sharePages = pages.map((page) => page.copy()).toList();
    } else {
      final saved = prefs.getString("flipleaf_$id");
      if (saved != null) {
        try {
          final data = jsonDecode(saved) as Map<String, dynamic>;
          if (data["title"] is String && (data["title"] as String).trim().isNotEmpty) {
            title = (data["title"] as String).trim();
          }
          if (data["pages"] is List) {
            sharePages = (data["pages"] as List)
                .map((e) => PageData.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList();
          }
        } catch (_) {}
      }
    }

    // Share clean document text: use real line breaks and omit editor-only
    // page labels so the recipient sees the title and original content only.
    final content = sharePages
        .map((page) => page.text.trim())
        .where((pageText) => pageText.isNotEmpty)
        .join('\n\n');
    final sharedText = content.isEmpty ? title : '$title\n\n$content';
    await Share.share(sharedText, subject: title);
  }

  Future<void> chooseDocumentColor(String id) async {
    final current = allDocs.firstWhere((d) => d["id"] == id, orElse: () => <String, String>{});
    if (current.isEmpty) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("Document colour"),
        children: bgColors.keys.map((name) => SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, name),
          child: Row(children: [
            Container(width: 24, height: 24, decoration: BoxDecoration(
              color: bgColors[name], border: Border.all(color: Colors.black26),
              borderRadius: BorderRadius.circular(5))),
            const SizedBox(width: 12),
            Text(name),
            const Spacer(),
            if (current["color"] == name || (current["color"] == null && id == currentDocId && bgName == name))
              const Icon(Icons.check, size: 18),
          ]),
        )).toList(),
      ),
    );
    if (selected == null) return;
    current["color"] = selected;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("flipleaf_all_list", jsonEncode(allDocs));
    if (id == currentDocId) {
      setState(() => bgName = selected);
      await saveDoc();
    } else {
      final saved = prefs.getString("flipleaf_$id");
      if (saved != null) {
        try {
          final data = jsonDecode(saved) as Map<String, dynamic>;
          data["bg"] = selected;
          await prefs.setString("flipleaf_$id", jsonEncode(data));
        } catch (_) {}
      }
    }
    if (mounted) setState(() {});
  }

  void showDocumentActions(Map<String, String> document) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(child: Wrap(children: [
        ListTile(leading: const Icon(Icons.share), title: const Text("Share full document"),
          onTap: () async {
            Navigator.pop(ctx);
            await shareDocument(document["id"]!);
          }),
        ListTile(leading: const Icon(Icons.palette_outlined), title: const Text("Document colour"),
          onTap: () {
            Navigator.pop(ctx);
            chooseDocumentColor(document["id"]!);
          }),
      ])),
    );
  }

  Future<void> showPresentation() async {
    final sections = <String>[];
    final pointPattern = RegExp(r'^\s*(?:[-*•▪]|\d+[.)]|[A-Za-z][.)])\s+');
    for (final page in pages) {
      final source = page.text.replaceAll('\r\n', '\n').trim();
      if (source.isEmpty) continue;
      for (final paragraph in source.split(RegExp(r'\n\s*\n+'))) {
        final trimmed = paragraph.trim();
        if (trimmed.isEmpty) continue;
        final lines = trimmed.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
        if (lines.length > 1 && lines.every((line) => pointPattern.hasMatch(line))) {
          sections.addAll(lines);
        } else {
          sections.add(trimmed);
        }
      }
    }
    if (sections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Add some text before starting presentation mode.")));
      return;
    }
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Presentation style"),
        content: const Text("Choose how each paragraph or point should appear."),
        actions: [
          TextButton.icon(onPressed: () => Navigator.pop(ctx, "instant"), icon: const Icon(Icons.slideshow), label: const Text("Instant reveal")),
          FilledButton.icon(onPressed: () => Navigator.pop(ctx, "typing"), icon: const Icon(Icons.keyboard_alt_outlined), label: const Text("Typewriter effect")),
        ],
      ),
    );
    if (mode == null || !mounted) return;
    int index = 0;
    String visibleText = mode == "instant" ? sections[0] : "";
    int animationToken = 0;
    bool typing = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SafeArea(child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Icon(Icons.slideshow, size: 26),
                const SizedBox(width: 8),
                Expanded(child: Text(docTitle.trim().isEmpty ? "Presentation" : docTitle,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis)),
                IconButton(onPressed: () { animationToken++; Navigator.pop(ctx); }, icon: const Icon(Icons.close), tooltip: "Close presentation"),
              ]),
              const SizedBox(height: 8),
              Text("Slide \${index + 1} of \${sections.length}", style: const TextStyle(color: Colors.grey)),
              const Divider(),
              Flexible(child: SingleChildScrollView(child: Align(alignment: Alignment.centerLeft, child: Text(
                visibleText, key: ValueKey(index), style: const TextStyle(fontSize: 22, height: 1.5),
              )))),
              const SizedBox(height: 16),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: index <= 0 ? null : () async {
                      final previousIndex = index - 1;
                      if (mode == "instant") {
                        animationToken++;
                        setDialogState(() {
                          index = previousIndex;
                          visibleText = sections[previousIndex];
                          typing = false;
                        });
                      } else {
                        final token = ++animationToken;
                        setDialogState(() {
                          index = previousIndex;
                          visibleText = "";
                          typing = true;
                        });
                        final target = sections[previousIndex];
                        for (int count = 1; count <= target.length; count++) {
                          await Future.delayed(const Duration(milliseconds: 12));
                          if (!ctx.mounted || token != animationToken) return;
                          setDialogState(() { visibleText = target.substring(0, count); });
                        }
                        if (ctx.mounted && token == animationToken) {
                          setDialogState(() => typing = false);
                        }
                      }
                    },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text("Previous"),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: typing || index >= sections.length - 1 ? null : () async {
                        final nextIndex = index + 1;
                        if (mode == "instant") {
                          setDialogState(() { index = nextIndex; visibleText = sections[index]; });
                        } else {
                          final token = ++animationToken;
                          setDialogState(() { index = nextIndex; visibleText = ""; typing = true; });
                          final target = sections[nextIndex];
                          for (int count = 1; count <= target.length; count++) {
                            await Future.delayed(const Duration(milliseconds: 12));
                            if (!ctx.mounted || token != animationToken) return;
                            setDialogState(() { visibleText = target.substring(0, count); });
                          }
                          if (ctx.mounted && token == animationToken) setDialogState(() => typing = false);
                        }
                      },
                      icon: Icon(index < sections.length - 1 ? Icons.arrow_forward : Icons.check),
                      label: Text(typing ? "Typing…" : (index < sections.length - 1 ? "Next slide" : "End")),
                    ),
                  ),
                ],
              ),
              TextButton(onPressed: () { animationToken++; Navigator.pop(ctx); }, child: const Text("Exit presentation")),
            ]),
          )),
        ),
      ),
    );
  }

  void saveUndo() {
    undoStack.add(pages[cur].copy());
    redoStack.clear();
    if (undoStack.length > 50) undoStack.removeAt(0);
  }

  bool isAllStyled(int s, int e, bool Function(FormatRange) check) {
    for (int i = s; i < e; i++) {
      bool has = false;
      for (var f in pages[cur].formats) {
        if (i >= f.start && i < f.end && check(f)) has = true;
      }
      if (!has) return false;
    }
    return true;
  }

  void toggleStyle({bool? bold, bool? italic, bool? underline}) {
    var sel = ctrl.selection;
    if (!sel.isValid || sel.isCollapsed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Highlight text first"), duration: Duration(seconds: 1)));
      return;
    }
    saveUndo();
    int s = sel.start, e = sel.end;
    bool allBold = false, allItalic = false, allUnderline = false;
    if (bold == true) allBold = isAllStyled(s, e, (f) => f.bold);
    if (italic == true) allItalic = isAllStyled(s, e, (f) => f.italic);
    if (underline == true) allUnderline = isAllStyled(s, e, (f) => f.underline);
    setState(() {
      pages[cur].formats.removeWhere((f) {
        bool overlap =!(f.end <= s || f.start >= e);
        if (!overlap) return false;
        if (bold == true && f.bold) return true;
        if (italic == true && f.italic) return true;
        if (underline == true && f.underline) return true;
        return false;
      });
      if (bold == true &&!allBold) pages[cur].formats.add(FormatRange(s, e, bold: true));
      if (italic == true &&!allItalic) pages[cur].formats.add(FormatRange(s, e, italic: true));
      if (underline == true &&!allUnderline) pages[cur].formats.add(FormatRange(s, e, underline: true));
      ctrl.formats = pages[cur].formats;
      saveDoc();
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
      saveDoc();
    });
  }

  void undo() {
    if (undoStack.isEmpty) return;
    setState(() {
      redoStack.add(pages[cur].copy());
      pages[cur] = undoStack.removeLast();
      initCtrl();
      saveDoc();
    });
  }

  void redo() {
    if (redoStack.isEmpty) return;
    setState(() {
      undoStack.add(pages[cur].copy());
      pages[cur] = redoStack.removeLast();
      initCtrl();
      saveDoc();
    });
  }

  void flipPrev() {
    if (cur > 0) {
      setState(() {
        cur--;
        initCtrl();
        elapsed = 0;
      });
      HapticFeedback.lightImpact();
    }
  }

  void flipNext() {
    setState(() {
      if (cur < pages.length - 1) {
        cur++;
      } else {
        pages.add(PageData());
        cur = pages.length - 1;
      }
      initCtrl();
      elapsed = 0;
    });
    HapticFeedback.mediumImpact();
    saveDoc();
  }

  void addNewPage() {
    setState(() {
      pages.insert(cur + 1, PageData());
      cur++;
      initCtrl();
      elapsed = 0;
    });
    HapticFeedback.heavyImpact();
    saveDoc();
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
            HapticFeedback.heavyImpact();
            SystemSound.play(SystemSoundType.alert);
          } else {
            playing = false;
            timer?.cancel();
          }
        }
      });
    });
  }

  void showTimerDialog() {
    var tc = TextEditingController(text: timerSec.toString());
    showDialog(context: context, builder: (_) => AlertDialog(title: const Text("Timer per page (sec)"), content: TextField(controller: tc, keyboardType: TextInputType.number), actions: [TextButton(onPressed: () { setState(() => timerSec = int.tryParse(tc.text)?? 5); saveDoc(); Navigator.pop(context); }, child: const Text("OK"))]));
  }

  void showSearch() {
    var sc = TextEditingController();
    List<int> results = [];
    showDialog(
        context: context,
        builder: (_) => StatefulBuilder(
            builder: (ctx, setSt) => AlertDialog(
                    title: const Text("Search"),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: sc,
                          decoration: const InputDecoration(hintText: "Enter word", prefixIcon: Icon(Icons.search)),
                          onChanged: (v) {
                            setSt(() {
                              results = [];
                              for (int i = 0; i < pages.length; i++) {
                                if (pages[i].text.toLowerCase().contains(v.toLowerCase()) && v.isNotEmpty) results.add(i);
                              }
                            });
                          }),
                      const SizedBox(height: 8),
                      for (int i in results)
                        ListTile(
                            dense: true,
                            title: Text("Found in Page ${i + 1}"),
                            onTap: () {
                              Navigator.pop(context);
                              setState(() {
                                cur = i;
                                initCtrl();
                              });
                            })
                    ]),
                    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))])));
  }

  Widget iconBtn(String label, FontWeight fw, VoidCallback tap, {bool italic = false, bool underline = false}) {
    return InkWell(
        onTap: tap,
        child: Container(
            width: 38,
            height: 38,
            margin: const EdgeInsets.all(3),
            alignment: Alignment.center,
            decoration: BoxDecoration(border: Border.all(color: Colors.black54, width: 1.2), borderRadius: BorderRadius.circular(6), color: Colors.white),
            child: Text(label, style: TextStyle(fontWeight: fw, fontStyle: italic? FontStyle.italic : FontStyle.normal, decoration: underline? TextDecoration.underline : null, fontSize: 15))));
  }

  void handleSwipe(DragEndDetails details) {
    if (!ctrl.selection.isCollapsed) return;
    double v = details.primaryVelocity?? 0;
    if (v < -250) flipNext();
    if (v > 250) flipPrev();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (cur >= 0 && cur < pages.length) {
      pages[cur].text = ctrl.text;
      pages[cur].formats = ctrl.formats;
    }
    saveDoc();
    ctrl.dispose();
    titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Keep the page editor's layout height stable when the keyboard opens.
      // The keyboard may cover part of the page, but must not redefine page capacity.
      resizeToAvoidBottomInset: false,
      backgroundColor: bgColors[bgName],
      drawer: Drawer(
          child: ListView(children: [
        DrawerHeader(
            decoration: const BoxDecoration(color: Colors.black),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Flipleaf", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text("${allDocs.length} Documents", style: const TextStyle(color: Colors.white70)),
              const Spacer(),
              ElevatedButton.icon(icon: const Icon(Icons.create_new_folder), label: const Text("New Document"), onPressed: () { Navigator.pop(context); createNewDoc(); })
            ])),
        const Padding(padding: EdgeInsets.all(8), child: Text("FOLDERS / DOCUMENTS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
       ...allDocs.map((d) => ListTile(
            leading: const Icon(Icons.description),
            title: Text(d["title"]!.isEmpty? "Untitled" : d["title"]!, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text("Created: ${d["created"]}"),
            selected: d["id"] == currentDocId,
            trailing: IconButton(icon: const Icon(Icons.delete, size: 18), onPressed: () => deleteDoc(d["id"]!)),
            onLongPress: () => showDocumentActions(d),
            onTap: () {
              Navigator.pop(context);
              if (d["id"]!= currentDocId) loadDoc(d["id"]!);
            })),
      ])),
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text("Flipleaf", style: TextStyle(fontSize: 15)), actions: [
        IconButton(icon: const Icon(Icons.search, size: 22), onPressed: showSearch),
        Text("${elapsed ~/ 60}:${(elapsed % 60).toString().padLeft(2, '0')}", style: const TextStyle(fontSize: 12)),
        IconButton(icon: Icon(playing? Icons.pause : Icons.play_arrow, size: 24), onPressed: () { setState(() => playing =!playing); startTimer(); }),
        PopupMenuButton<String>(icon: const Icon(Icons.palette, size: 22), onSelected: (v) { setState(() => bgName = v); saveDoc(); }, itemBuilder: (_) => bgColors.keys.map((k) => PopupMenuItem(value: k, child: Text(k))).toList()),
        IconButton(icon: const Icon(Icons.timer, size: 22), onPressed: showTimerDialog),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (v) {
            if (v == "present") showPresentation();
            if (v == "share") shareDocument(currentDocId);
          },
          itemBuilder: (_) => const [
            PopupMenuItem<String>(
              value: "present",
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.slideshow),
                title: Text("Presentation mode"),
              ),
            ),
            PopupMenuItem<String>(
              value: "share",
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.share),
                title: Text("Share full document"),
              ),
            ),
          ],
        ),
      ]),
      body: Column(children: [
        Container(color: const Color(0xFFD9D9B8), padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4), child: Row(children: [iconBtn("B", FontWeight.bold, () => toggleStyle(bold: true)), iconBtn("I", FontWeight.normal, () => toggleStyle(italic: true), italic: true), iconBtn("U", FontWeight.normal, () => toggleStyle(underline: true), underline: true), const SizedBox(width: 6), IconButton(icon: const Icon(Icons.undo, size: 22), onPressed: undo), IconButton(icon: const Icon(Icons.redo, size: 22), onPressed: redo), const Spacer(), IconButton(icon: const Text("A-", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), onPressed: () => changeFont(-1)), Text("${pages[cur].fontSize.toInt()}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), IconButton(icon: const Text("A+", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), onPressed: () => changeFont(1)),])),
        Container(color: Colors.black12, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), child: Row(children: [ElevatedButton.icon(icon: const Icon(Icons.chevron_left, size: 20), label: const Text("Prev"), onPressed: cur > 0? flipPrev : null, style: ElevatedButton.styleFrom(minimumSize: const Size(70, 36))), const SizedBox(width: 8), Text("${cur + 1} / ${pages.length}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), const SizedBox(width: 8), ElevatedButton.icon(icon: const Icon(Icons.chevron_right, size: 20), label: const Text("Next"), onPressed: flipNext, style: ElevatedButton.styleFrom(minimumSize: const Size(70, 36))), const Spacer(), ElevatedButton.icon(icon: const Icon(Icons.add, size: 20), label: const Text("New Page"), onPressed: addNewPage, style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, minimumSize: const Size(90, 36))),])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: TextField(controller: titleCtrl, onChanged: (v) { docTitle = v; saveDoc(); }, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold), decoration: const InputDecoration(hintText: "Document Title", border: InputBorder.none, isDense: true, prefixIcon: Icon(Icons.title, size: 20)))),
        Expanded(
            child: GestureDetector(
          onHorizontalDragEnd: handleSwipe,
          child: Stack(children: [
            Container(
                margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: bgColors[bgName], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black26)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onLongPress: deleteCurrentPage,
                      child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Page ${cur + 1}  (hold to delete)", style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                        Text("Created: $createdDate", style: TextStyle(fontSize: 10, color: Colors.grey[600], fontStyle: FontStyle.italic)),
                      ],
                    )),
                    const Divider(height: 10),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => TextField(
                          controller: ctrl,
                          maxLines: null,
                          expands: true,
                          style: TextStyle(fontSize: pages[cur].fontSize),
                          onChanged: (_) {
                            // Wait until Flutter has laid out the editor, then
                            // paginate against its real writing-area dimensions.
                            // Keep the controller text and page model in sync
                            // before measuring, especially for large pasted text.
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted || cur < 0 || cur >= pages.length) return;
                              final liveText = ctrl.text;
                              if (pages[cur].text != liveText) {
                                pages[cur].text = liveText;
                              }
                              // The Scaffold keeps the page area at a stable
                              // height while the keyboard is open, so measure
                              // against these unchanged editor constraints.
                              _paginateOverflow(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              );
                            });
                          },
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            hintText: "Type here... select text then tap B/I/U",
                          ),
                        ),
                      ),
                    ),
                    if (playing)
                      LinearProgressIndicator(
                        value: timerSec > 0 ? (elapsed / timerSec).clamp(0.0, 1.0) : 0.0,
                        color: Colors.orange,
                        minHeight: 3,
                      ),
                  ],
                ),
            ),
          ]),
        ),
      ),
    ]),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const FlipleafApp());

class FlipleafApp extends StatelessWidget {
  const FlipleafApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(debugShowCheckedModeBanner: false, home: FlipleafEditor());
  }
}

class FormatRange {
  int start, end;
  bool bold, italic, underline;
  double? fontSize;
  FormatRange(this.start, this.end, {this.bold=false, this.italic=false, this.underline=false, this.fontSize});
  Map<String,dynamic> toJson() => {"s":start,"e":end,"b":bold,"i":italic,"u":underline,"fs":fontSize};
  static FormatRange fromJson(Map<String,dynamic> j) {
    return FormatRange(j["s"] as int, j["e"] as int, bold:j["b"]==true, italic:j["i"]==true, underline:j["u"]==true, fontSize:(j["fs"] as num?)?.toDouble());
  }
}

class PageData {
  String text;
  List<FormatRange> formats;
  double fontSize;
  PageData({this.text="", List<FormatRange>? formats, this.fontSize=18}) : formats = formats??[];
  Map<String,dynamic> toJson() => {"text":text, "formats":formats.map((e)=>e.toJson()).toList(), "fs":fontSize};
  static PageData fromJson(Map<String,dynamic> j) {
    List<FormatRange> fmt=[];
    var raw=j["formats"];
    if(raw is List){
      for(var e in raw){
        try{ fmt.add(FormatRange.fromJson(Map<String,dynamic>.from(e as Map))); }catch(_){}
      }
    }
    String txt="";
    if(j["text"] is String) txt=j["text"];
    double fs=18;
    if(j["fs"] is num) fs=(j["fs"] as num).toDouble();
    return PageData(text:txt, formats:fmt, fontSize:fs);
  }
  PageData copy(){
    List<FormatRange> nl=[];
    for(var e in formats){ nl.add(FormatRange(e.start,e.end,bold:e.bold,italic:e.italic,underline:e.underline,fontSize:e.fontSize)); }
    return PageData(text:text, formats:nl, fontSize:fontSize);
  }
}

class RichController extends TextEditingController {
  List<FormatRange> formats;
  double baseSize;
  RichController({String? text, required this.formats, required this.baseSize}) : super(text:text);
  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}){
    if(text.isEmpty){ return TextSpan(text:"", style:style); }
    List<TextSpan> ch=[];
    for(int i=0;i<text.length;i++){
      bool b=false,it=false,u=false; double fs=baseSize;
      for(var f in formats){ if(i>=f.start && i<f.end){ if(f.bold) b=true; if(f.italic) it=true; if(f.underline) u=true; if(f.fontSize!=null) fs=f.fontSize!; } }
      ch.add(TextSpan(text:text[i], style:TextStyle(fontWeight:b?FontWeight.bold:FontWeight.normal, fontStyle:it?FontStyle.italic:FontStyle.normal, decoration:u?TextDecoration.underline:TextDecoration.none, fontSize:fs)));
    }
    return TextSpan(children:ch, style:style);
  }
}

class FlipleafEditor extends StatefulWidget {
  const FlipleafEditor({super.key});
  @override State<FlipleafEditor> createState()=>_FlipleafEditorState();
}

class _FlipleafEditorState extends State<FlipleafEditor> {
  List<PageData> pages=[PageData()];
  int cur=0;
  late RichController ctrl;
  List<PageData> undoStack=[], redoStack=[];
  Map<String,Color> bgColors={
    "White":Colors.white, "Black":const Color(0xFFE0E0E0),
    "Blue":const Color(0xFFE3F2FD), "Green":const Color(0xFFE8F5E9),
    "Pink":const Color(0xFFFCE4EC), "Yellow":const Color(0xFFFFF9C4),
    "Brown":const Color(0xFFEFEBE9), "Purple":const Color(0xFFF3E5F5),
  };
  String bgName="White";
  int timerSec=5, elapsed=0;
  bool playing=false;
  Timer? timer;
  String docTitle="";
  String createdDate="";
  final titleCtrl=TextEditingController();

  @override void initState(){
    super.initState();
    ctrl=RichController(text:"", formats:[], baseSize:18);
    createdDate="${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}";
    loadDoc();
  }

  Future<void> loadDoc() async {
    final p=await SharedPreferences.getInstance();
    String? saved=p.getString("flipleaf_doc_v3");
    if(saved!=null){
      try{
        var j=jsonDecode(saved) as Map<String,dynamic>;
        List<PageData> loaded=[];
        var plist=j["pages"];
        if(plist is List){
          for(var item in plist){
            loaded.add(PageData.fromJson(Map<String,dynamic>.from(item as Map)));
          }
        }
        setState((){
          if(j["title"] is String) docTitle=j["title"];
          if(j["created"] is String) createdDate=j["created"];
          titleCtrl.text=docTitle;
          if(loaded.isNotEmpty) pages=loaded;
          if(j["bg"] is String) bgName=j["bg"];
          if(j["timer"] is int) timerSec=j["timer"];
        });
      }catch(e){}
    }
    initCtrl();
  }

  Future<void> saveDoc() async {
    final p=await SharedPreferences.getInstance();
    var j={"title":docTitle, "created":createdDate, "bg":bgName, "timer":timerSec, "pages":pages.map((e)=>e.toJson()).toList()};
    await p.setString("flipleaf_doc_v3", jsonEncode(j));
  }

  void initCtrl(){
    ctrl.dispose();
    ctrl=RichController(text:pages[cur].text, formats:pages[cur].formats, baseSize:pages[cur].fontSize);
    ctrl.addListener((){ pages[cur].text=ctrl.text; saveDoc(); });
    setState((){});
  }

  void saveUndo(){ undoStack.add(pages[cur].copy()); redoStack.clear(); if(undoStack.length>50) undoStack.removeAt(0); }
  bool _isAllStyled(int s,int e,bool Function(FormatRange) check){
    for(int i=s;i<e;i++){ bool has=false; for(var f in pages[cur].formats){ if(i>=f.start && i<f.end && check(f)) has=true; } if(!has) return false; } return true;
  }
  void toggleStyle({bool? bold,bool? italic,bool? underline}){
    var sel=ctrl.selection;
    if(!sel.isValid || sel.isCollapsed){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text("Highlight text first"), duration:Duration(seconds:1))); return; }
    saveUndo(); int s=sel.start, e=sel.end;
    bool allBold=false, allItalic=false, allUnderline=false;
    if(bold==true) allBold=_isAllStyled(s,e,(f)=>f.bold);
    if(italic==true) allItalic=_isAllStyled(s,e,(f)=>f.italic);
    if(underline==true) allUnderline=_isAllStyled(s,e,(f)=>f.underline);
    setState((){
      pages[cur].formats.removeWhere((f){ bool overlap=!(f.end<=s || f.start>=e); if(!overlap) return false; if(bold==true && f.bold) return true; if(italic==true && f.italic) return true; if(underline==true && f.underline) return true; return false; });
      if(bold==true &&!allBold) pages[cur].formats.add(FormatRange(s,e,bold:true));
      if(italic==true &&!allItalic) pages[cur].formats.add(FormatRange(s,e,italic:true));
      if(underline==true &&!allUnderline) pages[cur].formats.add(FormatRange(s,e,underline:true));
      ctrl.formats=pages[cur].formats; saveDoc();
    });
  }
  void changeFont(double d){
    var sel=ctrl.selection; saveUndo();
    setState((){
      if(sel.isValid &&!sel.isCollapsed){ pages[cur].formats.add(FormatRange(sel.start, sel.end, fontSize:pages[cur].fontSize+d)); }
      else{ pages[cur].fontSize=(pages[cur].fontSize+d).clamp(12,40); }
      ctrl.baseSize=pages[cur].fontSize; ctrl.formats=pages[cur].formats; saveDoc();
    });
  }
  void undo(){ if(undoStack.isEmpty) return; setState((){ redoStack.add(pages[cur].copy()); pages[cur]=undoStack.removeLast(); initCtrl(); saveDoc(); }); }
  void redo(){ if(redoStack.isEmpty) return; setState((){ undoStack.add(pages[cur].copy()); pages[cur]=redoStack.removeLast(); initCtrl(); saveDoc(); }); }
  void flipPrev(){ if(cur>0){ setState((){ cur--; initCtrl(); elapsed=0; }); } }
  void flipNext(){ setState((){ if(cur<pages.length-1){ cur++; } else { pages.add(PageData()); cur++; } initCtrl(); elapsed=0; }); SystemSound.play(SystemSoundType.alert); HapticFeedback.heavyImpact(); saveDoc(); }
  void startTimer(){ timer?.cancel(); timer=Timer.periodic(const Duration(seconds:1),(t){ if(!playing) return; setState((){ elapsed++; if(elapsed>=timerSec){ elapsed=0; if(cur<pages.length-1){ cur++; initCtrl(); SystemSound.play(SystemSoundType.alert); HapticFeedback.heavyImpact(); } else { playing=false; } } }); }); }
  void showTimerDialog(){ var tc=TextEditingController(text:timerSec.toString()); showDialog(context:context, builder:(_)=>AlertDialog(title:const Text("Timer per page (seconds)"), content:TextField(controller:tc, keyboardType:TextInputType.number), actions:[TextButton(onPressed:(){ setState(()=>timerSec=int.tryParse(tc.text)??5); saveDoc(); Navigator.pop(context); }, child:const Text("OK"))])); }
  void showSearch(){ var sc=TextEditingController(); List<int> results=[]; showDialog(context:context, builder:(_)=>StatefulBuilder(builder:(ctx,setSt)=>AlertDialog(title:const Text("Search"), content:Column(mainAxisSize:MainAxisSize.min, children:[TextField(controller:sc, decoration:const InputDecoration(hintText:"Enter word", prefixIcon:Icon(Icons.search)), onChanged:(v){ setSt((){ results=[]; for(int i=0;i<pages.length;i++){ if(pages[i].text.toLowerCase().contains(v.toLowerCase()) && v.isNotEmpty) results.add(i); } }); }), const SizedBox(height:8), for(int i in results) ListTile(dense:true, title:Text("Found in Page ${i+1}"), onTap:(){ Navigator.pop(context); setState((){ cur=i; initCtrl(); }); })]), actions:[TextButton(onPressed:()=>Navigator.pop(context), child:const Text("Close"))]))); }
  @override void dispose(){ timer?.cancel(); ctrl.dispose(); titleCtrl.dispose(); super.dispose(); }

  Widget iconBtn(String label, FontWeight fw, VoidCallback tap, {bool italic=false, bool underline=false}){
    return InkWell(onTap:tap, child:Container(width:28,height:28,margin:const EdgeInsets.all(2), alignment:Alignment.center, decoration:BoxDecoration(border:Border.all(color:Colors.black45), borderRadius:BorderRadius.circular(4), color:Colors.white), child:Text(label, style:TextStyle(fontWeight:fw, fontStyle:italic?FontStyle.italic:FontStyle.normal, decoration:underline?TextDecoration.underline:null, fontSize:12))));
  }

  @override Widget build(BuildContext context){
    return Scaffold(
      backgroundColor:bgColors[bgName],
      appBar:AppBar(
        backgroundColor:Colors.black, foregroundColor:Colors.white,
        title:const Text("Flipleaf", style:TextStyle(fontSize:14)),
        actions:[
          IconButton(icon:const Icon(Icons.search, size:20), onPressed:showSearch),
          Text("${elapsed~/60}:${(elapsed%60).toString().padLeft(2,'0')}", style:const TextStyle(fontSize:11)),
          IconButton(icon:Icon(playing?Icons.pause:Icons.play_arrow, size:20), onPressed:(){ setState(()=>playing=!playing); startTimer(); }),
          PopupMenuButton<String>(icon:const Icon(Icons.palette, size:20), onSelected:(v){ setState(()=>bgName=v); saveDoc(); }, itemBuilder:(_)=>bgColors.keys.map((k)=>PopupMenuItem(value:k, child:Text(k))).toList()),
          IconButton(icon:const Icon(Icons.timer, size:20), onPressed:showTimerDialog),
        ],
      ),
      body:Column(children:[
        Container(color:Colors.black12, padding:const EdgeInsets.symmetric(horizontal:2, vertical:2),
          child:Row(children:[
            iconBtn("B", FontWeight.bold, ()=>toggleStyle(bold:true)),
            iconBtn("I", FontWeight.normal, ()=>toggleStyle(italic:true), italic:true),
            iconBtn("U", FontWeight.normal, ()=>toggleStyle(underline:true), underline:true),
            IconButton(icon:const Icon(Icons.undo, size:18), onPressed:undo),
            IconButton(icon:const Icon(Icons.redo, size:18), onPressed:redo),
            const Spacer(),
            IconButton(icon:const Text("A-", style:TextStyle(fontSize:12)), onPressed:()=>changeFont(-1)),
            Text("${pages[cur].fontSize.toInt()}", style:const TextStyle(fontSize:11)),
            IconButton(icon:const Text("A+", style:TextStyle(fontSize:12)), onPressed:()=>changeFont(1)),
            IconButton(icon:const Icon(Icons.chevron_left, size:20), onPressed:cur>0?flipPrev:null),
            Text("${cur+1}/${pages.length}", style:const TextStyle(fontSize:12, fontWeight:FontWeight.bold)),
            IconButton(icon:const Icon(Icons.chevron_right, size:20), onPressed:flipNext),
          ]),
        ),
        Padding(padding:const EdgeInsets.symmetric(horizontal:12, vertical:6), child:TextField(controller:titleCtrl, onChanged:(v){ docTitle=v; saveDoc(); }, style:const TextStyle(fontSize:16, fontWeight:FontWeight.bold), decoration:const InputDecoration(hintText:"Document Title", border:InputBorder.none, isDense:true, prefixIcon:Icon(Icons.title, size:18)))),
        Expanded(child:Container(margin:const EdgeInsets.fromLTRB(8,0,8,8), padding:const EdgeInsets.all(12), decoration:BoxDecoration(color:bgColors[bgName], borderRadius:BorderRadius.circular(8), border:Border.all(color:Colors.black26)),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
            Row(mainAxisAlignment:MainAxisAlignment.spaceBetween, children:[Text("Page ${cur+1}", style:TextStyle(fontSize:10, color:Colors.grey[600])), Text("Created: $createdDate", style:TextStyle(fontSize:10, color:Colors.grey[600], fontStyle:FontStyle.italic))]),
            const Divider(height:10),
            Expanded(child:TextField(controller:ctrl, maxLines:null, expands:true, style:TextStyle(fontSize:pages[cur].fontSize), decoration:const InputDecoration(border:InputBorder.none, hintText:"Type here... select text then tap B/I/U"))),
            if(playing) LinearProgressIndicator(value:elapsed/timerSec, color:Colors.orange, minHeight:3),
          ]),
        )),
      ]),
    );
  }
}

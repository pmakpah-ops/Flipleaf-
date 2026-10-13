import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main()=>runApp(MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData.dark(),home:Home()));

// --- DATA MODELS ---
class TextSeg{
  String text; bool bold; bool italic; bool underline;
  TextSeg(this.text,{this.bold=false,this.italic=false,this.underline=false});
  Map toJson()=>{'t':text,'b':bold,'i':italic,'u':underline};
  factory TextSeg.fromJson(Map j)=>TextSeg(j['t']??'',bold:j['b']??false,italic:j['i']??false,underline:j['u']??false);
}
class PageData{
  List<TextSeg> segs;
  PageData({List<TextSeg>? segs}):segs=segs??[TextSeg('')];
  String get plain=>segs.map((e)=>e.text).join();
  Map toJson()=>{'segs':segs.map((e)=>e.toJson()).toList()};
  factory PageData.fromJson(Map j){
    if(j['segs']!=null){return PageData(segs:(j['segs'] as List).map((e)=>TextSeg.fromJson(e)).toList());}
    // backward compat with old version
    return PageData(segs:[TextSeg(j['text']??'',bold:j['bold']??false,italic:j['italic']??false,underline:j['underline']??false)]);
  }
}
class Notebook{
  String id,title; List<PageData> pages; int bgIndex; int timerSec; DateTime createdAt;
  Notebook({required this.id,required this.title,required this.pages,this.bgIndex=0,this.timerSec=5,DateTime? createdAt}):createdAt=createdAt??DateTime.now();
  Map toJson()=>{'id':id,'title':title,'pages':pages.map((e)=>e.toJson()).toList(),'bgIndex':bgIndex,'timerSec':timerSec,'createdAt':createdAt.toIso8601String()};
  factory Notebook.fromJson(Map j)=>Notebook(id:j['id'],title:j['title'],pages:(j['pages'] as List).map((e)=>PageData.fromJson(e)).toList(),bgIndex:j['bgIndex']??0,timerSec:j['timerSec']??5,createdAt:j['createdAt']!=null?DateTime.parse(j['createdAt']):DateTime.now());
}

class Home extends StatefulWidget{const Home({super.key});@override State<Home>createState()=>_HomeS();}
class _HomeS extends State<Home>{
  List<Notebook> books=[]; String query='';
  final bgColors=[Colors.white,Colors.black,Color(0xFF0D1B3E),Color(0xFF0B3D2E),Color(0xFFFFE4EC),Color(0xFFD8B4FE),Color(0xFFFFEB3B),Color(0xFFFFD700),Color(0xFF8D6E63)];
  final bgNames=['White','Black','Blue','Green','Pink','Purple','Yellow','Gold','Brown'];
  @override void initState(){super.initState();_load();}
  Future _load()async{var p=await SharedPreferences.getInstance();var s=p.getString('flip_pad_v2');if(s!=null){setState(()=>books=(jsonDecode(s) as List).map((e)=>Notebook.fromJson(e)).toList());}else{var old=p.getString('flip_pad');if(old!=null){setState(()=>books=(jsonDecode(old) as List).map((e){var nb=Notebook.fromJson(e);return nb;}).toList());}}}
  Future _save()async{var p=await SharedPreferences.getInstance();await p.setString('flip_pad_v2', jsonEncode(books.map((e)=>e.toJson()).toList()));}
  void _newBook(){var nb=Notebook(id:DateTime.now().millisecondsSinceEpoch.toString(),title:'Untitled',pages:[PageData()],createdAt:DateTime.now());setState(()=>books.insert(0,nb));_save();Navigator.push(context, MaterialPageRoute(builder:(_)=>Editor(book:nb,onSave:_save,bgColors:bgColors,bgNames:bgNames))).then((_)=>_load());}
  String _fmtDate(DateTime d)=>"${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2,'0')}";
  @override Widget build(BuildContext c){
    var filtered=books.where((b)=>b.title.toLowerCase().contains(query.toLowerCase())||b.pages.any((pg)=>pg.plain.toLowerCase().contains(query.toLowerCase()))).toList();
    return Scaffold(backgroundColor:Colors.black,appBar:AppBar(backgroundColor:Colors.black,title:Text('FlipLeaf'),actions:[IconButton(icon:Icon(Icons.add),onPressed:_newBook)]),
    body:Column(children:[
      Padding(padding:EdgeInsets.all(12),child:TextField(decoration:InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Search file...',filled:true,fillColor:Colors.white10,border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide.none)),onChanged:(v)=>setState(()=>query=v))),
      Expanded(child:ListView.builder(itemCount:filtered.length,itemBuilder:(_,i){var b=filtered[i];return Card(color:Colors.white10,margin:EdgeInsets.symmetric(horizontal:12,vertical:6),child:ListTile(title:Text(b.title,style:TextStyle(fontWeight:FontWeight.bold)),subtitle:Text('${b.pages.length} pages • ${bgNames[b.bgIndex]} • ${b.timerSec}s • ${_fmtDate(b.createdAt)}',style:TextStyle(fontSize:11)),leading:Container(width:40,height:40,decoration:BoxDecoration(color:bgColors[b.bgIndex],borderRadius:BorderRadius.circular(8),border:Border.all(color:Colors.white24))),onTap:(){Navigator.push(context, MaterialPageRoute(builder:(_)=>Editor(book:b,onSave:_save,bgColors:bgColors,bgNames:bgNames))).then((_)=>_load());},trailing:IconButton(icon:Icon(Icons.delete_outline),onPressed:(){setState(()=>books.removeWhere((e)=>e.id==b.id));_save();})));}))
    ]));
  }
}

class Editor extends StatefulWidget{final Notebook book;final VoidCallback onSave;final List<Color> bgColors;final List<String> bgNames;const Editor({super.key,required this.book,required this.onSave,required this.bgColors,required this.bgNames});@override State<Editor>createState()=>_EditorS();}
class _EditorS extends State<Editor>{
  late PageController pc; int cur=0; bool presenting=false; Timer? pt;
  late TextEditingController tec; int selStart=0,selEnd=0;
  bool nextBold=false,nextItalic=false,nextUnderline=false;
  PageData get cp=>widget.book.pages[cur];
  String get _dateStr{var d=widget.book.createdAt;return "${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2,'0')}";}
  @override void initState(){super.initState();pc=PageController();tec=TextEditingController(text:cp.plain);tec.addListener(_onSelChanged);}
  void _onSelChanged(){selStart=tec.selection.start==-1?tec.text.length:tec.selection.start;selEnd=tec.selection.end==-1?tec.text.length:tec.selection.end;}
  @override void dispose(){pc.dispose();tec.dispose();pt?.cancel();super.dispose();}

  // rebuild segs from flat text change
  void _handleTextChange(String newText){
    String oldText = cp.plain;
    if(newText==oldText) return;
    // find diff
    int diffPos=0; while(diffPos<oldText.length && diffPos<newText.length && oldText[diffPos]==newText[diffPos])diffPos++;
    if(newText.length>oldText.length){
      // insertion
      String inserted=newText.substring(diffPos,diffPos+(newText.length-oldText.length));
      _insertAt(diffPos,inserted);
    }else{
      // deletion
      int delCount=oldText.length-newText.length;
      _deleteAt(diffPos,delCount);
    }
    widget.onSave(); setState((){});
  }
  void _insertAt(int pos,String ins){
    List<TextSeg> newSegs=[]; int curPos=0;
    for(var s in cp.segs){
      int nextPos=curPos+s.text.length;
      if(pos>=curPos && pos<=nextPos){
        int local=pos-curPos;
        String left=s.text.substring(0,local);
        String right=s.text.substring(local);
        if(left.isNotEmpty)newSegs.add(TextSeg(left,bold:s.bold,italic:s.italic,underline:s.underline));
        newSegs.add(TextSeg(ins,bold:nextBold,italic:nextItalic,underline:nextUnderline));
        if(right.isNotEmpty)newSegs.add(TextSeg(right,bold:s.bold,italic:s.italic,underline:s.underline));
        // add rest
        int idx=cp.segs.indexOf(s);
        for(int j=idx+1;j<cp.segs.length;j++)newSegs.add(cp.segs[j]);
        cp.segs=newSegs; return;
      }
      newSegs.add(s); curPos=nextPos;
    }
    if(newSegs.length==cp.segs.length){newSegs.add(TextSeg(ins,bold:nextBold,italic:nextItalic,underline:nextUnderline)); cp.segs=newSegs;}
  }
  void _deleteAt(int pos,int count){
    List<TextSeg> newSegs=[]; int curPos=0;
    for(var s in cp.segs){
      int nextPos=curPos+s.text.length;
      int sStart=curPos, sEnd=nextPos;
      int delStart=pos, delEnd=pos+count;
      if(sEnd<=delStart || sStart>=delEnd){
        newSegs.add(s);
      }else{
        int leftEnd=(delStart-clamp(sStart,delStart,sEnd)).clamp(0,s.text.length);
        // simpler: build remaining
        String txt=s.text; String remain="";
        int localDelStart=(delStart-sStart).clamp(0,txt.length);
        int localDelEnd=(delEnd-sStart).clamp(0,txt.length);
        remain=txt.substring(0,localDelStart)+txt.substring(localDelEnd);
        if(remain.isNotEmpty)newSegs.add(TextSeg(remain,bold:s.bold,italic:s.italic,underline:s.underline));
      }
      curPos=nextPos;
    }
    if(newSegs.isEmpty)newSegs=[TextSeg('')];
    cp.segs=newSegs;
  }
  int clamp(int v,int min,int max)=>v<min?min:(v>max?max:v);

  void _applyStyle(String type){
    if(selStart==selEnd){
      // toggle for next input
      setState((){
        if(type=='b')nextBold=!nextBold;
        if(type=='i')nextItalic=!nextItalic;
        if(type=='u')nextUnderline=!nextUnderline;
      });
      return;
    }
    // apply to selection range
    int start=selStart<selEnd?selStart:selEnd; int end=selStart<selEnd?selEnd:selStart;
    List<TextSeg> newSegs=[]; int curPos=0;
    for(var s in cp.segs){
      int nextPos=curPos+s.text.length;
      if(nextPos<=start || curPos>=end){
        newSegs.add(s);
      }else{
        int segStart=curPos, segEnd=nextPos;
        int overStart=start>segStart?start:segStart;
        int overEnd=end<segEnd?end:segEnd;
        int localOverStart=overStart-segStart;
        int localOverEnd=overEnd-segStart;
        if(localOverStart>0)newSegs.add(TextSeg(s.text.substring(0,localOverStart),bold:s.bold,italic:s.italic,underline:s.underline));
        bool b=s.bold,i=s.italic,u=s.underline;
        if(type=='b')b=!b; if(type=='i')i=!i; if(type=='u')u=!u;
        newSegs.add(TextSeg(s.text.substring(localOverStart,localOverEnd),bold:b,italic:i,underline:u));
        if(localOverEnd<s.text.length)newSegs.add(TextSeg(s.text.substring(localOverEnd),bold:s.bold,italic:s.italic,underline:s.underline));
      }
      curPos=nextPos;
    }
    setState(()=>cp.segs=newSegs);
    // rebuild controller to keep styles visible
    var flat=cp.plain; var sel=tec.selection;
    tec.text=flat; tec.selection=sel;
    widget.onSave();
  }

  List<TextSpan> _buildSpans(double fontSize,Color txtColor){
    return cp.segs.map((s)=>TextSpan(text:s.text,style:TextStyle(fontSize:fontSize,color:txtColor,fontWeight:s.bold?FontWeight.bold:FontWeight.normal,fontStyle:s.italic?FontStyle.italic:FontStyle.normal,decoration:s.underline?TextDecoration.underline:TextDecoration.none))).toList();
  }

  void _newPage(){setState(()=>widget.book.pages.insert(cur+1,PageData()));widget.onSave();pc.nextPage(duration:Duration(milliseconds:300),curve:Curves.easeInOut);}
  void _startPresent(){if(widget.book.pages.length<2)return;setState(()=>presenting=true);pt=Timer.periodic(Duration(seconds:widget.book.timerSec),(t){if(cur<widget.book.pages.length-1){pc.nextPage(duration:Duration(milliseconds:500),curve:Curves.easeInOut);}else{t.cancel();setState(()=>presenting=false);}});}
  void _stopPresent(){pt?.cancel();setState(()=>presenting=false);}
  void _showTimerDialog(){
    int mins=widget.book.timerSec~/60; int secs=widget.book.timerSec%60;
    TextEditingController mCtrl=TextEditingController(text:mins.toString());
    TextEditingController sCtrl=TextEditingController(text:secs.toString());
    showDialog(context:context,builder:(_)=>AlertDialog(title:Text('Timer per page'),content:Row(children:[
      Expanded(child:TextField(controller:mCtrl,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:'Minutes',border:OutlineInputBorder()))),
      SizedBox(width:10),
      Expanded(child:TextField(controller:sCtrl,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:'Seconds',border:OutlineInputBorder()))),
    ]),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:Text('Cancel')),TextButton(onPressed:(){
      int m=int.tryParse(mCtrl.text)??0; int s=int.tryParse(sCtrl.text)??5;
      int total=m*60+s; if(total<1)total=1;
      setState(()=>widget.book.timerSec=total); widget.onSave(); Navigator.pop(context);
    },child:Text('Save'))]));
  }

  @override Widget build(BuildContext c){
    var bg=widget.bgColors[widget.book.bgIndex]; var isLight=widget.book.bgIndex==0||widget.book.bgIndex==4||widget.book.bgIndex==5||widget.book.bgIndex==6||widget.book.bgIndex==7;
    var txtColor=isLight?Colors.black:Colors.white;
    // determine if selection has bold
    bool selBold=false,selItalic=false,selUnderline=false;
    if(selStart!=selEnd){int st=selStart<selEnd?selStart:selEnd;int en=selStart<selEnd?selEnd:selStart;int pos=0;for(var s in cp.segs){int n=pos+s.text.length;if(!(n<=st||pos>=en)){if(s.bold)selBold=true;if(s.italic)selItalic=true;if(s.underline)selUnderline=true;}pos=n;}}
    else{selBold=nextBold;selItalic=nextItalic;selUnderline=nextUnderline;}
    return Scaffold(backgroundColor:bg,appBar:AppBar(backgroundColor:Colors.black,leading:IconButton(icon:Icon(Icons.arrow_back),onPressed:(){widget.onSave();Navigator.pop(context);}),title:TextField(controller:TextEditingController(text:widget.book.title),style:TextStyle(color:Colors.white,fontWeight:FontWeight.bold),decoration:InputDecoration(border:InputBorder.none,hintText:'Title',hintStyle:TextStyle(color:Colors.white54)),onSubmitted:(v){setState(()=>widget.book.title=v.isEmpty?'Untitled':v);widget.onSave();}),actions:[
      IconButton(icon:Icon(presenting?Icons.pause:Icons.play_arrow),onPressed:presenting?_stopPresent:_startPresent),
      PopupMenuButton(icon:Icon(Icons.palette),itemBuilder:(_)=>List.generate(widget.bgNames.length,(i)=>PopupMenuItem(child:Text(widget.bgNames[i]),onTap:(){Future.delayed(Duration(milliseconds:100),(){setState(()=>widget.book.bgIndex=i);widget.onSave();});}))),
      IconButton(icon:Icon(Icons.timer),onPressed:_showTimerDialog),
    ]),
    body:Column(children:[
      Container(color:Colors.black87,padding:EdgeInsets.symmetric(horizontal:8,vertical:4),child:SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
        IconButton(icon:Text('B',style:TextStyle(fontWeight:FontWeight.bold,color:selBold?Colors.amber:Colors.white)),onPressed:()=>_applyStyle('b')),
        IconButton(icon:Text('I',style:TextStyle(fontStyle:FontStyle.italic,color:selItalic?Colors.amber:Colors.white)),onPressed:()=>_applyStyle('i')),
        IconButton(icon:Text('U',style:TextStyle(decoration:TextDecoration.underline,color:selUnderline?Colors.amber:Colors.white)),onPressed:()=>_applyStyle('u')),
        IconButton(icon:Icon(Icons.add),onPressed:_newPage),
        Text('${cur+1}/${widget.book.pages.length}',style:TextStyle(color:Colors.white70,fontSize:12)),
        SizedBox(width:10),
        Text(_dateStr,style:TextStyle(color:Colors.white38,fontSize:10))
      ]))),
      Expanded(child:PageView.builder(controller:pc,itemCount:widget.book.pages.length,onPageChanged:(i){setState((){cur=i;var flat=widget.book.pages[i].plain;tec.text=flat;});},itemBuilder:(_,i){
        var pg=widget.book.pages[i];
        bool isCurrent=i==cur;
        return Container(margin:EdgeInsets.all(14),padding:EdgeInsets.all(18),decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(16),boxShadow:[BoxShadow(color:Colors.black26,blurRadius:12)],border:Border.all(color:isLight?Colors.black12:Colors.white12)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text('Page ${i+1}',style:TextStyle(color:isLight?Colors.black54:Colors.white54,fontSize:11)),Text(_dateStr,style:TextStyle(color:isLight?Colors.black38:Colors.white38,fontSize:10))]),
          Divider(color:isLight?Colors.black12:Colors.white12),
          Expanded(child:isCurrent?Stack(children:[
            // Rich preview behind
            SingleChildScrollView(child:RichText(text:TextSpan(children:_buildSpans(18,txtColor.withOpacity(0.0))))),
            TextField(controller:tec,maxLines:null,expands:true,style:TextStyle(color:Colors.transparent,fontSize:18,height:1.4),cursorColor:txtColor,decoration:InputDecoration(border:InputBorder.none,hintText:'Start typing...',hintStyle:TextStyle(color:isLight?Colors.black26:Colors.white24)),onChanged:_handleTextChange),
            // visible styled text overlay that syncs scroll? we use separate RichText on top ignoring input
            Positioned.fill(child:IgnorePointer(child:SingleChildScrollView(child:RichText(text:TextSpan(children:_buildSpans(18,txtColor)))))),
          ]):SingleChildScrollView(child:RichText(text:TextSpan(children:pg.segs.map((s)=>TextSpan(text:s.text,style:TextStyle(color:txtColor,fontSize:18,height:1.4,fontWeight:s.bold?FontWeight.bold:FontWeight.normal,fontStyle:s.italic?FontStyle.italic:FontStyle.normal,decoration:s.underline?TextDecoration.underline:TextDecoration.none))).toList()))))
        ]));
      })),
      if(presenting)LinearProgressIndicator(value:1,backgroundColor:Colors.white10,color:Colors.amber,minHeight:3)
    ]));
  }
}

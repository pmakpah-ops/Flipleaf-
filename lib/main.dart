import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main()=>runApp(MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData.dark(),home:Home()));

class PageData{
  String text; bool bold,italic,underline; double fontSize;
  List<String> undoStack=[]; List<String> redoStack=[];
  PageData({this.text='',this.bold=false,this.italic=false,this.underline=false,this.fontSize=18});
  Map toJson()=>{'text':text,'bold':bold,'italic':italic,'underline':underline,'fontSize':fontSize};
  factory PageData.fromJson(Map j)=>PageData(text:j['text']??'',bold:j['bold']??false,italic:j['italic']??false,underline:j['underline']??false,fontSize:(j['fontSize']??18).toDouble());
}
class Notebook{
  String id,title; List<PageData> pages; int bgIndex; int timerSec;
  Notebook({required this.id,required this.title,required this.pages,this.bgIndex=0,this.timerSec=5});
  Map toJson()=>{'id':id,'title':title,'pages':pages.map((e)=>e.toJson()).toList(),'bgIndex':bgIndex,'timerSec':timerSec};
  factory Notebook.fromJson(Map j)=>Notebook(id:j['id'],title:j['title'],pages:(j['pages'] as List).map((e)=>PageData.fromJson(e)).toList(),bgIndex:j['bgIndex']??0,timerSec:j['timerSec']??5);
}

class Home extends StatefulWidget{const Home({super.key});@override State<Home>createState()=>_HomeS();}
class _HomeS extends State<Home>{
  List<Notebook> books=[]; String query='';
  final bgColors=[Colors.white,Colors.black,Colors.blue.shade900,Colors.green.shade900,Colors.pink.shade100,Colors.purple.shade300];
  final bgNames=['White','Black','Blue','Green','Pink','Purple'];
  @override void initState(){super.initState();_load();}
  Future _load()async{var p=await SharedPreferences.getInstance();var s=p.getString('flip_pad');if(s!=null){setState(()=>books=(jsonDecode(s) as List).map((e)=>Notebook.fromJson(e)).toList());}}
  Future _save()async{var p=await SharedPreferences.getInstance();await p.setString('flip_pad', jsonEncode(books.map((e)=>e.toJson()).toList()));}
  void _newBook(){var nb=Notebook(id:DateTime.now().millisecondsSinceEpoch.toString(),title:'Untitled',pages:[PageData()]);setState(()=>books.insert(0,nb));_save();Navigator.push(context, MaterialPageRoute(builder:(_)=>Editor(book:nb,onSave:_save))).then((_)=>_load());}
  @override Widget build(BuildContext c){
    var filtered=books.where((b)=>b.title.toLowerCase().contains(query.toLowerCase())||b.pages.any((pg)=>pg.text.toLowerCase().contains(query.toLowerCase()))).toList();
    return Scaffold(backgroundColor:Colors.black,appBar:AppBar(backgroundColor:Colors.black,title:Text('FlipLeaf'),actions:[IconButton(icon:Icon(Icons.add),onPressed:_newBook)]),
    body:Column(children:[
      Padding(padding:EdgeInsets.all(12),child:TextField(decoration:InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Search file...',filled:true,fillColor:Colors.white10,border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide.none)),onChanged:(v)=>setState(()=>query=v))),
      Expanded(child:ListView.builder(itemCount:filtered.length,itemBuilder:(_,i){var b=filtered[i];return Card(color:Colors.white10,margin:EdgeInsets.symmetric(horizontal:12,vertical:6),child:ListTile(title:Text(b.title,style:TextStyle(fontWeight:FontWeight.bold)),subtitle:Text('${b.pages.length} pages • ${bgNames[b.bgIndex]} • ${b.timerSec}s',style:TextStyle(fontSize:12)),leading:Container(width:40,height:40,decoration:BoxDecoration(color:bgColors[b.bgIndex],borderRadius:BorderRadius.circular(8),border:Border.all(color:Colors.white24))),onTap:(){Navigator.push(context, MaterialPageRoute(builder:(_)=>Editor(book:b,onSave:_save))).then((_)=>_load());},trailing:IconButton(icon:Icon(Icons.delete_outline),onPressed:(){setState(()=>books.removeWhere((e)=>e.id==b.id));_save();})));}))
    ]));
  }
}

class Editor extends StatefulWidget{final Notebook book;final VoidCallback onSave;const Editor({super.key,required this.book,required this.onSave});@override State<Editor>createState()=>_EditorS();}
class _EditorS extends State<Editor>{
  late PageController pc; int cur=0; bool presenting=false; Timer? pt; final bgColors=[Colors.white,Colors.black,Color(0xFF0D1B3E),Color(0xFF0B3D2E),Color(0xFFFFE4EC),Color(0xFFD8B4FE)]; final bgNames=['White','Black','Blue','Green','Pink','Purple'];
  late TextEditingController tec;
  @override void initState(){super.initState();pc=PageController();tec=TextEditingController(text:widget.book.pages.isNotEmpty?widget.book.pages[0].text:'');}
  @override void dispose(){pc.dispose();tec.dispose();pt?.cancel();super.dispose();}
  PageData get cp=>widget.book.pages[cur];
  void _updateText(String v){if(cp.text!=v){cp.undoStack.add(cp.text);if(cp.undoStack.length>30)cp.undoStack.removeAt(0);cp.redoStack.clear();cp.text=v;widget.onSave();}}
  void _undo(){if(cp.undoStack.isNotEmpty){cp.redoStack.add(cp.text);setState((){cp.text=cp.undoStack.removeLast();tec.text=cp.text;});widget.onSave();}}
  void _redo(){if(cp.redoStack.isNotEmpty){cp.undoStack.add(cp.text);setState((){cp.text=cp.redoStack.removeLast();tec.text=cp.text;});widget.onSave();}}
  void _newPage(){setState(()=>widget.book.pages.insert(cur+1,PageData()));widget.onSave();pc.nextPage(duration:Duration(milliseconds:300),curve:Curves.easeInOut);}
  void _startPresent(){if(widget.book.pages.length<2)return;setState(()=>presenting=true);pt=Timer.periodic(Duration(seconds:widget.book.timerSec),(t){if(cur<widget.book.pages.length-1){pc.nextPage(duration:Duration(milliseconds:500),curve:Curves.easeInOut);}else{t.cancel();setState(()=>presenting=false);}});}
  void _stopPresent(){pt?.cancel();setState(()=>presenting=false);}
  @override Widget build(BuildContext c){
    var bg=bgColors[widget.book.bgIndex]; var isLight=widget.book.bgIndex==0||widget.book.bgIndex==4||widget.book.bgIndex==5;
    return Scaffold(backgroundColor:bg,appBar:AppBar(backgroundColor:Colors.black,leading:IconButton(icon:Icon(Icons.arrow_back),onPressed:(){widget.onSave();Navigator.pop(context);}),title:TextField(controller:TextEditingController(text:widget.book.title),style:TextStyle(color:Colors.white,fontWeight:FontWeight.bold),decoration:InputDecoration(border:InputBorder.none,hintText:'Title',hintStyle:TextStyle(color:Colors.white54)),onSubmitted:(v){setState(()=>widget.book.title=v.isEmpty?'Untitled':v);widget.onSave();}),actions:[
      IconButton(icon:Icon(presenting?Icons.pause:Icons.play_arrow),onPressed:presenting?_stopPresent:_startPresent),
      PopupMenuButton(icon:Icon(Icons.palette),itemBuilder:(_)=>List.generate(bgNames.length,(i)=>PopupMenuItem(child:Text(bgNames[i]),onTap:(){Future.delayed(Duration(milliseconds:100),(){setState(()=>widget.book.bgIndex=i);widget.onSave();});}))),
      IconButton(icon:Icon(Icons.timer),onPressed:(){showDialog(context:context,builder:(_)=>AlertDialog(title:Text('Timer per page'),content:TextField(keyboardType:TextInputType.number,decoration:InputDecoration(suffixText:'seconds'),controller:TextEditingController(text:widget.book.timerSec.toString()),onSubmitted:(v){setState(()=>widget.book.timerSec=int.tryParse(v)??5);widget.onSave();Navigator.pop(context);}),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:Text('OK'))]));}),
    ]),
    body:Column(children:[
      Container(color:Colors.black87,padding:EdgeInsets.symmetric(horizontal:8,vertical:4),child:SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
        IconButton(icon:Icon(Icons.format_bold,color:cp.bold?Colors.amber:Colors.white),onPressed:(){setState(()=>cp.bold=!cp.bold);widget.onSave();}),IconButton(icon:Icon(Icons.format_italic,color:cp.italic?Colors.amber:Colors.white),onPressed:(){setState(()=>cp.italic=!cp.italic);widget.onSave();}),IconButton(icon:Icon(Icons.format_underline,color:cp.underline?Colors.amber:Colors.white),onPressed:(){setState(()=>cp.underline=!cp.underline);widget.onSave();}),
        IconButton(icon:Icon(Icons.undo,color:Colors.white),onPressed:_undo),IconButton(icon:Icon(Icons.redo,color:Colors.white),onPressed:_redo),
        IconButton(icon:Icon(Icons.text_decrease),onPressed:(){setState(()=>cp.fontSize=(cp.fontSize-2).clamp(12,32));widget.onSave();}),Text('${cp.fontSize.toInt()}',style:TextStyle(color:Colors.white)),IconButton(icon:Icon(Icons.text_increase),onPressed:(){setState(()=>cp.fontSize=(cp.fontSize+2).clamp(12,32));widget.onSave();}),
        IconButton(icon:Icon(Icons.add),onPressed:_newPage),Text('${cur+1}/${widget.book.pages.length}',style:TextStyle(color:Colors.white70,fontSize:12))
      ]))),
      Expanded(child:PageView.builder(controller:pc,itemCount:widget.book.pages.length,onPageChanged:(i){setState((){cur=i;tec.text=widget.book.pages[i].text;});},itemBuilder:(_,i){
        var pg=widget.book.pages[i];
        return Container(margin:EdgeInsets.all(14),padding:EdgeInsets.all(18),decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(16),boxShadow:[BoxShadow(color:Colors.black26,blurRadius:12)],border:Border.all(color:isLight?Colors.black12:Colors.white12)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Page ${i+1}',style:TextStyle(color:isLight?Colors.black54:Colors.white54,fontSize:11)),Divider(color:isLight?Colors.black12:Colors.white12),
          Expanded(child:TextField(controller:i==cur?tec:TextEditingController(text:pg.text),maxLines:null,expands:true,style:TextStyle(color:isLight?Colors.black:Colors.white,fontSize:pg.fontSize,fontWeight:pg.bold?FontWeight.bold:FontWeight.normal,fontStyle:pg.italic?FontStyle.italic:FontStyle.normal,decoration:pg.underline?TextDecoration.underline:TextDecoration.none),decoration:InputDecoration(border:InputBorder.none,hintText:'Start typing...',hintStyle:TextStyle(color:isLight?Colors.black26:Colors.white24)),onChanged:i==cur?_updateText:(v){pg.text=v;widget.onSave();}))
        ]));
      })),
      if(presenting)LinearProgressIndicator(value:1,backgroundColor:Colors.white10,color:Colors.amber,minHeight:3)
    ]));
  }
}

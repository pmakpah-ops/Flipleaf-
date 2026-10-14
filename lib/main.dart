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
  static FormatRange fromJson(Map<String,dynamic> j) => FormatRange(j["s"], j["e"], bold:j["b"]??false, italic:j["i"]??false, underline:j["u"]??false, fontSize:(j["fs"] as num?)?.toDouble());
}

class PageData {
  String text;
  List<FormatRange> formats;
  double fontSize;
  PageData({this.text="", List<FormatRange>? formats, this.fontSize=18}) : formats = formats?? [];
  Map<String,dynamic> toJson() => {"text":text, "formats": formats.map((e)=>e.toJson()).toList(), "fs":fontSize};
  static PageData fromJson(Map<String,dynamic> j) => PageData(text:j["text"]??"", formats: ((j["formats"] as List?)?? []).map((e)=>FormatRange.fromJson(Map<String,dynamic>.from(e))).toList(), fontSize:(j["fs"] as num?)?.toDouble()??18);
  PageData copy() {
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
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if(text.isEmpty) return TextSpan(text:"", style:style);
    List<TextSpan> ch=[];
    for(int i=0

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/channel.dart';
import 'quang_native_player.dart';
import 'quang_native_browser.dart';

class QuangNativeTube extends StatefulWidget {
  final List<String> legacySearches;
  final bool fullscreen;
  final ValueChanged<bool> onFullscreen;
  const QuangNativeTube({super.key,this.legacySearches=const [],required this.fullscreen,required this.onFullscreen});
  @override
  State<QuangNativeTube> createState()=>_QuangNativeTubeState();
}
class _QuangNativeTubeState extends State<QuangNativeTube> {
  static const api=MethodChannel('quangtv/modules');
  final search=TextEditingController();
  List<Map<String,dynamic>> items=[],watched=[];List<String> searches=[];
  List<Map<String,dynamic>> qualities=[];
  String error='',mode='feed',title='Đề xuất',page='';
  bool loading=false;int generation=0;
  Channel? playing;GlobalKey<QuangNativePlayerState> playerKey=GlobalKey<QuangNativePlayerState>();
  @override
  void initState(){super.initState();_history();_load();}
  Future<void> _history()async{try{final value=await api.invokeMapMethod<String,dynamic>('history',{'legacy':widget.legacySearches});if(mounted)setState((){searches=(value?['searches'] as List? ?? []).map((e)=>e.toString()).toList();watched=(value?['videos'] as List? ?? []).map((e)=>Map<String,dynamic>.from(e as Map)).toList();});}on PlatformException{/* Keep the current list available. */}}
  Future<void> _load([String query=''])async{
    final uri=Uri.tryParse(query);
    if(uri?.scheme=='https'&&(uri!.host=='youtu.be'||uri.host=='youtube.com'||uri.host.endsWith('.youtube.com'))){await _play({'url':query,'title':'YouTube'});return;}
    final request=++generation;setState((){loading=true;error='';mode='feed';title=query.isEmpty?'Đề xuất':query;});
    try{if(query.trim().isNotEmpty)await api.invokeMethod<void>('recordSearch',{'query':query});final data=await api.invokeListMethod<dynamic>('catalog',{'query':query});if(mounted&&request==generation)setState(()=>items=(data ?? []).map((e)=>Map<String,dynamic>.from(e as Map)).toList());await _history();}
    on PlatformException catch(e){if(mounted&&request==generation)setState(()=>error=e.message ?? 'Không tải được danh sách');}
    finally{if(mounted&&request==generation)setState(()=>loading=false);}
  }
  Future<void> _play(Map<String,dynamic> item)async{
    final url=item['url']?.toString() ?? 'https://www.youtube.com/watch?v=${item['id']}';
    final request=++generation;FocusManager.instance.primaryFocus?.unfocus();setState((){loading=true;error='';});
    try{final data=await api.invokeMapMethod<String,dynamic>('playback',{'url':url});if(!mounted||request!=generation)return;
      final source=data?['url']?.toString() ?? '';if(source.isEmpty)throw PlatformException(code:'SOURCE',message:'Không có nguồn phát phù hợp');
      final prefs=await SharedPreferences.getInstance();
      await prefs.setString('quangtv_headers_${base64Url.encode(utf8.encode(source))}',jsonEncode({'User-Agent':'Mozilla/5.0','Referer':'https://www.youtube.com/'}));
      if(!mounted||request!=generation)return;
      setState((){page=data?['page']?.toString() ?? url;playerKey=GlobalKey<QuangNativePlayerState>();playing=Channel(name:data?['title']?.toString() ?? item['title']?.toString() ?? 'Video',url:source,country:'YouTube');qualities=(data?['choices'] as List? ?? []).map((e)=>Map<String,dynamic>.from(e as Map)).toList();});
      final uri=Uri.parse(page);final id=uri.queryParameters['v'] ?? (uri.host=='youtu.be'&&uri.pathSegments.isNotEmpty?uri.pathSegments.first:'');
      _recordWhenPlaying(page,{'id':id,'title':playing!.name,'thumbnail':data?['thumbnail']?.toString() ?? item['thumbnail']?.toString() ?? ''});
    }on PlatformException catch(e){if(mounted&&request==generation)setState(()=>error=e.message ?? 'Không phát được video');}
    finally{if(mounted&&request==generation)setState(()=>loading=false);}
  }
  Future<void> _recordWhenPlaying(String selectedPage,Map<String,dynamic> item)async {
    for(var i=0;i<120;i++) {
      await Future<void>.delayed(const Duration(milliseconds:500));
      if(!mounted||page!=selectedPage||playing==null)return;
      final state=playerKey.currentState;
      final p=state?.controller;final v=state?.vlc;
      if((p?.value.isPlaying==true&&(p?.value.position.inSeconds ?? 0)>1)||(v?.value.isPlaying==true&&(v?.value.position.inSeconds ?? 0)>1)) {
        await api.invokeMethod<void>('recordVideo',item);await _history();return;
      }
    }
  }
  Future<void> _download()async{
    if(page.isEmpty)return;setState(()=>loading=true);
    try{final options=await api.invokeListMethod<dynamic>('tubeExtract',{'url':page});if(!mounted)return;
      await showModalBottomSheet<void>(context:context,builder:(sheet)=>SafeArea(child:ListView(shrinkWrap:true,children:[const ListTile(title:Text('Chất lượng tải · Có âm thanh')),for(final raw in options ?? [])ListTile(title:Text((raw as Map)['quality']?.toString() ?? 'MP4'),leading:const Icon(Icons.download_outlined),onTap:()async{Navigator.pop(sheet);await api.invokeMethod<void>('tubeDownload',Map<String,dynamic>.from(raw));if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Đã bắt đầu tải nền · Xem trong Đã tải')));})])));
    }on PlatformException catch(e){if(mounted)setState(()=>error=e.message ?? 'Không tải được video');}finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> _delete(String kind,[String? value])async{await api.invokeMethod<void>('deleteHistory',{'kind':kind,'value':value});await _history();}
  @override
  void dispose(){generation++;search.dispose();super.dispose();}
  @override
  Widget build(BuildContext context){
    final selected=playing;
    final player=selected==null?const SizedBox.shrink():QuangNativePlayer(key:playerKey,channel:selected,embedded:true,onFullscreenChanged:widget.onFullscreen);
    if(widget.fullscreen&&selected!=null)return player;
    return Column(children:[
      Padding(padding:const EdgeInsets.all(12),child:Row(children:[Expanded(child:TextField(controller:search,onSubmitted:(value)=>_load(value.trim()),textInputAction:TextInputAction.search,decoration:const InputDecoration(hintText:'Tìm trên QuangTube',prefixIcon:Icon(Icons.search),isDense:true))),PopupMenuButton<String>(tooltip:'Thư viện',onSelected:(value){_history();setState(()=>mode=value);},itemBuilder:(_)=>const [PopupMenuItem(value:'searches',child:Text('Lịch sử tìm kiếm')),PopupMenuItem(value:'videos',child:Text('Video đã xem')),PopupMenuItem(value:'downloads',child:Text('Đã tải'))])])),
      if(selected!=null)...[SizedBox(height:(MediaQuery.sizeOf(context).height*.28).clamp(130.0,240.0),width:double.infinity,child:player),ListTile(dense:true,title:Text(selected.name,maxLines:2,overflow:TextOverflow.ellipsis),trailing:Row(mainAxisSize:MainAxisSize.min,children:[if(qualities.isNotEmpty)PopupMenuButton<int>(tooltip:'Chất lượng',icon:const Icon(Icons.high_quality),onSelected:(index)=>setState((){playerKey=GlobalKey<QuangNativePlayerState>();playing=Channel(name:selected.name,url:qualities[index]['url'].toString(),country:'YouTube');}),itemBuilder:(_)=>[for(var i=0;i<qualities.length;i++)PopupMenuItem(value:i,child:Text(qualities[i]['quality']?.toString() ?? 'Tự động'))]),IconButton(tooltip:'Tải video',onPressed:_download,icon:const Icon(Icons.download_outlined)),IconButton(tooltip:'Đóng video',onPressed:()=>setState(()=>playing=null),icon:const Icon(Icons.close))]))],
      if(loading)const LinearProgressIndicator(),
      if(error.isNotEmpty)ListTile(title:Text(error),trailing:IconButton(tooltip:'Thử lại',onPressed:()=>_load(search.text.trim()),icon:const Icon(Icons.refresh))),
      SizedBox(height:48,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:12),children:[for(final topic in ['Đề xuất','Âm nhạc','Tin tức','Học tập'])Padding(padding:const EdgeInsets.only(right:8),child:ActionChip(label:Text(topic),onPressed:()=>_load(topic=='Đề xuất'?'':topic))),ActionChip(label:const Text('Lịch sử'),onPressed:(){_history();setState(()=>mode='videos');})])),
      Expanded(child:mode=='downloads'?const QuangNativeDownloads():mode=='searches'||mode=='videos'?_records():RefreshIndicator(onRefresh:()=>_load(search.text.trim()),child:ListView(padding:const EdgeInsets.all(12),children:[Text(title,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w600)),for(final item in items)_card(item),if(items.isEmpty&&!loading&&error.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('Chưa có video. Hãy tìm theo chủ đề bạn thích.'))]))),
    ]);
  }
  Widget _card(Map<String,dynamic> item)=>Card(clipBehavior:Clip.antiAlias,margin:const EdgeInsets.only(top:12),child:InkWell(onTap:()=>_play(item),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[if((item['thumbnail']?.toString() ?? '').startsWith('https://'))AspectRatio(aspectRatio:16/9,child:Image.network(item['thumbnail'].toString(),fit:BoxFit.cover,cacheWidth:640,errorBuilder:(_,error,stack)=>const Center(child:Icon(Icons.smart_display_outlined,size:40)))),ListTile(title:Text(item['title']?.toString() ?? 'Video',maxLines:2,overflow:TextOverflow.ellipsis),subtitle:Text(item['author']?.toString() ?? ''),trailing:const Icon(Icons.play_circle_outline))])));
  Widget _records(){final searchesMode=mode=='searches';return Column(children:[Row(children:[Expanded(child:Padding(padding:const EdgeInsets.all(12),child:Text(searchesMode?'Lịch sử tìm kiếm':'Video đã xem'))),TextButton(onPressed:()=>_delete(searchesMode?'searches':'videos'),child:const Text('Xóa tất cả'))]),Expanded(child:ListView(children:searchesMode?[for(final query in searches)ListTile(leading:const Icon(Icons.history),title:Text(query),onTap:(){search.text=query;_load(query);},trailing:IconButton(tooltip:'Xóa tìm kiếm',onPressed:()=>_delete('searches',query),icon:const Icon(Icons.close)))]:[for(final item in watched)ListTile(leading:const Icon(Icons.smart_display_outlined),title:Text(item['title']?.toString() ?? 'Video'),onTap:()=>_play(item),trailing:IconButton(tooltip:'Xóa lịch sử xem',onPressed:()=>_delete('videos',item['id'].toString()),icon:const Icon(Icons.close)))]))]);}
}

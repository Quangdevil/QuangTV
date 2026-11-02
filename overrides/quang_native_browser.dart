import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/channel.dart';
import 'quang_native_player.dart';

class _MayTab { String url=''; final previous=<String>[];final next=<String>[];final media=<String>{}; }

class QuangNativeBrowser extends StatefulWidget {
  final bool fullscreen;
  final ValueChanged<bool> onFullscreen;
  const QuangNativeBrowser({super.key,required this.fullscreen,required this.onFullscreen});
  @override
  State<QuangNativeBrowser> createState()=>_QuangNativeBrowserState();
}
class _QuangNativeBrowserState extends State<QuangNativeBrowser> {
  static const api=MethodChannel('quangtv/modules');
  static const origin='https://may-viet-web-proxy.daquang.workers.dev';
  final address=TextEditingController();
  final tabs=<_MayTab>[_MayTab()];int tabIndex=0;
  List<String> get previous=>tabs[tabIndex].previous;
  List<String> get next=>tabs[tabIndex].next;
  Set<String> get media=>tabs[tabIndex].media;
  late final String token=List.generate(20,(_)=>Random.secure().nextInt(256).toRadixString(16).padLeft(2,'0')).join();
  late final WebViewController web;
  bool loading=false,showFiles=false,history=false;
  String page='',error='';int generation=0;
  bool wasLandscape=false;
  @override
  void didChangeDependencies(){super.didChangeDependencies();final landscape=MediaQuery.orientationOf(context)==Orientation.landscape;if(landscape!=wasLandscape){wasLandscape=landscape;if(media.isNotEmpty||playing!=null){WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)widget.onFullscreen(landscape);});}}}
  Channel? playing;GlobalKey<QuangNativePlayerState> playerKey=GlobalKey<QuangNativePlayerState>();
  @override
  void initState(){super.initState();web=WebViewController()
    ..setBackgroundColor(const Color(0xff0b111a))
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..addJavaScriptChannel('MayNative',onMessageReceived:(message){
      if(!mounted)return;
      try{final d=jsonDecode(message.message) as Map<String,dynamic>;if(d['token']!=token)return;
        final type=d['type'];if(type=='quang-media'){_detect(d['url']?.toString() ?? '');}
        if(type=='may-navigate'){_open(d['url']?.toString() ?? '',method:d['method']=='POST'?'POST':'GET',fields:d['fields']);}
        if(type=='may-command'){switch(d['command']){case 'home':_home();break;case 'back':_back();break;case 'forward':_forward();break;case 'reload':if(page.isNotEmpty){_open(page,replace:true);}break;}}
      }catch(_){/* Ignore messages that are not from the app-owned parent. */}
    })
    ..setNavigationDelegate(NavigationDelegate(onNavigationRequest:(request){
      if(!mounted)return NavigationDecision.prevent;
      if(request.url.startsWith('$origin/native-content')||request.url=='about:blank'||request.url=='about:srcdoc')return NavigationDecision.navigate;
      final uri=Uri.tryParse(request.url);
      if(uri==null||!['http','https'].contains(uri.scheme))return NavigationDecision.prevent;
      if(request.isMainFrame||uri.host!='may-viet-web-proxy.daquang.workers.dev'){_open(request.url);return NavigationDecision.prevent;}
      return NavigationDecision.navigate;
    }));}
  void _detect(String raw){
    var uri=Uri.tryParse(raw);if(uri==null)return;
    for(var i=0;i<3&&uri!=null&&uri.host=='may-viet-web-proxy.daquang.workers.dev'&&uri.queryParameters['url']!=null;i++){uri=Uri.tryParse(uri.queryParameters['url']!);}
    if(uri==null||!['http','https'].contains(uri.scheme))return;
    if(!RegExp(r'\.(mp4|m3u8|webm|m4v)(?:$|[?&])',caseSensitive:false).hasMatch(uri.toString())&&!uri.queryParameters.values.any((v)=>v.startsWith('video/')))return;
    if(media.length<40&&mounted&&!media.contains(uri.toString()))setState(()=>media.add(uri.toString()));
  }
  Future<void> _open(String raw,{String method='GET',dynamic fields,bool replace=false})async{
    if(!mounted)return;
    final value=raw.trim();if(value.isEmpty)return;
    final url=value.startsWith('http://')||value.startsWith('https://')?value:(!value.contains(' ')&&value.contains('.')?'https://$value':'https://duckduckgo.com/?q=${Uri.encodeQueryComponent(value)}');
    if(!['http','https'].contains(Uri.tryParse(url)?.scheme))return;
    final request=++generation;FocusManager.instance.primaryFocus?.unfocus();
    setState((){loading=true;error='';showFiles=false;history=false;playing=null;});
    try{
      final safeFields=fields is List ? fields.whereType<List>().where((e)=>e.length==2&&e.every((v)=>v is String)).take(300).map((e)=>e.cast<String>()).toList() : null;
      final data=await api.invokeMapMethod<String,dynamic>('browse',{'url':url,'method':method,'fields':safeFields});
      if(!mounted||request!=generation)return;
      if(!replace&&page.isNotEmpty){previous.add(page);next.clear();}
      page=url;tabs[tabIndex].url=url;address.text=url;media.clear();
      const capture="""<script>(()=>{const send=u=>{if(u)parent.postMessage({type:'quang-media',url:u},'*')};const scan=()=>{document.querySelectorAll('video,video source').forEach(v=>send(v.currentSrc||v.src));document.querySelectorAll('meta[property^="og:video"],meta[itemprop="contentUrl"]').forEach(m=>send(m.content));performance.getEntriesByType('resource').forEach(r=>send(r.name));};addEventListener('loadedmetadata',scan,true);addEventListener('message',e=>{if(e.source===parent&&e.data?.type==='quang-pause')document.querySelectorAll('video,audio').forEach(v=>v.pause())});setInterval(scan,1500);scan()})();</script>""";
      final html=jsonEncode((data?['html']?.toString() ?? '')+capture).replaceAll('<',r'\u003c');
      final shell='''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body,iframe{margin:0;width:100%;height:100%;border:0;background:#0b111a}</style></head><body><script>
      const f=document.createElement('iframe');f.setAttribute('sandbox','allow-scripts allow-forms');f.allow='fullscreen; autoplay';f.allowFullscreen=true;f.referrerPolicy='no-referrer';f.srcdoc=$html;document.body.append(f);
      addEventListener('message',e=>{if(e.source!==f.contentWindow||e.origin!=='null'||!e.data||typeof e.data!=='object')return;const d=e.data;if(['may-navigate','may-command','quang-media'].includes(d.type))MayNative.postMessage(JSON.stringify({...d,token:'$token'}))});
      </script></body></html>''';
      await web.loadHtmlString(shell,baseUrl:'$origin/native-content');
    }on PlatformException catch(e){if(mounted&&request==generation)setState(()=>error=e.message ?? 'Không mở được trang');}
    catch(_){if(mounted&&request==generation)setState(()=>error='Không mở được trang. Hãy thử lại.');}
    finally{if(mounted&&request==generation)setState(()=>loading=false);}
  }
  void _pausePage(){web.runJavaScript("document.querySelector('iframe')?.contentWindow.postMessage({type:'quang-pause'},'*')");}
  void _home(){generation++;web.runJavaScript("document.querySelector('iframe')?.remove()");setState((){page='';tabs[tabIndex].url='';playing=null;showFiles=false;history=false;media.clear();address.clear();});}
  void _back(){if(previous.isEmpty){_home();return;}next.add(page);_open(previous.removeLast(),replace:true);}
  void _forward(){if(next.isNotEmpty){previous.add(page);_open(next.removeLast(),replace:true);}}
  Future<void> _tabs()async {
    await showModalBottomSheet<void>(context:context,builder:(sheet)=>SafeArea(child:ListView(shrinkWrap:true,children:[
      ListTile(title:Text('Tab (${tabs.length}/8)'),trailing:IconButton(tooltip:'Tab mới',onPressed:tabs.length>=8?null:(){Navigator.pop(sheet);_pausePage();setState((){tabs.add(_MayTab());tabIndex=tabs.length-1;page='';address.clear();playing=null;showFiles=false;});},icon:const Icon(Icons.add))),
      for(var i=0;i<tabs.length;i++)ListTile(leading:Icon(i==tabIndex?Icons.radio_button_checked:Icons.radio_button_unchecked),title:Text(tabs[i].url.isEmpty?'Trang mới':tabs[i].url,maxLines:1,overflow:TextOverflow.ellipsis),onTap:(){Navigator.pop(sheet);_pausePage();generation++;setState(()=>tabIndex=i);if(tabs[i].url.isEmpty){_home();}else{_open(tabs[i].url,replace:true);}},trailing:IconButton(tooltip:'Đóng tab',onPressed:(){Navigator.pop(sheet);_pausePage();generation++;setState((){tabs.removeAt(i);if(tabs.isEmpty)tabs.add(_MayTab());tabIndex=tabIndex.clamp(0,tabs.length-1);});if(tabs[tabIndex].url.isEmpty){_home();}else{_open(tabs[tabIndex].url,replace:true);}},icon:const Icon(Icons.close))),
    ])));
  }
  Future<void> _links()async{
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,builder:(sheet)=>SafeArea(child:SizedBox(height:MediaQuery.sizeOf(sheet).height*.55,child:Column(children:[
      const ListTile(title:Text('Video trong trang')),
      Expanded(child:media.isEmpty?const Center(child:Text('Phát video trong trang để nhận diện nguồn tải.')):ListView(children:[for(final url in media)ListTile(title:Text(Uri.tryParse(url)?.path.split('/').last ?? 'Video',maxLines:1,overflow:TextOverflow.ellipsis),subtitle:Text(Uri.tryParse(url)?.host ?? ''),trailing:Wrap(children:[
        IconButton(tooltip:'Phát trong app',icon:const Icon(Icons.play_circle_outline),onPressed:(){Navigator.pop(sheet);_pausePage();setState((){playerKey=GlobalKey<QuangNativePlayerState>();playing=Channel(name:'Video trình duyệt',url:'$origin/proxy?url=${Uri.encodeQueryComponent(url)}',country:'Browser');});}),
        IconButton(tooltip:'Tải về',icon:const Icon(Icons.download_outlined),onPressed:()async{Navigator.pop(sheet);try{final extension=Uri.tryParse(url)?.path.toLowerCase().endsWith('.webm')==true?'webm':Uri.tryParse(url)?.path.toLowerCase().endsWith('.m3u8')==true?'m3u8':'mp4';await api.invokeMethod<Object>('download',{'url':'$origin/proxy?url=${Uri.encodeQueryComponent(url)}','name':'May-${DateTime.now().millisecondsSinceEpoch}.$extension'});if(mounted)setState(()=>showFiles=true);}on PlatformException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message ?? 'Không tải được')));}}),
      ]))])),
    ]))));
  }
  @override
  void dispose(){generation++;web.runJavaScript("document.querySelector('iframe')?.remove()");address.dispose();super.dispose();}
  @override
  Widget build(BuildContext context){
    final video=playing;
    final content=video!=null?QuangNativePlayer(key:playerKey,channel:video,embedded:true,startMuted:true,onFullscreenChanged:widget.onFullscreen):page.isEmpty?_landing():WebViewWidget(controller:web);
    if(widget.fullscreen)return PopScope(canPop:false,onPopInvokedWithResult:(didPop,result){if(!didPop){if(playerKey.currentState?.fullscreen==true){playerKey.currentState?.toggleFullscreen();}else{widget.onFullscreen(false);}}},child:Stack(children:[Positioned.fill(child:content),Positioned(top:8,right:8,child:IconButton(tooltip:'Thu nhỏ',onPressed:(){if(playerKey.currentState?.fullscreen==true){playerKey.currentState?.toggleFullscreen();}else{widget.onFullscreen(false);}},icon:const Icon(Icons.fullscreen_exit)))]));
    return Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(12,8,12,6),child:Row(children:[Expanded(child:TextField(controller:address,onSubmitted:_open,keyboardType:TextInputType.url,textInputAction:TextInputAction.go,decoration:const InputDecoration(hintText:'Tìm kiếm hoặc nhập địa chỉ',prefixIcon:Icon(Icons.public),isDense:true))),TextButton(onPressed:_tabs,child:Text('${tabs.length}')),IconButton(tooltip:'Trang đầu Mây',onPressed:_home,icon:const Icon(Icons.home_outlined))])),
      if(loading)const LinearProgressIndicator(),
      if(error.isNotEmpty)ListTile(title:Text(error),trailing:IconButton(tooltip:'Thử lại',onPressed:()=>_open(address.text,replace:true),icon:const Icon(Icons.refresh))),
      Expanded(child:showFiles?const QuangNativeDownloads():content),
      SafeArea(top:false,child:Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[IconButton(tooltip:'Quay lại',onPressed:_back,icon:const Icon(Icons.chevron_left)),IconButton(tooltip:'Tiến tới',onPressed:next.isEmpty?null:_forward,icon:const Icon(Icons.chevron_right)),TextButton.icon(onPressed:_links,icon:const Icon(Icons.video_library_outlined),label:Text('Video (${media.length})')),IconButton(tooltip:'Đã tải',onPressed:(){_pausePage();setState(()=>showFiles=!showFiles);},icon:const Icon(Icons.folder_outlined)),IconButton(tooltip:'Toàn màn hình',onPressed:(){if(playing!=null){playerKey.currentState?.toggleFullscreen();}else{widget.onFullscreen(true);}},icon:const Icon(Icons.fullscreen))])),
    ]);
  }
  Widget _landing()=>ListView(padding:const EdgeInsets.all(24),children:[const SizedBox(height:20),const Icon(Icons.cloud_outlined,size:54,color:Color(0xff8ae4d1)),const SizedBox(height:16),const Text('Mây',textAlign:TextAlign.center,style:TextStyle(fontSize:36,fontWeight:FontWeight.w700)),const Padding(padding:EdgeInsets.symmetric(vertical:16),child:Text('Không gian duyệt web của bạn',textAlign:TextAlign.center)),for(final item in {'Google':'https://www.google.com/','Facebook':'https://m.facebook.com/','Telegram':'https://web.telegram.org/','Tin tức':'https://vnexpress.net/'}.entries)Card(child:ListTile(title:Text(item.key),trailing:const Icon(Icons.north_east),onTap:()=>_open(item.value))),Card(child:ListTile(leading:const Icon(Icons.folder_outlined),title:const Text('Tệp đã tải'),onTap:(){_pausePage();setState(()=>showFiles=true);}))]);
}

class QuangNativeDownloads extends StatefulWidget {
  const QuangNativeDownloads({super.key});
  @override
  State<QuangNativeDownloads> createState()=>_QuangNativeDownloadsState();
}
class _QuangNativeDownloadsState extends State<QuangNativeDownloads> {
  static const api=MethodChannel('quangtv/modules');
  List<Map<String,dynamic>> files=[];Timer? timer;String folder='';
  Future<void> _load()async{try{final data=await api.invokeListMethod<dynamic>('downloads') ?? [];if(mounted)setState(()=>files=data.map((e)=>Map<String,dynamic>.from(e as Map)).toList());}on PlatformException{/* Retain the current file list while the service is busy. */}}
  @override
  void initState(){super.initState();_load();timer=Timer.periodic(const Duration(seconds:2),(_)=>_load());}
  @override
  void dispose(){timer?.cancel();super.dispose();}
  @override
  Widget build(BuildContext context)=>Column(children:[ListTile(leading:IconButton(tooltip:'Thư mục',icon:const Icon(Icons.folder_outlined),onPressed:()=>setState(()=>folder='')),title:Text(folder.isEmpty?'Đã tải':'Đã tải / ${folder=='videos'?'Video':'Đang tải'}')),
    Expanded(child:folder.isEmpty?ListView(children:[ListTile(leading:const Icon(Icons.folder),title:const Text('Video đã tải'),subtitle:Text('${files.where((e)=>e['complete']==true).length} tệp'),onTap:()=>setState(()=>folder='videos')),ListTile(leading:const Icon(Icons.folder),title:const Text('Đang tải / Lỗi'),subtitle:Text('${files.where((e)=>e['complete']!=true).length} lượt tải'),onTap:()=>setState(()=>folder='active'))]):ListView(children:[for(final file in files.where((e)=>folder=='videos'?e['complete']==true:e['complete']!=true))Dismissible(key:ValueKey(file['key']),direction:DismissDirection.endToStart,background:Container(color:Colors.red.shade700,alignment:Alignment.centerRight,padding:const EdgeInsets.all(16),child:const Icon(Icons.delete_outline)),confirmDismiss:(_)async{final removed=await api.invokeMethod<bool>('deleteDownload',{'key':file['key']}) ?? false;if(removed&&mounted){setState(()=>files.removeWhere((e)=>e['key']==file['key']));}return removed;},child:ListTile(leading:Icon(file['complete']==true?Icons.play_circle_outline:Icons.downloading),title:Text(file['name']?.toString() ?? 'Video'),subtitle:Text(file['detail']?.toString() ?? ''),onTap:file['complete']==true?()=>api.invokeMethod<void>('openDownload',{'key':file['key']}):null,trailing:IconButton(tooltip:file['active']==true?'Hủy tải':'Xóa tệp',onPressed:()async{await api.invokeMethod<bool>('deleteDownload',{'key':file['key']});await _load();},icon:const Icon(Icons.delete_outline))))])),
  ]);
}

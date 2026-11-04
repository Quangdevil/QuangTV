import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/channel.dart';
import 'quang_native_player.dart';

class _MayTab { String url=''; final previous=<String>[];final next=<String>[];final media=<String>{}; }

class QuangNativeBrowser extends StatefulWidget {
  final bool fullscreen;
  final ValueChanged<bool> onFullscreen;
  final String? initialUrl;
  final bool direct;
  const QuangNativeBrowser({super.key,required this.fullscreen,required this.onFullscreen,this.initialUrl,this.direct=false});
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
  String? _expectedVideoId;
  bool _captureBlocked=false;
  @override
  void didChangeDependencies(){super.didChangeDependencies();final landscape=MediaQuery.orientationOf(context)==Orientation.landscape;if(landscape!=wasLandscape){wasLandscape=landscape;if(media.isNotEmpty||playing!=null){WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)widget.onFullscreen(landscape);});}}}
  Channel? playing;GlobalKey<QuangNativePlayerState> playerKey=GlobalKey<QuangNativePlayerState>();
  @override
  void initState(){super.initState();web=WebViewController()
    ..setBackgroundColor(const Color(0xff0b111a))
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..addJavaScriptChannel('MayNative',onMessageReceived:(message){
      if(!mounted)return;
      try{final d=jsonDecode(message.message) as Map<String,dynamic>;if(d['token']!=token)return;if(widget.direct&&(_captureBlocked||d['page']!=page))return;
        final type=d['type'];if(type=='quang-media'){_detect(d['url']?.toString() ?? '',mediaElement:d['mediaElement']==true);}
        if(widget.direct)return;
        if(type=='may-navigate'){_open(d['url']?.toString() ?? '',method:d['method']=='POST'?'POST':'GET',fields:d['fields']);}
        if(type=='may-command'){switch(d['command']){case 'home':_home();break;case 'back':_back();break;case 'forward':_forward();break;case 'reload':if(page.isNotEmpty){_open(page,replace:true);}break;}}
      }catch(_){/* Ignore messages that are not from the app-owned parent. */}
    })
    ..setNavigationDelegate(NavigationDelegate(onPageStarted:(url){
      if(!widget.direct||!mounted)return;
      final uri=Uri.tryParse(url);if(uri==null||!['http','https'].contains(uri.scheme))return;
      if(!_acceptDirectTarget(uri))return;
      setState((){if(page!=url){if(page.isNotEmpty)previous.add(page);next.clear();media.clear();}page=url;tabs[tabIndex].url=url;address.text=url;loading=true;});
    },onPageFinished:(url){
      if(widget.direct&&mounted){if(!_captureBlocked)web.runJavaScript(_directCapture());setState(()=>loading=false);}
    },onNavigationRequest:(request){
      if(!mounted)return NavigationDecision.prevent;
      if(request.url.startsWith('$origin/native-content')||request.url=='about:blank'||request.url=='about:srcdoc')return NavigationDecision.navigate;
      final uri=Uri.tryParse(request.url);
      if(uri==null||!['http','https'].contains(uri.scheme))return NavigationDecision.prevent;
      if(widget.direct){if(request.isMainFrame&&!_acceptDirectTarget(uri))return NavigationDecision.prevent;return NavigationDecision.navigate;}
      if(request.isMainFrame||uri.host!='may-viet-web-proxy.daquang.workers.dev'){_open(request.url);return NavigationDecision.prevent;}
      return NavigationDecision.navigate;
    }));
    final initial=widget.initialUrl;
    if(initial!=null&&initial.isNotEmpty)WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)_open(initial);});
  }
  String? _videoId(Uri uri){
    final host=uri.host.toLowerCase();
    final supported=['douyin.com','iesdouyin.com','tiktok.com','facebook.com','fb.com','fb.watch'].any((domain)=>host==domain||host.endsWith('.$domain'));
    if(!supported)return null;
    final path=RegExp(r'/(?:video|videos|reel|v)/(\d+)(?:[/.]|$)').firstMatch(uri.path)?.group(1);
    if(path!=null)return path;
    for(final key in ['modal_id','v']){final id=uri.queryParameters[key];if(id!=null&&RegExp(r'^\d+$').hasMatch(id))return id;}
    return null;
  }
  bool _acceptDirectTarget(Uri uri){
    final id=_videoId(uri);
    if(_expectedVideoId==null){if(id!=null)_expectedVideoId=id;return !_captureBlocked;}
    if(id==_expectedVideoId)return !_captureBlocked;
    // An expired/unavailable share URL can silently open an unrelated feed.
    // Keep its media out of the download sheet rather than saving another clip.
    if(mounted)setState((){_captureBlocked=true;media.clear();loading=false;error='Trang đã chuyển khỏi video được chia sẻ. Không bắt video đề xuất khác. Hãy mở lại đúng link video.';});
    return false;
  }
  String _directCapture()=>r"""(()=>{if(window.__quangCapture)return;window.__quangCapture=true;
    const seen=new Set();const send=(url,mediaElement)=>{try{if(!/^https?:\/\//i.test(url)||seen.has(url)||seen.size>=120)return;seen.add(url);MayNative.postMessage(JSON.stringify({type:'quang-media',url,mediaElement,page:location.href,token:'__TOKEN__'}))}catch(_){}};
    const scan=()=>{document.querySelectorAll('video,video source').forEach(v=>send(v.currentSrc||v.src,true));document.querySelectorAll('meta[property^="og:video"],meta[itemprop="contentUrl"]').forEach(m=>send(m.content,true));performance.getEntriesByType('resource').forEach(r=>{if(r.initiatorType==='video'||/[?&](?:mime_type|mime)=video/i.test(r.name)||/\/(?:aweme\/v1\/play|video\/tos\/)/i.test(r.name)||/\.(mp4|m3u8|webm|m4v)(?:$|[?&])/i.test(r.name))send(r.name,true)})};
    addEventListener('loadedmetadata',scan,true);setInterval(scan,1500);scan();
  })()""".replaceAll('__TOKEN__',token);
  void _detect(String raw,{bool mediaElement=false}){
    var uri=Uri.tryParse(raw);if(uri==null)return;
    for(var i=0;i<3&&uri!=null&&uri.host=='may-viet-web-proxy.daquang.workers.dev'&&uri.queryParameters['url']!=null;i++){uri=Uri.tryParse(uri.queryParameters['url']!);}
    if(uri==null||!['http','https'].contains(uri.scheme))return;
    if(!mediaElement&&!RegExp(r'\.(mp4|m3u8|webm|m4v)(?:$|[?&])',caseSensitive:false).hasMatch(uri.toString())&&!uri.queryParameters.values.any((v)=>v.startsWith('video/')))return;
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
      if(widget.direct){
        _expectedVideoId=_videoId(Uri.parse(url));_captureBlocked=false;
        if(!replace&&page.isNotEmpty&&page!=url){previous.add(page);next.clear();}
        page=url;tabs[tabIndex].url=url;address.text=url;media.clear();
        await web.loadRequest(Uri.parse(url));return;
      }
      final safeFields=fields is List ? fields.whereType<List>().where((e)=>e.length==2&&e.every((v)=>v is String)).take(300).map((e)=>e.cast<String>()).toList() : null;
      final data=await api.invokeMapMethod<String,dynamic>('browse',{'url':url,'method':method,'fields':safeFields});
      if(!mounted||request!=generation)return;
      if(!replace&&page.isNotEmpty){previous.add(page);next.clear();}
      page=url;tabs[tabIndex].url=url;address.text=url;media.clear();
      const capture="""<script>(()=>{const seen=new Set();const send=(u,mediaElement=false)=>{if(u&&!seen.has(u)&&seen.size<120){seen.add(u);parent.postMessage({type:'quang-media',url:u,mediaElement},'*')}};const scan=()=>{document.querySelectorAll('video,video source').forEach(v=>send(v.currentSrc||v.src,true));document.querySelectorAll('meta[property^="og:video"],meta[itemprop="contentUrl"]').forEach(m=>send(m.content,true));performance.getEntriesByType('resource').forEach(r=>{if(r.initiatorType==='video'||/[.](mp4|m3u8|webm|m4v)(?:$|[?&])/i.test(r.name))send(r.name,r.initiatorType==='video')});};addEventListener('loadedmetadata',scan,true);addEventListener('message',e=>{if(e.source===parent&&e.data?.type==='quang-pause')document.querySelectorAll('video,audio').forEach(v=>v.pause())});setInterval(scan,1500);scan()})();</script>""";
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
  void _pausePage(){unawaited(web.runJavaScript(widget.direct?"document.querySelectorAll('video,audio').forEach(v=>v.pause())":"document.querySelector('iframe')?.contentWindow.postMessage({type:'quang-pause'},'*')").catchError((Object _){}));}
  void _home(){generation++;_expectedVideoId=null;_captureBlocked=false;_pausePage();if(widget.direct){web.loadHtmlString('<body style="background:#0b111a"></body>');}else{web.runJavaScript("document.querySelector('iframe')?.remove()");}setState((){page='';tabs[tabIndex].url='';playing=null;showFiles=false;history=false;media.clear();address.clear();});}
  void _back(){if(previous.isEmpty){_home();return;}next.add(page);_open(previous.removeLast(),replace:true);}
  void _forward(){if(next.isNotEmpty){previous.add(page);_open(next.removeLast(),replace:true);}}
  Future<void> _tabs()async {
    await showModalBottomSheet<void>(context:context,builder:(sheet)=>SafeArea(child:ListView(shrinkWrap:true,children:[
      ListTile(title:Text('Tab (${tabs.length}/8)'),trailing:IconButton(tooltip:'Tab mới',onPressed:tabs.length>=8?null:(){Navigator.pop(sheet);_pausePage();setState((){tabs.add(_MayTab());tabIndex=tabs.length-1;page='';address.clear();playing=null;showFiles=false;});},icon:const Icon(Icons.add))),
      for(var i=0;i<tabs.length;i++)ListTile(leading:Icon(i==tabIndex?Icons.radio_button_checked:Icons.radio_button_unchecked),title:Text(tabs[i].url.isEmpty?'Trang mới':tabs[i].url,maxLines:1,overflow:TextOverflow.ellipsis),onTap:(){Navigator.pop(sheet);_pausePage();generation++;setState(()=>tabIndex=i);if(tabs[i].url.isEmpty){_home();}else{_open(tabs[i].url,replace:true);}},trailing:IconButton(tooltip:'Đóng tab',onPressed:(){Navigator.pop(sheet);_pausePage();generation++;setState((){tabs.removeAt(i);if(tabs.isEmpty)tabs.add(_MayTab());tabIndex=tabIndex.clamp(0,tabs.length-1);});if(tabs[tabIndex].url.isEmpty){_home();}else{_open(tabs[tabIndex].url,replace:true);}},icon:const Icon(Icons.close))),
    ])));
  }
  Future<void> _links()async{
    if(_captureBlocked)return;
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,builder:(sheet)=>SafeArea(child:SizedBox(height:MediaQuery.sizeOf(sheet).height*.55,child:Column(children:[
      const ListTile(title:Text('Video trong trang')),
      Expanded(child:media.isEmpty?const Center(child:Text('Phát video trong trang để nhận diện nguồn tải.')):ListView(children:[for(final url in media)ListTile(title:Text(Uri.tryParse(url)?.path.split('/').last ?? 'Video',maxLines:1,overflow:TextOverflow.ellipsis),subtitle:Text(Uri.tryParse(url)?.host ?? ''),trailing:Wrap(children:[
        IconButton(tooltip:'Phát trong app',icon:const Icon(Icons.play_circle_outline),onPressed:(){Navigator.pop(sheet);_playMedia(url);}),
        IconButton(tooltip:'Tải về',icon:const Icon(Icons.download_outlined),onPressed:()async{Navigator.pop(sheet);try{final extension=Uri.tryParse(url)?.path.toLowerCase().endsWith('.webm')==true?'webm':Uri.tryParse(url)?.path.toLowerCase().endsWith('.m3u8')==true?'m3u8':'mp4';await api.invokeMethod<Object>('download',{'url':widget.direct?url:'$origin/proxy?url=${Uri.encodeQueryComponent(url)}','page':page,'direct':widget.direct,'name':'May-${DateTime.now().millisecondsSinceEpoch}.$extension'});if(mounted)setState(()=>showFiles=true);}on PlatformException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message ?? 'Không tải được')));}}),
      ]))])),
    ]))));
  }
  Future<void> _playMedia(String url)async{
    _pausePage();
    final source=widget.direct?url:'$origin/proxy?url=${Uri.encodeQueryComponent(url)}';
    try{
      if(widget.direct){
        final headers=await api.invokeMapMethod<String,dynamic>('browserMediaHeaders',{'url':url,'page':page}) ?? {};
        final prefs=await SharedPreferences.getInstance();
        await prefs.setString('quangtv_headers_${base64Url.encode(utf8.encode(source))}',jsonEncode(headers));
      }
      if(!mounted)return;
      setState((){playerKey=GlobalKey<QuangNativePlayerState>();playing=Channel(name:'Video trình duyệt',url:source,country:'Browser');});
    }on PlatformException catch(e){if(mounted)setState(()=>error=e.message ?? 'Không mở được video.');}
  }
  @override
  void dispose(){generation++;_pausePage();unawaited(web.loadHtmlString('<body></body>').catchError((Object _){}));address.dispose();super.dispose();}
  @override
  Widget build(BuildContext context){
    final video=playing;
    final content=video!=null?QuangNativePlayer(key:playerKey,channel:video,embedded:true,startMuted:true,onFullscreenChanged:widget.onFullscreen):page.isEmpty?_landing():WebViewWidget(controller:web);
    if(widget.fullscreen)return PopScope(canPop:false,onPopInvokedWithResult:(didPop,result){if(!didPop){if(playerKey.currentState?.fullscreen==true){playerKey.currentState?.toggleFullscreen();}else{widget.onFullscreen(false);}}},child:Stack(children:[Positioned.fill(child:content),Positioned(top:8,right:8,child:IconButton(tooltip:'Thu nhỏ',onPressed:(){if(playerKey.currentState?.fullscreen==true){playerKey.currentState?.toggleFullscreen();}else{widget.onFullscreen(false);}},icon:const Icon(Icons.fullscreen_exit)))]));
    return Column(children:[
      if(error.isNotEmpty)ListTile(title:Text(error),trailing:IconButton(tooltip:'Thử lại',onPressed:()=>_open(address.text,replace:true),icon:const Icon(Icons.refresh))),
      Expanded(child:showFiles?const QuangNativeDownloads():content),
      _bottomBar(),
    ]);
  }
  Widget _bottomBar()=>Material(color:const Color(0xff111e29),elevation:12,child:SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(10,8,10,2),child:Column(mainAxisSize:MainAxisSize.min,children:[
    if(loading)const Padding(padding:EdgeInsets.only(bottom:8),child:LinearProgressIndicator(minHeight:2)),
    Row(children:[
      Expanded(child:TextField(key:const ValueKey('browser-address'),controller:address,onSubmitted:_open,keyboardType:TextInputType.url,textInputAction:TextInputAction.go,autocorrect:false,enableSuggestions:false,decoration:InputDecoration(hintText:'Tìm kiếm hoặc nhập địa chỉ',prefixIcon:const Icon(Icons.public,size:20),filled:true,fillColor:const Color(0xff0b141e),contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:11),isDense:true,border:OutlineInputBorder(borderRadius:BorderRadius.circular(24),borderSide:BorderSide.none),suffixIcon:IconButton(tooltip:'Mở địa chỉ',onPressed:()=>_open(address.text),icon:const Icon(Icons.arrow_forward,size:20))))),
      const SizedBox(width:4),
      IconButton(tooltip:'Tab (${tabs.length})',onPressed:_tabs,icon:Badge(label:Text('${tabs.length}'),child:const Icon(Icons.tab_outlined))),
    ]),
    Row(children:[
      IconButton(tooltip:'Quay lại',onPressed:_back,icon:const Icon(Icons.chevron_left)),
      IconButton(tooltip:'Tiến tới',onPressed:next.isEmpty?null:_forward,icon:const Icon(Icons.chevron_right)),
      Expanded(child:FilledButton.icon(key:const ValueKey('browser-capture'),onPressed:_captureBlocked?null:_links,style:FilledButton.styleFrom(backgroundColor:const Color(0xff8ae4d1),foregroundColor:const Color(0xff123832),padding:const EdgeInsets.symmetric(horizontal:10)),icon:const Icon(Icons.video_library_outlined,size:19),label:Text('Bắt video (${media.length})',maxLines:1,overflow:TextOverflow.ellipsis))),
      IconButton(tooltip:'Đã tải',onPressed:(){_pausePage();setState(()=>showFiles=!showFiles);},icon:const Icon(Icons.folder_outlined)),
      PopupMenuButton<String>(tooltip:'Tác vụ trình duyệt',onSelected:(action){switch(action){case 'home':_home();break;case 'reload':if(page.isNotEmpty)_open(page,replace:true);break;case 'fullscreen':if(playing!=null){playerKey.currentState?.toggleFullscreen();}else{widget.onFullscreen(true);}break;}},itemBuilder:(_)=>const [PopupMenuItem(value:'home',child:Text('Trang đầu Mây')),PopupMenuItem(value:'reload',child:Text('Tải lại trang')),PopupMenuItem(value:'fullscreen',child:Text('Toàn màn hình'))]),
    ]),
  ]))));
  Widget _landing()=>LayoutBuilder(builder:(context,constraints){final width=constraints.maxWidth;return ListView(padding:EdgeInsets.symmetric(horizontal:width>600?48:24,vertical:24),children:[
    const SizedBox(height:12),
    Container(alignment:Alignment.center,child:Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(color:const Color(0xff173d39),borderRadius:BorderRadius.circular(28)),child:const Icon(Icons.cloud_outlined,size:46,color:Color(0xff8ae4d1)))),
    const SizedBox(height:18),const Text('Mây',textAlign:TextAlign.center,style:TextStyle(fontSize:34,fontWeight:FontWeight.w700)),
    const Padding(padding:EdgeInsets.only(top:8,bottom:26),child:Text('Một không gian, nhiều điều khám phá',textAlign:TextAlign.center,style:TextStyle(color:Color(0xff93a7b3)))),
    Wrap(spacing:12,runSpacing:12,children:[for(final item in {'Google':'https://www.google.com/','Facebook':'https://m.facebook.com/','Telegram':'https://web.telegram.org/','Tin tức':'https://vnexpress.net/'}.entries)SizedBox(width:(width-(width>600?96:48)-12)/2,child:Material(color:const Color(0xff111e29),borderRadius:BorderRadius.circular(18),child:InkWell(borderRadius:BorderRadius.circular(18),onTap:()=>_open(item.value),child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Icon(Icons.public,color:Color(0xff8ae4d1)),const SizedBox(height:14),Text(item.key,style:const TextStyle(fontWeight:FontWeight.w600)),const SizedBox(height:4),const Text('Mở trong Mây',style:TextStyle(fontSize:12,color:Color(0xff93a7b3)))])))))]),
    const SizedBox(height:20),
    Card(color:const Color(0xff17332f),child:ListTile(leading:const Icon(Icons.video_library_outlined,color:Color(0xff8ae4d1)),title:const Text('Bắt video trong trang'),subtitle:const Text('Phát video rồi chạm Bắt video ở thanh dưới.'),onTap:_links)),
    Card(color:const Color(0xff111e29),child:ListTile(leading:const Icon(Icons.folder_outlined),title:const Text('Tệp đã tải'),subtitle:const Text('Mở xem và quản lý video trên máy'),trailing:const Icon(Icons.chevron_right),onTap:(){_pausePage();setState(()=>showFiles=true);})),
  ]);});
}

class QuangNativeDownloads extends StatefulWidget {
  const QuangNativeDownloads({super.key});
  @override
  State<QuangNativeDownloads> createState()=>_QuangNativeDownloadsState();
}
class _QuangNativeDownloadsState extends State<QuangNativeDownloads> {
  static const api=MethodChannel('quangtv/modules');
  List<Map<String,dynamic>> files=[];
  Timer? timer;
  String folder='';
  bool busy=false;
  String message='';
  Future<void> _load()async{
    try{
      final data=await api.invokeListMethod<dynamic>('downloads') ?? [];
      if(mounted)setState(()=>files=data.map((e)=>Map<String,dynamic>.from(e as Map)).toList());
    }on PlatformException catch(e){if(mounted)setState(()=>message=e.message ?? 'Không đọc được thư mục tải.');}
  }
  @override
  void initState(){super.initState();_load();timer=Timer.periodic(const Duration(seconds:2),(_){if(!busy)_load();});}
  @override
  void dispose(){timer?.cancel();super.dispose();}
  Future<bool> _remove(Map<String,dynamic> file)async{
    if(busy)return false;
    setState(()=>busy=true);
    try{
      final removed=await api.invokeMethod<bool>('deleteDownload',{'key':file['key']}) ?? false;
      if(mounted)setState((){if(removed)files.removeWhere((e)=>e['key']==file['key']);else message='Chưa xóa được tệp. Hãy thử lại.';});
      return removed;
    }on PlatformException catch(e){if(mounted)setState(()=>message=e.message ?? 'Không xóa được tệp.');return false;}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> _removeAll()async{
    if(files.isEmpty||busy)return;
    // Capture only app-owned keys shown before confirmation. New downloads that
    // arrive while the dialog is open are not silently included in the deletion.
    final keys=files.map((e)=>e['key'].toString()).toList(growable:false);
    final confirmed=await showDialog<bool>(context:context,builder:(dialog)=>AlertDialog(
      title:const Text('Xóa toàn bộ video?'),
      content:Text('Xóa ${keys.length} mục và các tệp tương ứng khỏi bộ nhớ máy. Các lượt đang tải sẽ bị hủy. Không thể hoàn tác.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialog,false),child:const Text('Hủy')),TextButton(key:const ValueKey('downloads-confirm-delete-all'),onPressed:()=>Navigator.pop(dialog,true),child:const Text('Xóa toàn bộ'))],
    )) ?? false;
    if(!confirmed||!mounted)return;
    setState(()=>busy=true);
    try{
      final result=await api.invokeMapMethod<String,dynamic>('deleteDownloads',{'keys':keys});
      if(mounted)setState(()=>message=(result?['failed'] as num? ?? 0)>0?'Đã xóa ${result?['removed'] ?? 0} mục; còn ${result?['failed']} mục chưa xóa được.':'Đã xóa các tệp và lượt tải đã chọn.');
      await _load();
    }on PlatformException catch(e){if(mounted)setState(()=>message=e.message ?? 'Không xóa được toàn bộ tệp.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> _retry(Map<String,dynamic> file)async{
    if(busy)return;
    setState(()=>busy=true);
    try{
      final retried=await api.invokeMethod<bool>('retryDownload',{'key':file['key']}) ?? false;
      if(mounted)setState(()=>message=retried?'Đã bắt đầu tải lại.':'Không còn nguồn tải. Hãy mở lại link video để lấy nguồn mới.');
      await _load();
    }on PlatformException catch(e){if(mounted)setState(()=>message=e.message ?? 'Không thể tải lại.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  List<Map<String,dynamic>> get visible=>files.where((e)=>folder=='videos'?e['complete']==true:folder=='active'?e['active']==true:e['complete']!=true&&e['active']!=true).toList();
  String get folderTitle=>folder=='videos'?'Video đã tải':folder=='active'?'Đang tải':'Tải lỗi';
  @override
  Widget build(BuildContext context)=>Column(children:[
    Padding(padding:const EdgeInsets.fromLTRB(8,8,8,0),child:Row(children:[IconButton(tooltip:'Thư mục',icon:Icon(folder.isEmpty?Icons.folder_outlined:Icons.arrow_back),onPressed:()=>setState(()=>folder='')),Expanded(child:Text(folder.isEmpty?'Đã tải':folderTitle,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w700))),TextButton.icon(key:const ValueKey('downloads-delete-all'),onPressed:files.isEmpty||busy?null:_removeAll,icon:const Icon(Icons.delete_sweep_outlined,size:19),label:const Text('Xóa toàn bộ'))])),
    if(busy)const LinearProgressIndicator(minHeight:2),
    if(message.isNotEmpty)Padding(padding:const EdgeInsets.symmetric(horizontal:16,vertical:6),child:Text(message,style:const TextStyle(color:Color(0xff93a7b3)))),
    Expanded(child:RefreshIndicator(onRefresh:_load,child:folder.isEmpty?ListView(padding:const EdgeInsets.all(12),children:[
      _folder('Video đã tải',Icons.video_library_outlined,files.where((e)=>e['complete']==true).length,'videos'),
      _folder('Đang tải',Icons.downloading_outlined,files.where((e)=>e['active']==true).length,'active'),
      _folder('Tải lỗi',Icons.error_outline,files.where((e)=>e['complete']!=true&&e['active']!=true).length,'errors'),
      const Padding(padding:EdgeInsets.all(16),child:Text('Video được lưu trên máy. Xóa tại đây sẽ xóa luôn tệp.',style:TextStyle(fontSize:12,color:Color(0xff93a7b3)))),
    ]):ListView(padding:const EdgeInsets.all(12),children:[
      if(visible.isEmpty)Padding(padding:const EdgeInsets.symmetric(vertical:48),child:Column(children:[Icon(folder=='videos'?Icons.video_library_outlined:Icons.folder_open,size:40,color:const Color(0xff8ae4d1)),const SizedBox(height:16),Text(folder=='videos'?'Chưa có video đã tải':folder=='active'?'Không có lượt đang tải':'Không có lượt tải lỗi')])),
      for(final file in visible)Padding(padding:const EdgeInsets.only(bottom:8),child:Dismissible(key:ValueKey(file['key']),direction:busy?DismissDirection.none:DismissDirection.endToStart,background:Container(decoration:BoxDecoration(color:const Color(0xff7c2a32),borderRadius:BorderRadius.circular(16)),alignment:Alignment.centerRight,padding:const EdgeInsets.all(16),child:const Icon(Icons.delete_outline)),confirmDismiss:(_)async{await _remove(file);return false;},child:Material(color:const Color(0xff111e29),borderRadius:BorderRadius.circular(16),child:ListTile(contentPadding:const EdgeInsets.fromLTRB(14,6,6,6),leading:Icon(file['complete']==true?Icons.play_circle_outline:file['active']==true?Icons.downloading:Icons.error_outline,color:const Color(0xff8ae4d1)),title:Text(file['name']?.toString() ?? 'Video',maxLines:2,overflow:TextOverflow.ellipsis),subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(file['detail']?.toString() ?? ''),if(file['active']==true&&(file['total'] as num? ?? 0)>0)Padding(padding:const EdgeInsets.only(top:7),child:LinearProgressIndicator(value:((file['bytes'] as num? ?? 0)/(file['total'] as num)).clamp(0.0,1.0).toDouble()))]),onTap:file['complete']==true?()async{try{await api.invokeMethod<void>('openDownload',{'key':file['key']});}on PlatformException catch(e){if(mounted)setState(()=>message=e.message ?? 'Không mở được video.');}}:null,trailing:Row(mainAxisSize:MainAxisSize.min,children:[if(file['complete']!=true&&file['active']!=true)IconButton(tooltip:'Thử tải lại',onPressed:busy?null:()=>_retry(file),icon:const Icon(Icons.refresh)),IconButton(tooltip:file['active']==true?'Hủy tải':'Xóa tệp',onPressed:busy?null:()=>_remove(file),icon:const Icon(Icons.delete_outline))]))))),
    ]))),
  ]);
  Widget _folder(String title,IconData icon,int count,String target)=>Padding(padding:const EdgeInsets.only(bottom:10),child:Material(color:const Color(0xff111e29),borderRadius:BorderRadius.circular(16),child:ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:18,vertical:10),leading:Icon(icon,color:const Color(0xff8ae4d1),size:30),title:Text(title,style:const TextStyle(fontWeight:FontWeight.w600)),subtitle:Text('$count ${target=='videos'?'tệp':'lượt tải'}'),trailing:const Icon(Icons.chevron_right),onTap:()=>setState(()=>folder=target))));
}

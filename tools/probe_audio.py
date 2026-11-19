import json, urllib.request, urllib.parse
UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15'
IOSUA='com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)'
VRUA='com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip'
def visitor():
    r=urllib.request.urlopen(urllib.request.Request('https://www.youtube.com/sw.js_data',headers={'User-Agent':UA}),timeout=10).read().decode()
    if r.startswith(")]}'"): r=r[4:]
    return json.loads(r)[0][2][0][0][13]
V=visitor()
CL={
 'IOS':({'clientName':'IOS','clientVersion':'20.10.4','deviceMake':'Apple','deviceModel':'iPhone16,2','osName':'iPhone','osVersion':'18.3.2.22D82','userAgent':IOSUA,'hl':'ru','gl':'US','visitorData':V},'5',IOSUA),
 'VISIONOS':({'clientName':'VISIONOS','clientVersion':'1.02','deviceMake':'Apple','deviceModel':'RealityDevice17,1','osName':'visionOS','osVersion':'26.5.23O471','userAgent':UA,'hl':'ru','gl':'US','visitorData':V},'101',UA),
 'ANDROID_VR':({'clientName':'ANDROID_VR','clientVersion':'1.65.10','deviceMake':'Oculus','deviceModel':'Quest 3','androidSdkVersion':32,'userAgent':VRUA,'osName':'Android','osVersion':'12L','hl':'ru','gl':'US','visitorData':V},'28',VRUA),
}
def player(vid,name):
    c,cn,ua=CL[name]
    body=json.dumps({'context':{'client':c},'videoId':vid,'contentCheckOk':True,'racyCheckOk':True}).encode()
    req=urllib.request.Request('https://www.youtube.com/youtubei/v1/player?prettyPrint=false',data=body,headers={'Content-Type':'application/json','User-Agent':ua,'X-Youtube-Client-Name':cn,'X-Youtube-Client-Version':c['clientVersion'],'X-Goog-Visitor-Id':V,'Origin':'https://www.youtube.com'})
    return json.loads(urllib.request.urlopen(req,timeout=15).read()), ua
for vid in ['RM6qWf7TCww']:
  for name in CL:
    try:
        j,ua=player(vid,name)
        ps=j.get('playabilityStatus',{})
        sd=j.get('streamingData',{})
        af=sd.get('adaptiveFormats',[])
        print('=====',name,vid,ps.get('status'),'adaptive',len(af))
        for f in af:
            if not f['mimeType'].startswith('audio/'): continue
            u=f.get('url','')
            xt=urllib.parse.parse_qs(urllib.parse.urlparse(u).query).get('xtags',[''])[0] if u else ''
            print('  A',f['itag'],f['mimeType'][:28],f.get('bitrate'),'track=',json.dumps(f.get('audioTrack'),ensure_ascii=False),'xtags=',xt,'isDrc=',f.get('isDrc'))
        hls=sd.get('hlsManifestUrl')
        if hls:
            m=urllib.request.urlopen(urllib.request.Request(hls,headers={'User-Agent':ua}),timeout=15).read().decode()
            lines=m.split('\n')
            media=[l for l in lines if l.startswith('#EXT-X-MEDIA')]
            print('  HLS media lines:',len(media))
            for l in media[:30]: print('   ',l[:400])
            si=[l for l in lines if l.startswith('#EXT-X-STREAM-INF')]
            print('  HLS stream-inf:',len(si))
            for l in si[:4]: print('   ',l[:400])
    except Exception as e:
        print(name,vid,'ERR',e)

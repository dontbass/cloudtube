import json, urllib.request, sys
UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15'
def visitor():
    r=urllib.request.urlopen(urllib.request.Request('https://www.youtube.com/sw.js_data',headers={'User-Agent':UA}),timeout=10).read().decode()
    if r.startswith(")]}'"): r=r[4:]
    return json.loads(r)[0][2][0][0][13]
def player(vid, client):
    v=visitor()
    if client=='VISIONOS':
        c={'clientName':'VISIONOS','clientVersion':'1.02','deviceMake':'Apple','deviceModel':'RealityDevice17,1','osName':'visionOS','osVersion':'26.5.23O471','userAgent':UA,'hl':'ru','gl':'US','visitorData':v}; cn='101'; ua=UA
    else:
        ua='com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip'
        c={'clientName':'ANDROID_VR','clientVersion':'1.65.10','deviceMake':'Oculus','deviceModel':'Quest 3','androidSdkVersion':32,'userAgent':ua,'osName':'Android','osVersion':'12L','hl':'ru','gl':'US','visitorData':v}; cn='28'
    body=json.dumps({'context':{'client':c},'videoId':vid,'contentCheckOk':True,'racyCheckOk':True}).encode()
    req=urllib.request.Request('https://www.youtube.com/youtubei/v1/player?prettyPrint=false',data=body,headers={'Content-Type':'application/json','User-Agent':ua,'X-Youtube-Client-Name':cn,'X-Youtube-Client-Version':c['clientVersion'],'X-Goog-Visitor-Id':v,'Origin':'https://www.youtube.com'})
    j=json.loads(urllib.request.urlopen(req,timeout=15).read())
    return j, ua
for client in ['VISIONOS','ANDROID_VR']:
  for vid in ['aqz-KE-bpKQ','dQw4w9WgXcQ']:
    try:
        j,ua=player(vid,client)
        ps=j.get('playabilityStatus',{})
        af=j.get('streamingData',{}).get('adaptiveFormats',[])
        print(client,vid,ps.get('status'),ps.get('reason'),'adaptive',len(af),'withurl',sum(1 for f in af if 'url' in f))
        vs=[f for f in af if 'url' in f and f['mimeType'].startswith('video/')]
        for f in vs[:40]:
            print('  ',f['itag'],f.get('qualityLabel'),f['mimeType'][:40],f.get('bitrate'),'init' in str(f.get('initRange')),'n=' in f['url'])
        if vs:
            f=max(vs,key=lambda f:f.get('height',0))
            cl=int(f.get('contentLength',0))
            for off in [0, 5_000_000, 30_000_000, cl//2]:
                try:
                    rq=urllib.request.Request(f['url'],headers={'User-Agent':ua,'Range':'bytes=%d-%d'%(off,off+500_000)})
                    rs=urllib.request.urlopen(rq,timeout=20); d=rs.read()
                    print('   range',off,rs.status,len(d))
                except Exception as e: print('   range',off,'ERR',e)
    except Exception as e:
        print(client,vid,'ERR',e)

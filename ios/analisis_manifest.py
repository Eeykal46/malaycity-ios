import json,urllib.request
m=json.load(urllib.request.urlopen("https://malaycity.com/mobile/manifest.json",timeout=40))
f=m["files"]
tot=sum(x["size"] for x in f)
k={}
for x in f:
    p=x["path"].lower()
    if ".pvr." in p: n="pvr (iOS)"
    elif ".etc." in p: n="etc (Android)"
    elif ".dxt." in p: n="dxt (PC)"
    else: n="biasa (semua)"
    g=k.setdefault(n,[0,0]); g[0]+=1; g[1]+=x["size"]
for n in sorted(k,key=lambda z:-k[z][1]):
    print("{:<16} {:>4} fail {:>9.0f} MB".format(n,k[n][0],k[n][1]/1024**2))
print()
print("JUMLAH        : {:.2f} GB".format(tot/1024**3))
b=k.get("biasa (semua)",[0,0])[1]; p=k.get("pvr (iOS)",[0,0])[1]
print("biasa+pvr saja: {:.2f} GB  (jimat {:.0f}%)".format((b+p)/1024**3,100*(1-(b+p)/tot)))

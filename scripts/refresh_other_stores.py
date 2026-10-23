#!/usr/bin/env python3
"""Refresh Bowtie pre-owned inventory from public Hicks Auto Group listings.
Only public retail-safe vehicle attributes are exported. No price caching, age or private fields.
"""
import json,re,urllib.request,urllib.parse,time
from html.parser import HTMLParser
from pathlib import Path
ROOT="https://www.hicksautogroup.com/inventory/used"
STORES={
 "edhicksnissan.com":"Ed Hicks Nissan",
 "edhicksinfiniti.com":"Ed Hicks INFINITI",
 "edhicksimports.com":"Ed Hicks Imports",
 "hicksfamilynissan.com":"Hicks Family Nissan",
}
class Links(HTMLParser):
 def __init__(self): super().__init__();self.links=[];self.url=None;self.parts=[]
 def handle_starttag(self,tag,attrs):
  if tag=="a":self.url=dict(attrs).get("href","");self.parts=[]
 def handle_data(self,data):
  if self.url is not None:self.parts.append(data)
 def handle_endtag(self,tag):
  if tag=="a" and self.url is not None:self.links.append((self.url," ".join(self.parts)));self.url=None
def read(url):
 req=urllib.request.Request(url,headers={"User-Agent":"BowtieInventoryResearch/1.0 (public vehicle listing; contact site owner for access)"})
 with urllib.request.urlopen(req,timeout=30) as r:return r.read().decode("utf-8","replace")
def parse_page(html):
 p=Links();p.feed(html);found=[]
 for href,label in p.links:
  full=urllib.parse.urljoin(ROOT,href)
  host=(urllib.parse.urlparse(full).hostname or "").lower().removeprefix("www.")
  if host not in STORES:continue
  label=" ".join(label.split())
  vin=re.search(r"\\bvin\\s*[:#]?\\s*([A-HJ-NPR-Z0-9]{17})\\b",label,re.I)
  stock=re.search(r"\\bStock\\s*#\\s*([A-Za-z0-9-]+)",label,re.I)
  title=re.search(r"\\b(20\\d{2}|19\\d{2})\\s+(.+?)\\s+Selling Price",label,re.I)
  miles=re.search(r"\\bMileage\\s+([\\d,]+)\\s+Miles",label,re.I)
  if not(vin and stock and title):continue
  vehicle=title.group(2).strip()
  makes=["Mercedes-Benz","Land Rover","Alfa Romeo","Aston Martin","Chevrolet","Volkswagen","Mitsubishi","INFINITI","Nissan","Toyota","Honda","Hyundai","Kia","Ford","Jeep","Dodge","GMC","RAM","BMW","Audi","Lexus","Subaru","Buick","Mazda","Lincoln","Volvo","Cadillac","Porsche","Acura","Genesis","Chrysler","MINI","Tesla","FIAT"]
  make=next((m for m in makes if vehicle.lower().startswith(m.lower()+" ")),"")
  rest=vehicle[len(make):].strip() if make else vehicle
  found.append(dict(id=vin.group(1).upper(),vin=vin.group(1).upper(),stock=stock.group(1),year=int(title.group(1)),make=make,model=rest,trim="",type="used",store=STORES[host],miles=int(miles.group(1).replace(",","")) if miles else 0,photo="",dealerUrl=full if urllib.parse.urlparse(full).path not in ("/inventory/used","/") else "https://www."+host+"/inventory/used",lastVerified=None,sourceDate=time.strftime("%Y-%m-%d",time.gmtime()),gold=False))
 return found
def main():
 vehicles={}
 for page in range(1,16):
  url=ROOT+"?"+urllib.parse.urlencode(dict(inproduction="true",instock="true",intransit="true",page=page,paymenttype="cash"))
  try: items=parse_page(read(url))
  except Exception as e:
   if page==1:raise
   print("Stopping at page",page,str(e));break
  print("Page",page,"found",len(items))
  if not items:break
  before=len(vehicles)
  for v in items:vehicles[v["vin"]]=v
  if page>1 and len(vehicles)==before:break
  time.sleep(1)
 if len(vehicles)<20:raise RuntimeError("Insufficient listings; preserving previous snapshot")
 output={"source":"Hicks Auto Group public used-inventory pages (not a live availability guarantee)","checkedAt":time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime()),"vehicles":list(vehicles.values())}
 Path("inventory-other-stores.json").write_text(json.dumps(output,ensure_ascii=False,separators=(",",":"))+"\n")
 print("Published",len(vehicles),"unique VINs")
if __name__=="__main__":main()

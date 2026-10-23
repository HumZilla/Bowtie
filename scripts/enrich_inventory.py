#!/usr/bin/env python3
"""Enrich existing Bowtie inventory by VIN from public dealership pages.
Never adds/removes vehicles, guesses values, or modifies Gold/referrals.
Requires: pip install requests beautifulsoup4
"""
import json,re,time,sys
from pathlib import Path
from urllib.parse import urljoin,urlparse
import requests
from bs4 import BeautifulSoup
ROOT=Path(__file__).resolve().parents[1]
SITES={
'Hicks Family Subaru':'https://www.hicksfamilysubaru.com',
'Ed Hicks Nissan':'https://www.edhicksnissan.com',
'Ed Hicks INFINITI':'https://www.edhicksinfiniti.com',
'Ed Hicks Imports':'https://www.edhicksimports.com',
'Hicks Family Nissan':'https://www.hicksfamilynissan.com'}
session=requests.Session();session.headers['User-Agent']='Mozilla/5.0 (compatible; BowtieInventoryVerifier/1.0)'
VIN=re.compile(r'\b[A-HJ-NPR-Z0-9]{17}\b',re.I)
def fetch(url):
 try:
  r=session.get(url,timeout=25);r.raise_for_status()
  return r.text
 except requests.RequestException as e:
  print('Fetch failed',url,str(e),file=sys.stderr);return ''
def records(obj):
 if isinstance(obj,dict):
  yield obj
  for v in obj.values():yield from records(v)
 elif isinstance(obj,list):
  for v in obj:yield from records(v)
def candidates(soup,base):
 out={}
 for a in soup.select('a[href]'):
  u=urljoin(base,a['href']);p=urlparse(u)
  if p.hostname not in (urlparse(base).hostname,):continue
  if not any(x in p.path.lower() for x in ('viewdetails','/vehicle/','/used/','/new/')):continue
  vin=VIN.search(u+' '+a.get_text(' ',strip=True))
  if vin:out[vin.group().upper()]=u
 return out
def extract(html,vin,base):
 soup=BeautifulSoup(html,'html.parser')
 text=soup.get_text(' ',strip=True)
 if vin.upper() not in html.upper():return {}
 data={}
 for tag in soup.select('script[type="application/ld+json"]'):
  try:
   for item in records(json.loads(tag.string or tag.get_text())):
    if str(item.get('vehicleIdentificationNumber','')).upper()!=vin and str(item.get('vin','')).upper()!=vin:continue
    mileage=item.get('mileageFromOdometer')
    if isinstance(mileage,dict):mileage=mileage.get('value')
    if mileage is not None:
     try:data['miles']=int(str(mileage).replace(',',''))
     except ValueError:pass
    offers=item.get('offers')
    if isinstance(offers,dict):
     try:data['price']=int(float(str(offers.get('price','')).replace(',','')))
     except ValueError:pass
    images=item.get('image')
    if isinstance(images,str):images=[images]
    if isinstance(images,list):
     for img in images:
      if isinstance(img,str) and img.startswith('https://'):data['photo']=img;break
  except (ValueError,TypeError):pass
 if 'miles' not in data:
  m=re.search(r'Mileage\s*[:#]?\s*([\d,]+)\s*Miles',text,re.I)
  if m:data['miles']=int(m.group(1).replace(',',''))
 if 'price' not in data:
  m=re.search(r'(?:Selling Price|Internet Price|Our Price)\s*\$([\d,]+)',text,re.I)
  if m:data['price']=int(m.group(1).replace(',',''))
 if 'photo' not in data:
  for el in soup.select('meta[property="og:image"],meta[name="twitter:image"]'):
   u=el.get('content','')
   if u.startswith('https://') and vin.lower() in u.lower():data['photo']=u;break
 return data
def main():
 pages={}
 for store,base in SITES.items():
  links={}
  for suffix in ('/inventory/used','/inventory/new'):
   html=fetch(base+suffix)
   if html:links.update(candidates(BeautifulSoup(html,'html.parser'),base))
  pages[store]=links
  print(store,'VIN-linked listing URLs:',len(links))
 for filename in ('inventory-public.json','inventory-other-stores.json'):
  path=ROOT/filename;data=json.loads(path.read_text());counts={'matched':0,'price':0,'miles':0,'photo':0}
  for v in data['vehicles']:
   vin=v.get('vin','').upper();base=SITES.get(v.get('store'))
   if not base:continue
   url=pages[v['store']].get(vin)
   existing=v.get('dealerUrl','')
   if not url and vin.lower() in existing.lower() and urlparse(existing).hostname==urlparse(base).hostname:url=existing
   if not url:continue
   html=fetch(url)
   if not html:continue
   details=extract(html,vin,base)
   if not details:continue  # Do not mark unverifiable pages as matched
   v['dealerUrl']=url;counts['matched']+=1
   for key in ('price','miles','photo'):
    if details.get(key) is not None and details.get(key)!='':
     v[key]=details[key];counts[key]+=1
   v['lastVerified']=time.strftime('%Y-%m-%d',time.gmtime())
   time.sleep(.15)
  path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
  print(filename,counts)
if __name__=='__main__':main()

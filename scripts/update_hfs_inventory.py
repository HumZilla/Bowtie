#!/usr/bin/env python3
"""Refresh HFS inventory from MAX Digital. Fail closed on unexpected feed changes."""
import csv
import io
import json
import os
import re
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

URL = "https://pubftp.max.firstlook.biz/MAX_FBInv/HICKSFAM02.csv"
OUT = Path("inventory-public.json")
ALIASES = {
 "vin": ("vin", "vehiclevin"),
 "stock": ("stock", "stocknumber", "stockno", "stocknum"),
 "year": ("year", "modelyear"),
 "make": ("make", "manufacturer"),
 "model": ("model", "modelname"),
 "trim": ("trim", "trimlevel", "style", "series"),
 "price": ("price", "sellingprice", "internetprice", "saleprice", "specialprice", "ourprice", "eprice", "advertisedprice"),
 "msrp": ("msrp", "listprice", "stickerprice"),
 "miles": ("mileage", "miles", "odometer"),
 "color": ("exteriorcolor", "extcolor", "color"),
 "photo": ("imageurl", "photourl", "primaryimage", "image", "photo", "pictureurl"),
 "photos": ("images", "photos", "photourls", "imageurls"),
 "type": ("newused", "condition", "vehicletype", "inventorytype", "type"),
 "days": ("daysininventory", "daysinstock", "agedays", "age", "daysonlot"),
 "certified": ("certified", "iscertified", "cpo"),
 "url": ("vehicleurl", "detailurl", "vdpurl", "dealerurl", "url"),
}
def key(s):
 return re.sub(r"[^a-z0-9]", "", str(s).lower())
def field(row, name):
 for alias in ALIASES[name]:
  if alias in row and str(row[alias]).strip():
   return str(row[alias]).strip()
 return ""
def integer(s):
 try: return int(float(re.sub(r"[^0-9.]", "", s))) if s else 0
 except (ValueError, TypeError): return 0
def money(s):
 try: return round(float(re.sub(r"[^0-9.]", "", s)), 2) if s else 0
 except (ValueError, TypeError): return 0
def main():
 req = urllib.request.Request(URL, headers={"User-Agent": "BowtieInventorySync/1.0"})
 with urllib.request.urlopen(req, timeout=45) as response:
  raw = response.read(15_000_001)
 if len(raw) > 15_000_000 or len(raw) < 200:
  raise ValueError("Unexpected feed size; refusing to publish")
 decoded = raw.decode("utf-8-sig", errors="replace")
 dialect = csv.Sniffer().sniff(decoded[:4096], delimiters=",;\t|")
 reader = csv.DictReader(io.StringIO(decoded), dialect=dialect)
 headers = {key(x) for x in (reader.fieldnames or [])}
 for required in ("vin", "stock", "year", "make", "model"):
  if not any(a in headers for a in ALIASES[required]):
   raise ValueError("Missing required feed column: " + required + " (found: " + ", ".join(sorted(headers)) + ")")
 previous = json.loads(OUT.read_text(encoding="utf-8"))
 existing = {v.get("vin", "").upper(): v for v in previous.get("vehicles", [])}
 now = datetime.now(timezone.utc).date().isoformat()
 vehicles = {}
 total = 0
 for rawrow in reader:
  total += 1
  row = {key(k): v for k, v in rawrow.items() if k is not None}
  vin = field(row, "vin").upper()
  stock = field(row, "stock")
  if not re.fullmatch(r"[A-HJ-NPR-Z0-9]{17}", vin) or not stock:
   continue
  make = field(row, "make")
  typ = field(row, "type").lower()
  if typ in ("n", "new", "new vehicle"): typ = "new"
  elif typ in ("u", "used", "preowned", "pre-owned", "pre owned", "certified", "cpo"): typ = "used"
  elif not typ: typ = "new" if integer(field(row, "miles")) < 1000 and make.lower() == "subaru" else "used"
  else: continue
  if typ == "new" and make.lower() != "subaru": continue
  old = existing.get(vin, {})
  pic = field(row, "photo") or field(row, "photos").split("|")[0].split(",")[0]
  if not pic.startswith("https://"): pic = old.get("photo", "")
  age_raw = field(row, "days")
  age = integer(age_raw) if age_raw else None
  # Do not carry forward stale aging as though freshly verified.
  vehicles[vin] = {
   "id": vin, "vin": vin, "stock": stock, "year": integer(field(row, "year")),
   "make": make, "model": field(row, "model"), "trim": field(row, "trim"),
   "type": typ, "store": "Hicks Family Subaru", "miles": integer(field(row, "miles")),
   "color": field(row, "color"), "certified": field(row, "certified").lower() in ("yes", "true", "1", "y"),
   "photo": pic, "dealerUrl": field(row, "url"),
   "lastVerified": now, "sourceDate": now, "gold": False,
   "price": money(field(row, "price")), "msrp": money(field(row, "msrp")),
   "daysInInventory": age, "inventoryAgeAsOf": now if age is not None else None
  }
 if total < 5 or len(vehicles) < 5:
  raise ValueError(f"Only {len(vehicles)} valid vehicles from {total} rows; refusing to replace inventory")
 if len(existing) >= 20 and len(vehicles) < len(existing) * .35:
  raise ValueError(f"Unexpected inventory drop: {len(existing)} -> {len(vehicles)}; refusing to publish")
 result = {"source": URL, "exportedAt": now, "vehicles": sorted(vehicles.values(), key=lambda v:(v["type"],v["make"],v["model"],v["stock"]))}
 OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
 print(f"Updated {len(vehicles)} HFS vehicles from {total} feed rows")
if __name__ == "__main__":
 try: main()
 except Exception as e:
  print(f"Inventory refresh failed safely: {e}", file=sys.stderr)
  sys.exit(1)

#!/usr/bin/env python3
import re, pathlib, sys
langs=['de','en','es','fr']; data={}
for l in langs:
 text=pathlib.Path(f'Sources/Resources/{l}.lproj/Localizable.strings').read_text()
 data[l]=dict(re.findall(r'^"(.*?)"\s*=\s*"(.*?)";',text,re.M))
base=set(data['de']); failed=False
for l in langs[1:]:
 missing=base-set(data[l])
 if missing: print(l,'missing',sorted(missing)); failed=True
for key in ['Dynamisch','Erstellen','Wiedergeben','Entfernen','Umbenennen','Versionsname','Verwerfen']:
 for l in ['en','es','fr']:
  if data[l].get(key)==data['de'].get(key): print(f'{l}: untranslated {key}'); failed=True
sys.exit(1 if failed else 0)

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
# Uebersetzungs-Check: en-Text unveraendert in es/fr uebernommen, obwohl de abweicht (Ausnahmen: Lehnwoerter/Namen).
allowed={'Suggestions','Albums','Pause','Versions','Collections','Notes','Transitions','Quelle','Open Era to import it.\\\\n(The share extension requires a signed installation with App Groups.)'}
for l in ['es','fr']:
 same=[k for k in base if len(k)>3 and k not in allowed and data[l].get(k)==data['en'].get(k) and data['de'].get(k)!=data['en'].get(k)]
 if same: print(l,'looks untranslated:',same); failed=True
sys.exit(1 if failed else 0)

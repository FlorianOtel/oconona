import os, json, importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location("oc_db", Path.home()/".config/opencode/scripts/oc-db.py")
oc_db = importlib.util.module_from_spec(spec); spec.loader.exec_module(oc_db)
snap = oc_db.get_session_snapshot(os.environ["OC_SID"])
if snap: print(json.dumps(snap))

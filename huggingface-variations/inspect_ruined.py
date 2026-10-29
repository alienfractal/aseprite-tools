"""Read API metadata only; never submits an image generation."""
import inspect
import json
import sys
import httpx
from pathlib import Path
from gradio_client import Client
import hf_bridge as b

folder=b.ROOT/'jobs'/'verify-ruined'
folder.mkdir(parents=True,exist_ok=True)
token=b.load_token('default')
key='token' if 'token' in inspect.signature(Client).parameters else 'hf_token'
try:
    if '--source-only' in sys.argv:
        response=httpx.get('https://huggingface.co/spaces/lienthealien/RuinedHugg/raw/main/app.py',
                           headers={'Authorization':'Bearer '+token},timeout=60,follow_redirects=True)
        response.raise_for_status()
        path=folder/'source'/'app.py';path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(response.text,encoding='utf-8')
        print('Source saved for inspection:',path)
        raise SystemExit(0)
    client=Client('lienthealien/RuinedHugg',**{key:token},verbose=False,analytics_enabled=False)
    api=client.view_api(return_format='dict',print_info=False)
    b.atomic_json(folder/'api-info.json',api)
    for name,detail in api.get('named_endpoints',{}).items():
        print(name,[(p['parameter_name'],p.get('component'),p.get('parameter_has_default')) for p in detail.get('parameters',[])])
except Exception as exc:
    print(b.clean_error(exc,token))
    raise SystemExit(1)

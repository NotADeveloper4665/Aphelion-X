#!/usr/bin/python3
import json
import sys

responses = {
    "load_session": {"authenticated": True},
    "backend_status": {"ready": True},
    "load_settings": {},
    "list_consoles_smartglass": [
        {"name": "Fixture Xbox", "id": "presence-fixture-id", "powerState": "On"}
    ],
    "list_streaming_servers": {
        "continuationToken": None,
        "results": [{"name": "Fixture Xbox", "serverId": "streaming-fixture-id"}],
        "totalItems": 1,
    },
}

for line in sys.stdin:
    request = json.loads(line)
    result = responses[request["cmd"]]
    print(json.dumps({"api_version": 1, "id": request["id"], "result": result}), flush=True)

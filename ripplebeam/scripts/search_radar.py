#!/usr/bin/env python3
import sys
import json
from radarclient import RadarClient
from radarclient.authentication import AppleConnectAuthentication

def main():
    if len(sys.argv) < 2:
        print("Usage: search_radar.py <keyword>", file=sys.stderr)
        sys.exit(1)

    keyword = sys.argv[1]

    try:
        client = RadarClient(authentication_strategy=AppleConnectAuthentication())

        results = client.radars_for_find(
            {
                "keyValue": {
                    "key": "title",
                    "value": {
                        "like": f"%{keyword}%"
                    }
                }
            },
            additional_fields=[
                "id", "title", "state", "classification", "priority", "lastModifiedAt"
            ]
        )

        json.dump([r.to_dict() for r in results], sys.stdout, indent=2)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
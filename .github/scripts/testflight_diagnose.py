"""Inspect TestFlight state through the App Store Connect API and re-send pending invites.

Reads APPSTORE_KEY_ID, APPSTORE_ISSUER_ID, APPSTORE_API_PRIVATE_KEY and BUNDLE_ID from the
environment. Email addresses are masked in the output because Actions logs on a public repo
are visible to anyone.
"""
import base64
import os
import sys
import time

import jwt
import requests

API = "https://api.appstoreconnect.apple.com"


def mask(email):
    if not email or "@" not in email:
        return email or "?"
    user, domain = email.split("@", 1)
    return f"{user[:2]}***@{domain}"


def token():
    key = os.environ["APPSTORE_API_PRIVATE_KEY"]
    if "BEGIN PRIVATE KEY" not in key:
        key = base64.b64decode(key).decode()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["APPSTORE_ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": os.environ["APPSTORE_KEY_ID"], "typ": "JWT"},
    )


SESSION = requests.Session()
SESSION.headers["Authorization"] = f"Bearer {token()}"


def get(path, **params):
    r = SESSION.get(API + path, params=params, timeout=60)
    if r.status_code >= 400:
        print(f"  ! GET {path} -> {r.status_code}: {r.text[:400]}")
        return None
    return r.json()


def post(path, body):
    r = SESSION.post(API + path, json=body, timeout=60)
    ok = r.status_code < 400
    detail = "" if ok else f": {r.text[:400]}"
    print(f"  POST {path} -> {r.status_code}{detail}")
    return ok


def patch(path, body):
    r = SESSION.patch(API + path, json=body, timeout=60)
    ok = r.status_code < 400
    detail = "" if ok else f": {r.text[:400]}"
    print(f"  PATCH {path} -> {r.status_code}{detail}")
    return ok


def main():
    bundle = os.environ.get("BUNDLE_ID", "")
    apps = get("/v1/apps", **{"filter[bundleId]": bundle})
    if not apps or not apps["data"]:
        print(f"No app found for bundle ID {bundle!r}.")
        sys.exit(1)
    app = apps["data"][0]
    app_id = app["id"]
    print(f"App: {app['attributes']['name']} ({bundle}) id={app_id}")

    print("\n== Team users (internal testers must be one of these Apple IDs) ==")
    users = get("/v1/users", limit=50) or {"data": []}
    user_ids = set()
    for u in users["data"]:
        a = u["attributes"]
        user_ids.add((a.get("username") or "").lower())
        print(f"  {mask(a.get('username'))}  roles={','.join(a.get('roles') or [])}"
              f"  allApps={a.get('allAppsVisible')}")

    print("\n== Recent builds ==")
    builds = get("/v1/builds", **{"filter[app]": app_id, "sort": "-uploadedDate", "limit": 5,
                                  "include": "buildBetaDetail,preReleaseVersion"}) or {"data": [], "included": []}
    details = {i["id"]: i["attributes"] for i in builds.get("included", []) if i["type"] == "buildBetaDetails"}
    versions = {i["id"]: i["attributes"].get("version") for i in builds.get("included", [])
                if i["type"] == "preReleaseVersions"}
    latest = None
    for b in builds["data"]:
        a = b["attributes"]
        rel = b.get("relationships", {})
        d_id = (rel.get("buildBetaDetail", {}).get("data") or {}).get("id")
        v_id = (rel.get("preReleaseVersion", {}).get("data") or {}).get("id")
        d = details.get(d_id, {})
        print(f"  {versions.get(v_id)} ({a.get('version')}) processing={a.get('processingState')} "
              f"expired={a.get('expired')} minOS={a.get('minOsVersion')} "
              f"encryption={a.get('usesNonExemptEncryption')} internal={d.get('internalBuildState')} "
              f"external={d.get('externalBuildState')} autoNotify={d.get('autoNotifyEnabled')}")
        if latest is None:
            latest = (b["id"], d_id, d)

    print("\n== Beta groups ==")
    groups = get(f"/v1/apps/{app_id}/betaGroups", limit=50) or {"data": []}
    for g in groups["data"]:
        a = g["attributes"]
        gb = get(f"/v1/betaGroups/{g['id']}/builds", limit=10) or {"data": []}
        print(f"  {a.get('name')!r} internal={a.get('isInternalGroup')} allBuilds={a.get('hasAccessToAllBuilds')} "
              f"publicLink={a.get('publicLinkEnabled')} builds={[x['attributes'].get('version') for x in gb['data']]}")

    print("\n== Testers ==")
    testers = get("/v1/betaTesters", **{"filter[apps]": app_id, "limit": 50}) or {"data": []}
    for t in testers["data"]:
        a = t["attributes"]
        email = (a.get("email") or "").lower()
        is_user = email in user_ids
        print(f"  {mask(email)} state={a.get('state')} inviteType={a.get('inviteType')} "
              f"matchesTeamUserAppleID={is_user}")
        if not is_user:
            print("    -> This email is not the Apple ID of any team user, so as an INTERNAL tester it can't "
                  "receive the build. Add the user's Apple ID instead, or test externally.")

    print("\n== Fixes ==")
    if latest and latest[1] and latest[2].get("autoNotifyEnabled") is False:
        print("Turning on tester notifications for the latest build")
        patch(f"/v1/buildBetaDetails/{latest[1]}",
              {"data": {"type": "buildBetaDetails", "id": latest[1], "attributes": {"autoNotifyEnabled": True}}})
    for t in testers["data"]:
        if t["attributes"].get("state") in ("INVITED", "NOT_INVITED", None):
            print(f"Re-sending invitation to {mask(t['attributes'].get('email'))}")
            post("/v1/betaTesterInvitations", {"data": {
                "type": "betaTesterInvitations",
                "relationships": {
                    "app": {"data": {"type": "apps", "id": app_id}},
                    "betaTester": {"data": {"type": "betaTesters", "id": t["id"]}},
                },
            }})
    if latest:
        print("Notifying testers about the latest build")
        post("/v1/buildBetaNotifications", {"data": {
            "type": "buildBetaNotifications",
            "relationships": {"build": {"data": {"type": "builds", "id": latest[0]}}},
        }})


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
from __future__ import annotations

"""Build the bundled Paris seed from the raw specialtycoffee.paris extract.

Reads docs/seed-paris (the extract, score included) and Annexe D of the PRD.
Writes the two bundle files, without the editorial score:

  Kohi/Resources/Reference/roasters-seed.json
  Kohi/Resources/Reference/places-paris.json

Re-run by hand before a build. Diff on id, and keep additions, closures and
website changes. Nothing here is marked verified.

  python3 Tools/SeedParis/build.py
"""

import json
import re
import sys
import unicodedata
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[2]
RAW_ROASTERS = ROOT / "docs/seed-paris/roasters-paris-seed.json"
RAW_PLACES = ROOT / "docs/seed-paris/places-paris-seed.json"
PRD = ROOT / "docs/kohi-prd-v1.md"
OUT_ROASTERS = ROOT / "Kohi/Resources/Reference/roasters-seed.json"
OUT_PLACES = ROOT / "Kohi/Resources/Reference/places-paris.json"
COORDINATES = ROOT / "docs/seed-paris/places-coordinates.json"
# Below this the BAN hit is a guess. The app geocodes the rest on device.
COORDINATE_FLOOR = 0.5

# Same noise list as Roaster.fold, including the words added for this seed.
NOISE = {
    "roasters", "roaster", "roastery", "roasting", "coffee", "coffees",
    "cafe", "brulerie", "torrefaction", "the", "co", "company", "and",
    "torrefacteur", "torrefacteurs", "cafes",
}

# Graphies that do not fold onto the Paris row. The value is the Paris slug.
FORCE_SLUG = {
    "Tanat (ex-Kawa)": "tanat",
    "Partisan Café Artisanal": "partisan",
    "Five Elephant": "five-elephants",
}

# Industrial, not specialty. Dropped from both files.
EXCLUDED = {"illy", "hausbrandt"}

COUNTRIES = {
    "FR": "France",
    "NO": "Norway",
    "DK": "Denmark",
    "SE": "Sweden",
    "FI": "Finland",
    "DE": "Germany",
    "NL": "Netherlands",
    "BE": "Belgium",
    "ES": "Spain",
    "IT": "Italy",
    "UK": "United Kingdom",
    "IE": "Ireland",
    "CH": "Switzerland",
    "AT": "Austria",
    "GR": "Greece",
    "PT": "Portugal",
    "CZ": "Czechia",
    "PL": "Poland",
}


def fold(value: str) -> str:
    stripped = unicodedata.normalize("NFD", value)
    stripped = "".join(c for c in stripped if unicodedata.category(c) != "Mn")
    stripped = stripped.lower()
    stripped = re.sub(r"[^a-z0-9]+", " ", stripped).strip()
    words = [word for word in stripped.split() if word and word not in NOISE]
    if not words:
        return stripped.replace(" ", "")
    return "".join(words)


def slugify(value: str) -> str:
    text = unicodedata.normalize("NFD", value)
    text = "".join(c for c in text if unicodedata.category(c) != "Mn")
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", "-", text).strip("-")
    return text or "roaster"


def domain(url: str | None) -> str:
    if not url:
        return ""
    host = (urlparse(url).netloc or "").lower()
    if host.startswith("www."):
        host = host[4:]
    if not host or "instagram.com" in host:
        return ""
    return host


def clean(value: str | None) -> str | None:
    if value is None:
        return None
    text = value.strip()
    return text or None


def load_annexe_d() -> list[dict]:
    text = PRD.read_text(encoding="utf-8")
    start = text.index("## Annexe D")
    end = text.index("## Annexe E")
    rows = []
    for line in text[start:end].splitlines():
        if not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) < 5 or cells[0].startswith("-") or cells[0] == "Torréfacteur":
            continue
        rows.append({
            "name": cells[0],
            "city": cells[1],
            "country": COUNTRIES[cells[2]],
            "mention": cells[3],
            "status": cells[4],
        })
    if len(rows) < 70:
        sys.exit(f"Annexe D parse looks short: {len(rows)} rows")
    return rows


def blank(slug: str, name: str, country: str, city: str, note: str = "") -> dict:
    return {
        "slug": slug,
        "name": name,
        "country": country,
        "city": city,
        "website": None,
        "instagram": None,
        "parisShopsServed": 0,
        "ownShopIDs": [],
        "aliases": [],
        "sources": [],
        "status": "",
        "note": note,
        "fetchedAt": "",
    }


def from_paris(item: dict) -> dict:
    city = "Paris" if item["ownShopsInParis"] > 0 else ""
    row = blank(item["id"], item["name"], item["countryName"], city, item.get("note") or "")
    row["website"] = clean(item.get("website"))
    row["instagram"] = clean(item.get("instagram"))
    row["parisShopsServed"] = item["parisShopsServed"]
    row["ownShopIDs"] = list(item.get("ownShopIds") or [])
    row["sources"] = ["specialtyCoffeeParis"]
    row["status"] = item["status"]
    row["fetchedAt"] = item["fetchedAt"]
    return row


def add_alias(row: dict, alias: str) -> None:
    if alias and alias != row["name"] and alias not in row["aliases"]:
        row["aliases"].append(alias)


def merge_annexe(row: dict, annexe: dict) -> None:
    if "annexeD" not in row["sources"]:
        row["sources"].append("annexeD")
    row["status"] = "partiel (deux sources)"
    if not row["city"] and annexe["city"]:
        row["city"] = annexe["city"]
    elif annexe["city"] and row["city"] == "Paris" and annexe["city"] != "Paris":
        # A foreign roaster served in Paris keeps its home city from Annexe D.
        # "Paris" here only meant "has a shop", which ownShopIDs already says.
        if row["parisShopsServed"] and row["ownShopIDs"]:
            pass
        else:
            row["city"] = annexe["city"]
    add_alias(row, annexe["name"])


def build_roasters(paris_items: list[dict], annexe_rows: list[dict]) -> list[dict]:
    rows = [from_paris(item) for item in paris_items if item["id"] not in EXCLUDED]
    by_slug = {row["slug"]: row for row in rows}
    by_fold = {fold(row["name"]): row["slug"] for row in rows}

    for annexe in annexe_rows:
        raw = annexe["name"]
        if raw in FORCE_SLUG:
            row = by_slug[FORCE_SLUG[raw]]
            merge_annexe(row, annexe)
            continue
        if raw.startswith("Kawa ("):
            annexe = {**annexe, "name": "Kawa"}
            raw = "Kawa"
        key = fold(raw)
        slug = by_fold.get(key)
        if slug:
            merge_annexe(by_slug[slug], annexe)
            continue
        slug = slugify(raw)
        if slug in by_slug:
            slug = f"{slug}-annexe"
        row = blank(slug, raw, annexe["country"], annexe["city"])
        if raw == "Kawa":
            row["note"] = "si distinct de Tanat"
        row["sources"] = ["annexeD"]
        row["status"] = "à vérifier (Annexe D)"
        rows.append(row)
        by_slug[slug] = row
        by_fold[key] = slug
    return rows


def check(roasters: list[dict], places: list[dict]) -> None:
    errors = []
    owners: dict[str, str] = {}
    for row in roasters:
        if "vérifié" in row["status"]:
            errors.append(f"status must not say vérifié: {row['slug']}")
        for label in [row["name"], *row["aliases"]]:
            key = fold(label)
            if not key:
                continue
            previous = owners.get(key)
            if previous and previous != row["slug"]:
                errors.append(f"fold {key!r} is both {previous} and {row['slug']}")
            owners[key] = row["slug"]
        host = domain(row["website"])
        if host:
            key = f"domain:{host}"
            previous = owners.get(key)
            if previous and previous != row["slug"]:
                errors.append(f"{host} is both {previous} and {row['slug']}")
            owners[key] = row["slug"]

    slugs = {row["slug"] for row in roasters}
    if EXCLUDED & slugs:
        errors.append(f"excluded slugs still present: {EXCLUDED & slugs}")
    for place in places:
        missing = [rid for rid in place["roasterIDs"] if rid not in slugs]
        if missing:
            errors.append(f"{place['id']} points at {missing}")
        if "siteScore" in place:
            errors.append(f"{place['id']} still has siteScore")
    if errors:
        sys.exit("seed check failed:\n" + "\n".join(errors))


def apply_coordinates(places: list[dict]) -> None:
    """Copy a confident BAN hit onto the place. Missing file: leave them off."""
    if not COORDINATES.exists():
        return
    found = json.loads(COORDINATES.read_text(encoding="utf-8"))
    kept = 0
    for place in places:
        hit = found.get(place["id"])
        if not hit or hit.get("score", 0) < COORDINATE_FLOOR:
            continue
        place["latitude"] = hit["latitude"]
        place["longitude"] = hit["longitude"]
        kept += 1
    print(f"{kept} places with coordinates")


def main() -> None:
    paris = json.loads(RAW_ROASTERS.read_text(encoding="utf-8"))["items"]
    raw_places = json.loads(RAW_PLACES.read_text(encoding="utf-8"))["items"]
    annexe = load_annexe_d()
    roasters = build_roasters(paris, annexe)

    places = []
    for item in raw_places:
        roaster_ids = [rid for rid in item["roasterIds"] if rid not in EXCLUDED]
        places.append({
            "id": item["id"],
            "name": item["name"],
            "brand": item["brand"],
            "address": item["address"],
            "postalCode": str(item["postalCode"]),
            "arrondissement": item["arrondissement"],
            "city": item["city"],
            "roasterIDs": roaster_ids,
            "status": item["status"],
            "closedOn": clean(item.get("closedOn")),
            "fetchedAt": item["fetchedAt"],
        })

    apply_coordinates(places)
    check(roasters, places)

    for path, payload in ((OUT_ROASTERS, roasters), (OUT_PLACES, places)):
        path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    merged = sum(1 for row in roasters if row["sources"] == ["specialtyCoffeeParis", "annexeD"])
    annexe_only = sum(1 for row in roasters if row["sources"] == ["annexeD"])
    paris_only = sum(1 for row in roasters if row["sources"] == ["specialtyCoffeeParis"])
    print(
        f"{len(roasters)} roasters "
        f"({paris_only} paris, {merged} merged, {annexe_only} annexe D only), "
        f"{len(places)} places"
    )


if __name__ == "__main__":
    main()

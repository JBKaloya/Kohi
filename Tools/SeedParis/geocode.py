#!/usr/bin/env python3
"""Geocode the Paris seed once, through the Base Adresse Nationale.

Writes docs/seed-paris/places-coordinates.json. build.py copies a hit into
the bundle when its score is at least 0.5. Re-run by hand; the app never
calls this.

  python3 Tools/SeedParis/geocode.py
"""

from __future__ import annotations

import csv
import io
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLACES = ROOT / "Kohi/Resources/Reference/places-paris.json"
OUT = ROOT / "docs/seed-paris/places-coordinates.json"


def main() -> None:
    places = json.loads(PLACES.read_text(encoding="utf-8"))
    buffer = io.StringIO()
    writer = csv.DictWriter(buffer, fieldnames=["id", "address", "postcode"])
    writer.writeheader()
    for place in places:
        address = place["address"].strip()
        city = place.get("city") or "Paris"
        writer.writerow({
            "id": place["id"],
            "address": f"{address}, {city}",
            "postcode": place.get("postalCode") or "",
        })

    csv_path = OUT.with_suffix(".request.csv")
    csv_path.write_text(buffer.getvalue(), encoding="utf-8")
    completed = subprocess.run(
        [
            "curl", "-sS", "-X", "POST",
            "-F", f"data=@{csv_path}",
            "-F", "columns=address",
            "-F", "postcode=postcode",
            "https://api-adresse.data.gouv.fr/search/csv/",
        ],
        check=True,
        capture_output=True,
    )
    csv_path.unlink(missing_ok=True)
    text = completed.stdout.decode("utf-8")
    rows = csv.DictReader(io.StringIO(text))
    found: dict[str, dict[str, float]] = {}
    missed: list[str] = []
    for row in rows:
        place_id = row.get("id") or ""
        try:
            latitude = float(row["latitude"])
            longitude = float(row["longitude"])
            score = float(row["result_score"])
        except (KeyError, TypeError, ValueError):
            missed.append(place_id)
            continue
        found[place_id] = {
            "latitude": latitude,
            "longitude": longitude,
            "score": score,
        }

    OUT.write_text(
        json.dumps(found, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    weak = sum(1 for hit in found.values() if hit["score"] < 0.5)
    print(f"{len(found)} geocoded, {weak} below 0.5, {len(missed)} missed")
    if missed:
        print("missed:", ", ".join(missed[:20]))


if __name__ == "__main__":
    main()

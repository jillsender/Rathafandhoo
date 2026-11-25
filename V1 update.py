"""
build_rathafandhoo_zip.py

Generates a clean, ready-to-use ZIP archive (`my-rathafandhoo-portal.zip`)
containing the standalone `index.html` application and a `README.md` guide
for GDh. Rathafandhoo.

Usage:
    python build_rathafandhoo_zip.py
"""

import os
import sys
import zipfile
from pathlib import Path


README_CONTENT = """# My Rathafandhoo (މައި ރަތަފަންދޫ) — Portal Package

A bilingual (Dhivehi RTL in Faruma font & English LTR in Inter/Plus Jakarta Sans)
community portal for **GDh. Rathafandhoo**, Huvadhu Atoll, Maldives.

## Included Features
- **Unified Top Navigation Banner**: Switch between Island Overview, Community & News,
  Politics & Polls, Family Tree, and the RBAC Studio, plus live Role & Language switching.
- **Full-Width Lagoon Hero Video**: Looping tropical lagoon video with poster/image fallback.
- **Political & Civic Polls**: Vote on local council, regional transport, and national policy topics.
- **Top & Side Ad Slots**: Dismissible top leaderboard banner and sticky side ad cards.
- **Interactive Family Tree**: Multi-generation lineage tree, SVG relationship lines, house directory,
  photo upload/zoom, and JSON export/import.

## How to Run Locally
Open `index.html` directly in any modern web browser, or serve the folder with a local server:

```bash
python -m http.server 8080
```
Then visit `http://localhost:8080` in your browser.
"""


def find_source_html() -> Path:
    """Locate index.html in the current working directory."""
    candidate = Path.cwd() / "index.html"
    if candidate.is_file():
        return candidate
    raise FileNotFoundError(
        "Could not find 'index.html' in the current directory. "
        "Make sure 'index.html' is saved in the same folder before running this script."
    )


def create_portal_zip(html_path: Path, output_zip: Path) -> Path:
    """Write index.html and README.md into a compressed ZIP archive."""
    try:
        with zipfile.ZipFile(output_zip, mode="w", compression=zipfile.ZIP_DEFLATED) as zf:
            zf.write(html_path, arcname="index.html")
            zf.writestr("README.md", README_CONTENT)
        return output_zip.resolve()
    except OSError as exc:
        raise RuntimeError(f"Failed to write ZIP file '{output_zip}': {exc}") from exc


def main() -> int:
    """Entry point for building the ZIP file."""
    try:
        html_file = find_source_html()
        zip_path = Path.cwd() / "my-rathafandhoo-portal.zip"
        created_path = create_portal_zip(html_file, zip_path)
        size_kb = created_path.stat().st_size / 1024
        print(f"Successfully created ZIP archive: {created_path} ({size_kb:.1f} KB)")
        return 0
    except Exception as error:
        print(f"Error building ZIP archive: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
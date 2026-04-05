"""
getUCLA_SR_BRB.py
Downloads WUS UCLA Snow Reanalysis (WUS_UCLA_SR v01) NetCDF tiles
covering the Boise River Basin from NASA Earthdata Cloud (NSIDC DAAC).

Dataset:   https://nsidc.org/data/wus_ucla_sr/versions/1
Resolution: 16 arc-second (~500 m), daily, WY1985-2021
Variables:  SWE, fSCA, snow depth (SD)
Dimensions per tile: [225 x 225 x 5 x 366]
    lat x lon x ensemble_stats x day_of_WY
    ensemble_stats: 1=mean, 2=std, 3=25th pctl, 4=50th pctl (median), 5=75th pctl

Requirements
------------
    pip install earthaccess
    NASA Earthdata Login: https://urs.earthdata.nasa.gov
    "NSIDC_DATAPOOL_OPS" app authorized in your Earthdata profile

HP Marshall, Boise State University
Created: April 2026
"""

from __future__ import annotations

import os
import sys
import pathlib

# ---------------------------------------------------------------------------
# User configuration
# ---------------------------------------------------------------------------

# Water year to download (dataset covers WY1985 – WY2021).
# WY2021 = Oct 1 2020 – Sep 30 2021  →  water_year_start=2020, wy_end_2digit=21
WATER_YEAR_START: int = 2020   # calendar year of Oct 1
WY_END_2DIGIT:    int = 21     # 2-digit end year

# Output directory — keep large files out of the git repo.
DATA_ROOT: pathlib.Path = pathlib.Path("/Users/hpmarshall/DATA_DRIVE/SnowFusion")
OUT_DIR:   pathlib.Path = DATA_ROOT / "UCLA_SR"

# BRB approximate extent:  lat [43.0, 44.5],  lon [-116.3, -114.3]
# Tiles are 1° × 1°, named by their lower-left corner.
LAT_TILES: list[int] = [43, 44]        # lower-left latitude of each tile
LON_TILES: list[int] = [115, 116, 117] # lower-left west longitude (positive)

# Minimum file size to be considered a valid download (bytes)
MIN_VALID_BYTES: int = 1_000_000  # 1 MB


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_wy_str(wy_start: int, wy_end_2digit: int) -> str:
    """Return the water-year string used in UCLA filenames, e.g. 'WY2020_21'."""
    return f"WY{wy_start}_{wy_end_2digit:02d}"


def _tile_str(lat: int, lon_w: int) -> str:
    """Return the tile identifier embedded in UCLA filenames, e.g. 'N43_0W115_0'."""
    return f"N{lat}_0W{lon_w}_0"


def _expected_filenames(
    lat_tiles: list[int],
    lon_tiles: list[int],
    wy_str: str,
) -> dict[str, list[str]]:
    """Return {tile_id: [swe_sca_filename, sd_filename]} for every tile."""
    files: dict[str, list[str]] = {}
    for lat in lat_tiles:
        for lon in lon_tiles:
            tid = _tile_str(lat, lon)
            swe_sca = f"WUS_UCLA_SR_v01_{tid}_agg_16_{wy_str}_SWE_SCA_POST.nc"
            sd      = f"WUS_UCLA_SR_v01_{tid}_agg_16_{wy_str}_SD_POST.nc"
            files[tid] = [swe_sca, sd]
    return files


def _check_existing(
    out_dir: pathlib.Path,
    tile_files: dict[str, list[str]],
) -> tuple[int, int]:
    """Return (existing_count, total_count) of valid files already on disk."""
    total    = sum(len(v) for v in tile_files.values())
    existing = 0
    for fnames in tile_files.values():
        for fname in fnames:
            fpath = out_dir / fname
            if fpath.exists() and fpath.stat().st_size > MIN_VALID_BYTES:
                print(f"  Already have: {fname}  "
                      f"({fpath.stat().st_size / 1e6:.1f} MB)")
                existing += 1
    return existing, total


# ---------------------------------------------------------------------------
# Download via earthaccess
# ---------------------------------------------------------------------------

def _download(
    out_dir: pathlib.Path,
    tile_ids: list[str],
    wy_str: str,
    tile_files: dict[str, list[str]],
) -> None:
    """Search for and download all missing tiles using earthaccess."""
    try:
        import earthaccess
    except ImportError:
        sys.exit(
            "earthaccess is not installed.\n"
            "Install with:  pip install earthaccess\n"
            "Then re-run this script."
        )

    # ---- Authenticate ----
    print("Logging into Earthdata...")
    try:
        from earthdata_credentials import ensure_earthdata_credentials
        ensure_earthdata_credentials()          # writes ~/.netrc if needed
        auth = earthaccess.login(strategy="netrc")
    except Exception:
        # Fall back to interactive login
        auth = earthaccess.login(strategy="interactive")

    if not auth.authenticated:
        sys.exit("ERROR: Earthdata authentication failed.\n"
                 "Check credentials at https://urs.earthdata.nasa.gov")
    print("  Authenticated successfully.")

    # ---- Search ----
    print("\nSearching for WUS_UCLA_SR granules (BRB bounding box)...")
    results = []
    try:
        results = earthaccess.search_data(
            short_name="WUS_UCLA_SR",
            bounding_box=(-117, 43, -114, 45),
            count=2000,
        )
        print(f"  Found {len(results)} granules.")
    except Exception as exc:
        print(f"  Bounding-box search failed ({exc}); retrying without bbox...")

    if not results:
        try:
            results = earthaccess.search_data(short_name="WUS_UCLA_SR", count=2000)
            print(f"  Found {len(results)} granules (no bbox filter).")
        except Exception as exc:
            sys.exit(f"ERROR: earthaccess search failed: {exc}")

    if not results:
        _diagnose_no_results()
        sys.exit("ERROR: No granules found for WUS_UCLA_SR.")

    # ---- Filter for our WY + tiles ----
    print(f"\nFiltering for {wy_str} and BRB tiles...")
    granules_to_download: list = []
    already_queued_files: set[str] = set()

    for granule in results:
        try:
            links = granule.data_links(access="external") or granule.data_links()
        except Exception as exc:
            print(f"  Warning: could not inspect granule links: {exc}")
            continue

        for link in links:
            fname = link.rsplit("/", 1)[-1]
            if wy_str not in fname or not fname.endswith(".nc"):
                continue
            for tid in tile_ids:
                if tid in fname:
                    fpath = out_dir / fname
                    if fpath.exists() and fpath.stat().st_size > MIN_VALID_BYTES:
                        print(f"  SKIP (exists): {fname}")
                    elif fname not in already_queued_files:
                        print(f"  QUEUE: {fname}")
                        granules_to_download.append(granule)
                        already_queued_files.add(fname)
                    break

    print(f"\nQueued {len(granules_to_download)} granule(s) for download.")

    if not granules_to_download:
        if already_queued_files:
            print("All matched files already exist on disk.")
        else:
            _show_sample_filenames(results)
        return

    # ---- Download ----
    print(f"\nDownloading to: {out_dir}")
    try:
        downloaded = earthaccess.download(granules_to_download, str(out_dir))
    except Exception as exc:
        sys.exit(f"ERROR: download failed: {exc}")

    print(f"\nDownloaded {len(downloaded)} file(s):")
    for fpath in downloaded:
        fpath = pathlib.Path(fpath)
        size_mb = fpath.stat().st_size / 1e6 if fpath.exists() else 0
        print(f"  DOWNLOADED: {fpath.name}  ({size_mb:.1f} MB)")


def _diagnose_no_results() -> None:
    """Print collection-level debugging info when no granules are found."""
    try:
        import earthaccess
        collections = earthaccess.search_datasets(short_name="WUS_UCLA_SR")
        print(f"  Collections found: {len(collections)}")
        for col in collections:
            cid  = col["meta"]["concept-id"]
            name = col["umm"]["ShortName"]
            ver  = col["umm"].get("Version", "?")
            print(f"    - {cid}: {name} v{ver}")
            for url_entry in col["umm"].get("RelatedUrls", [])[:5]:
                print(f"      URL: {url_entry.get('URL', '?')}  "
                      f"({url_entry.get('Type', '?')})")
    except Exception as exc:
        print(f"  Could not query collections: {exc}")


def _show_sample_filenames(results: list, n: int = 10) -> None:
    """Print a sample of filenames found to help diagnose naming mismatches."""
    print("WARNING: No files matched our tile/WY criteria.")
    print(f"Listing first {n} .nc filenames found for debugging:")
    shown = 0
    for granule in results:
        if shown >= n:
            break
        try:
            links = granule.data_links(access="external") or granule.data_links()
            for link in links:
                fname = link.rsplit("/", 1)[-1]
                if fname.endswith(".nc"):
                    print(f"  {fname}")
                    print(f"    {link}")
                    shown += 1
                    break
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------

def _verify_downloads(out_dir: pathlib.Path) -> int:
    """Print a summary of valid NetCDF files and inspect the first one found."""
    import netCDF4  # type: ignore

    nc_files = sorted(out_dir.glob("*SWE_SCA_POST*.nc"))
    print(f"\n=== Download Summary ===")
    print(f"NetCDF files in {out_dir}:")

    valid: list[pathlib.Path] = []
    for fp in nc_files:
        size = fp.stat().st_size
        if size > MIN_VALID_BYTES:
            print(f"  {fp.name}  ({size / 1e6:.1f} MB)")
            valid.append(fp)
        else:
            print(f"  {fp.name}  ({size} bytes — INVALID)")

    print(f"Valid NetCDF files: {len(valid)}")

    # Quick structure peek at the first valid file
    if valid:
        fp = valid[0]
        print(f"\n=== NetCDF File Structure ===")
        print(f"File: {fp.name}")
        with netCDF4.Dataset(fp) as ds:
            print("Variables:")
            for vname, var in ds.variables.items():
                dim_str = " x ".join(
                    f"{d}={ds.dimensions[d].size}" for d in var.dimensions
                )
                print(f"  {vname} [{dim_str}]")

    return len(valid)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    wy_str    = _make_wy_str(WATER_YEAR_START, WY_END_2DIGIT)
    tile_ids  = [_tile_str(lat, lon) for lat in LAT_TILES for lon in LON_TILES]
    tile_files = _expected_filenames(LAT_TILES, LON_TILES, wy_str)
    n_tiles    = len(tile_ids)

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print("\n=== WUS UCLA Snow Reanalysis Downloader ===")
    print(f"Water Year : {wy_str}")
    print(f"Tiles needed: {n_tiles}  "
          f"(lat: {LAT_TILES},  lon: {LON_TILES})")
    print(f"Output     : {OUT_DIR}\n")

    # ---- Check existing files ----
    existing, total = _check_existing(OUT_DIR, tile_files)

    if existing >= total:
        print(f"\nAll {total} files already downloaded. Skipping download.")
    else:
        print(f"\nHave {existing} of {total} files. "
              f"Need to download {total - existing} more.")
        _download(OUT_DIR, tile_ids, wy_str, tile_files)

    # ---- Verify ----
    valid_count = _verify_downloads(OUT_DIR)

    if valid_count == 0:
        print("\n============================================")
        print("AUTOMATED DOWNLOAD COULD NOT FIND FILES")
        print("============================================")
        print("Please download manually:")
        print("  1. Go to: https://nsidc.org/data/data-access-tool/WUS_UCLA_SR/versions/1")
        print("  2. Set bounding box to: lat [43, 45], lon [-117, -114]")
        print(f"  3. Select water year: {wy_str}")
        print(f"  4. Download the .nc files to: {OUT_DIR}")
        print("  5. Then run getUCLA_SWE.py to load and process the data")
        print("============================================")
    else:
        print("\nDone! Run getUCLA_SWE.py to load and process the data.")


if __name__ == "__main__":
    main()

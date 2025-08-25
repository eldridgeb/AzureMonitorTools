# Azure New Subscriptions Example

Small example script to detect newly created Azure subscriptions from tenant-level activity logs using the Azure REST API.

Purpose
- Query tenant activity logs and extract events where `eventName.value == "Create"`.
- Save deduplicated `.properties` for those events to `new_subs.json` and print a count.

Prerequisites
- Azure CLI installed and authenticated (the script calls `az rest`).
- `jq` installed for JSON filtering.
- A POSIX-compatible Bash shell with GNU `date` (Linux, macOS, WSL or Git Bash on Windows).

Usage
- Default (last 1 hour): `./azure-new-subs.sh`
- Specify lookback hours: `./azure-new-subs.sh 6`
- Or via env var: `HOURS_AGO=24 ./azure-new-subs.sh`

Output
- Creates `new_subs.json` in the working directory containing the deduplicated subscription create event properties.

Notes
- On Windows PowerShell, run the script from WSL or Git Bash (the `date -u -d` syntax requires GNU date).
- For automated/non-interactive use, authenticate with a service principal and ensure it has permission to read tenant activity logs.

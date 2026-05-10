#!/usr/bin/env bash
set -euo pipefail

if ! command -v dotnet >/dev/null 2>&1; then
  echo "dotnet is not installed or not on PATH. Run this script inside the dev container." >&2
  exit 1
fi

echo "==> dotnet --version"
dotnet --version

echo "==> dotnet restore DocumentCatalogIndexer.slnx"
dotnet restore DocumentCatalogIndexer.slnx

echo "==> dotnet build DocumentCatalogIndexer.slnx --configuration Release --no-restore"
dotnet build DocumentCatalogIndexer.slnx --configuration Release --no-restore

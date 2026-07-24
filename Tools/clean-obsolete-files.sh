#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
obsolete_files=(
  "RoomSurveyElectrical/SmartProjectEmbedding.swift"
)

for relative_path in "${obsolete_files[@]}"; do
  full_path="$repo_root/$relative_path"
  if [[ -e "$full_path" ]]; then
    rm -f "$full_path"
    echo "Removed obsolete file: $relative_path"
  else
    echo "Already clean: $relative_path"
  fi
done

echo 'Obsolete source cleanup completed.'

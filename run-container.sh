#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Run the reproducibility package in its pinned R 4.3.2 container.

Usage:
  ./run-container.sh --source-tests
  ./run-container.sh --audit-source
  ./run-container.sh [reproduce.R options]

Examples:
  ./run-container.sh --synthetic --cores 2
  ./run-container.sh --data-dir ~/private/optionmetrics --check-inputs
  ./run-container.sh --data-dir ~/private/optionmetrics --mode paper-vintage --cores 8

The host directory supplied to --data-dir is mounted read-only at
/optionmetrics inside the container. Generated work and outputs are written to
the repository's ignored work/ and outputs/ directories.
EOF
}

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not available inside WSL2. Install Docker with WSL2 integration and retry." >&2
  exit 1
fi

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
image_name="option-portfolio-selection-repro:4.3.2"
operation="reproduce"
data_directory=""
container_arguments=()

while (($#)); do
  case "$1" in
    --source-tests)
      if [[ "$operation" != "reproduce" || ${#container_arguments[@]} -ne 0 || -n "$data_directory" ]]; then
        echo "--source-tests must be used by itself." >&2
        exit 2
      fi
      operation="source-tests"
      shift
      ;;
    --audit-source)
      if [[ "$operation" != "reproduce" || ${#container_arguments[@]} -ne 0 || -n "$data_directory" ]]; then
        echo "--audit-source must be used by itself." >&2
        exit 2
      fi
      operation="audit-source"
      shift
      ;;
    --container-help)
      usage
      exit 0
      ;;
    --data-dir)
      if (($# < 2)); then
        echo "Missing directory after --data-dir." >&2
        exit 2
      fi
      if [[ ! -d "$2" ]]; then
        echo "OptionMetrics directory does not exist: $2" >&2
        exit 2
      fi
      data_directory="$(cd -- "$2" && pwd -P)"
      container_arguments+=("--data-dir" "/optionmetrics")
      shift 2
      ;;
    --config)
      echo "The container launcher intentionally uses --data-dir. Use --data-dir with --mode paper-vintage or current-vintage instead of a host-specific configuration file." >&2
      exit 2
      ;;
    *)
      container_arguments+=("$1")
      shift
      ;;
  esac
done

if [[ "$operation" != "reproduce" && ${#container_arguments[@]} -ne 0 ]]; then
  echo "The selected maintenance operation cannot be combined with reproduce.R options." >&2
  exit 2
fi

docker build --pull --tag "$image_name" "$script_directory"

docker_arguments=(
  run
  --rm
  --init
  --user "$(id -u):$(id -g)"
  --env HOME=/tmp
  --env RENV_PATHS_CACHE=/project/renv/cache
  --env RENV_PATHS_ROOT=/project/renv/local
  --mount "type=bind,src=${script_directory},dst=/project"
  --workdir /project
  --security-opt no-new-privileges
)

if [[ -n "$data_directory" ]]; then
  docker_arguments+=(--mount "type=bind,src=${data_directory},dst=/optionmetrics,readonly")
fi

case "$operation" in
  source-tests)
    command=(Rscript tests/run_tests.R)
    ;;
  audit-source)
    command=(Rscript src/scripts/07_audit_public_tree.R)
    ;;
  reproduce)
    command=(Rscript reproduce.R "${container_arguments[@]}")
    ;;
esac

docker "${docker_arguments[@]}" "$image_name" "${command[@]}"

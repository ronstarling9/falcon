#!/usr/bin/env bash
# Regenerate committed diagram renders from their PlantUML sources.
# Requires: java, graphviz (dot), and plantuml.jar (PLANTUML_JAR or ./plantuml.jar).
set -euo pipefail

JAR="${PLANTUML_JAR:-plantuml.jar}"
[ -f "$JAR" ] || { echo "plantuml.jar not found; set PLANTUML_JAR" >&2; exit 1; }
command -v dot >/dev/null || { echo "graphviz 'dot' not found" >&2; exit 1; }

cd "$(dirname "$0")/.."
for fmt in svg png; do
  java -jar "$JAR" -t"$fmt" -o "$PWD/docs" docs/deployment.puml
done
echo "regenerated docs/falcon-deployment.{svg,png}"

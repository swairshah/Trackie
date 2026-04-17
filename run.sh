#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_PATH=".build/Trackie.app"
APP_BIN="$APP_PATH/Contents/MacOS/Trackie"
CLI_BIN="$APP_PATH/Contents/MacOS/trackiectl"
BROKER_PORT=27182

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Trackie build & run ===${NC}"

# Kill any existing instance so the broker port is free.
pkill -f "$APP_BIN" 2>/dev/null || true
sleep 0.3

echo -e "${YELLOW}Building (debug)...${NC}"
swift build --product Trackie
swift build --product trackiectl

# First-time bundle build (or rebuild if missing).
if [ ! -d "$APP_PATH" ]; then
    echo -e "${YELLOW}Creating app bundle...${NC}"
    ./scripts/build-app.sh
else
    # Replace binaries with fresh debug builds; leave bundle layout as-is.
    cp .build/debug/Trackie "$APP_BIN"
    cp .build/debug/trackiectl "$CLI_BIN"
fi

# Keep CLI on PATH if ~/.local/bin exists.
if [ -d "$HOME/.local/bin" ]; then
    cp .build/debug/trackiectl "$HOME/.local/bin/trackie"
    chmod +x "$HOME/.local/bin/trackie"
    echo -e "${GREEN}installed CLI: ~/.local/bin/trackie${NC}"
fi

echo -e "${GREEN}Launching Trackie...${NC}"
open "$APP_PATH"

# Poll for the broker to come up. Cold launches can take a few seconds,
# particularly the first time after the bundle is rebuilt.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if nc -z 127.0.0.1 $BROKER_PORT >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done

if pgrep -f "$APP_BIN" >/dev/null; then
    echo -e "${GREEN}Trackie process: running${NC}"
else
    echo -e "${RED}Trackie process: not running${NC}"
fi

if nc -z 127.0.0.1 $BROKER_PORT >/dev/null 2>&1; then
    echo -e "${GREEN}Broker ($BROKER_PORT): listening${NC}"
    if "$CLI_BIN" ping >/dev/null 2>&1; then
        echo -e "${GREEN}CLI ↔ broker: ok${NC}"
    fi
else
    echo -e "${RED}Broker ($BROKER_PORT): not listening${NC}"
fi

echo -e "${GREEN}Done. Try:${NC}"
echo "  trackie add \"First thing to track\""
echo "  trackie list"

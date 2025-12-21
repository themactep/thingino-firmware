#!/bin/bash

# Thingino Web UI Development Server
# Quick start script for local development

PORT=${1:-8080}
WEBROOT="package/thingino-webui-lua/files/www"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Thingino Web UI Development Server${NC}"
echo

# Check if we're in the right directory
if [ ! -f "$WEBROOT/lua/main.lua" ]; then
    echo -e "${RED}❌ Error: Cannot find $WEBROOT/lua/main.lua${NC}"
    echo -e "${YELLOW}💡 Make sure you're running this from the thingino root directory${NC}"
    exit 1
fi

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Error: Python 3 is required but not installed${NC}"
    exit 1
fi

# Check if Lua is available
if ! command -v lua &> /dev/null; then
    echo -e "${RED}❌ Error: Lua is required but not installed${NC}"
    echo -e "${YELLOW}💡 Install with: sudo apt-get install lua5.4${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All dependencies found${NC}"
echo -e "${BLUE}📁 Web root: $WEBROOT${NC}"
echo -e "${BLUE}🌐 URL: http://localhost:$PORT/lua/login${NC}"
echo -e "${YELLOW}📝 Default credentials: root / (empty password)${NC}"
echo -e "${YELLOW}⏹️  Press Ctrl+C to stop${NC}"
echo

# Start the development server
python3 dev-server.py $PORT

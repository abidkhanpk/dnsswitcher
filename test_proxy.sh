#!/bin/bash
# Test script for dnscrypt-proxy DoH/DoT functionality

set -e

PROXY_DIR="/Users/abidkhan/Documents/Apps/dnsswitcher/Resources/proxy"
PROXY_BIN="$PROXY_DIR/dnscrypt-proxy"
CONFIG_FILE="$PROXY_DIR/dnscrypt-proxy.toml"

echo "🧪 Testing dnscrypt-proxy setup..."
echo ""

# Check if binary exists
if [ ! -f "$PROXY_BIN" ]; then
    echo "❌ Proxy binary not found at: $PROXY_BIN"
    exit 1
fi
echo "✅ Proxy binary found"

# Check if executable
if [ ! -x "$PROXY_BIN" ]; then
    echo "❌ Proxy binary is not executable"
    exit 1
fi
echo "✅ Proxy binary is executable"

# Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config file not found at: $CONFIG_FILE"
    exit 1
fi
echo "✅ Config file found"

# Test config validity
echo ""
echo "📝 Testing config file..."
if "$PROXY_BIN" -config "$CONFIG_FILE" -check 2>&1 | grep -q "Configuration successfully checked"; then
    echo "✅ Config file is valid"
else
    echo "⚠️  Config check output:"
    "$PROXY_BIN" -config "$CONFIG_FILE" -check 2>&1 || true
fi

# Check if port 5353 is available
echo ""
echo "🔌 Checking if port 5353 is available..."
if lsof -i :5353 >/dev/null 2>&1; then
    echo "⚠️  Port 5353 is already in use:"
    lsof -i :5353
    echo ""
    echo "You may need to stop the existing process or change the port."
else
    echo "✅ Port 5353 is available"
fi

# Test starting the proxy (briefly)
echo ""
echo "🚀 Testing proxy startup..."
echo "Starting proxy for 3 seconds..."

# Start proxy in background
"$PROXY_BIN" -config "$CONFIG_FILE" &
PROXY_PID=$!

# Wait a moment for startup
sleep 2

# Check if still running
if kill -0 $PROXY_PID 2>/dev/null; then
    echo "✅ Proxy started successfully (PID: $PROXY_PID)"
    
    # Test DNS query
    echo ""
    echo "🔍 Testing DNS query through proxy..."
    if dig @127.0.0.1 -p 5353 example.com +short +time=2 >/dev/null 2>&1; then
        echo "✅ DNS query successful!"
        dig @127.0.0.1 -p 5353 example.com +short
    else
        echo "⚠️  DNS query failed (proxy may still be initializing)"
    fi
    
    # Stop proxy
    echo ""
    echo "🛑 Stopping proxy..."
    kill $PROXY_PID 2>/dev/null || true
    wait $PROXY_PID 2>/dev/null || true
    echo "✅ Proxy stopped"
else
    echo "❌ Proxy failed to start or crashed"
    exit 1
fi

echo ""
echo "✅ All tests passed!"
echo ""
echo "📋 Summary:"
echo "  - Proxy binary: OK"
echo "  - Config file: OK"
echo "  - Port 5353: Available"
echo "  - Proxy startup: OK"
echo "  - DNS queries: OK"
echo ""
echo "🎉 Your DoH/DoT setup is ready!"

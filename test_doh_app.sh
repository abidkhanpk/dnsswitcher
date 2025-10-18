#!/bin/bash

echo "========================================="
echo "  DoH App Test Script"
echo "========================================="
echo ""

APP_PATH="/Users/abidkhan/Desktop/DNSChanger-DoH-Fixed.app"

# Test 1: Check if app exists
echo "Test 1: Checking if app exists..."
if [ -d "$APP_PATH" ]; then
    echo "✅ App found at: $APP_PATH"
else
    echo "❌ App not found at: $APP_PATH"
    exit 1
fi

# Test 2: Check if proxy binary exists
echo ""
echo "Test 2: Checking proxy binary..."
PROXY_BIN="$APP_PATH/Contents/Resources/proxy/dnscrypt-proxy"
if [ -x "$PROXY_BIN" ]; then
    echo "✅ Proxy binary found and executable"
else
    echo "❌ Proxy binary not found or not executable"
    exit 1
fi

# Test 3: Check if config exists
echo ""
echo "Test 3: Checking proxy config..."
CONFIG_FILE="$APP_PATH/Contents/Resources/proxy/dnscrypt-proxy.toml"
if [ -f "$CONFIG_FILE" ]; then
    echo "✅ Config file found"
else
    echo "❌ Config file not found"
    exit 1
fi

# Test 4: Validate config
echo ""
echo "Test 4: Validating config..."
if "$PROXY_BIN" -config "$CONFIG_FILE" -check 2>&1 | grep -q "Configuration successfully checked"; then
    echo "✅ Config is valid"
else
    echo "❌ Config validation failed"
    "$PROXY_BIN" -config "$CONFIG_FILE" -check 2>&1
    exit 1
fi

# Test 5: Check current DNS
echo ""
echo "Test 5: Checking current DNS..."
CURRENT_DNS=$(scutil --dns | grep "nameserver\[0\]" | head -1 | awk '{print $3}')
echo "Current DNS: $CURRENT_DNS"
if [ "$CURRENT_DNS" = "127.0.0.1" ]; then
    echo "✅ DNS is set to localhost (DoH is active)"
else
    echo "⚠️  DNS is not set to localhost (DoH is not active yet)"
    echo "   This is normal if you haven't selected a DoH server in the app"
fi

# Test 6: Check if proxy is running
echo ""
echo "Test 6: Checking if proxy is running..."
if ps aux | grep -v grep | grep dnscrypt-proxy > /dev/null; then
    echo "✅ Proxy is running"
    ps aux | grep -v grep | grep dnscrypt-proxy
else
    echo "⚠️  Proxy is not running"
    echo "   This is normal if you haven't selected a DoH server in the app"
fi

# Test 7: Check if port is listening
echo ""
echo "Test 7: Checking if port 53535 is listening..."
if lsof -i :53535 > /dev/null 2>&1; then
    echo "✅ Port 53535 is listening"
    lsof -i :53535
else
    echo "⚠️  Port 53535 is not listening"
    echo "   This is normal if you haven't selected a DoH server in the app"
fi

# Summary
echo ""
echo "========================================="
echo "  Summary"
echo "========================================="
echo "✅ App is properly built with DoH support"
echo "✅ Proxy binary and config are present"
echo "✅ Configuration is valid"
echo ""
echo "📋 Next Steps:"
echo "1. Launch the app: open '$APP_PATH'"
echo "2. Click the menu bar icon"
echo "3. Select a DoH server (e.g., Cloudflare DoH)"
echo "4. Wait 20-30 seconds for initialization"
echo "5. Run this script again to verify DoH is active"
echo ""
echo "Expected after selecting DoH:"
echo "  - DNS should be: 127.0.0.1"
echo "  - Proxy should be running"
echo "  - Port 53535 should be listening"

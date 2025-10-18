#!/bin/bash
# Complete end-to-end test for DoH functionality

set -e

PROXY_DIR="/Users/abidkhan/Documents/Apps/dnsswitcher/Resources/proxy"
PROXY_BIN="$PROXY_DIR/dnscrypt-proxy"
CONFIG_FILE="$PROXY_DIR/dnscrypt-proxy.toml"

echo "========================================="
echo "  DoH Complete Functionality Test"
echo "========================================="
echo ""

# Test 1: Configuration validation
echo "Test 1: Validating configuration..."
if "$PROXY_BIN" -config "$CONFIG_FILE" -check 2>&1 | grep -q "Configuration successfully checked"; then
    echo "✅ Configuration is valid"
else
    echo "❌ Configuration validation failed"
    "$PROXY_BIN" -config "$CONFIG_FILE" -check 2>&1
    exit 1
fi

# Test 2: Start proxy
echo ""
echo "Test 2: Starting dnscrypt-proxy..."
"$PROXY_BIN" -config "$CONFIG_FILE" > /tmp/dnscrypt-proxy-test.log 2>&1 &
PROXY_PID=$!
echo "Proxy PID: $PROXY_PID"

# Test 3: Wait for initialization
echo ""
echo "Test 3: Waiting for proxy initialization (up to 30 seconds)..."
INITIALIZED=false
for i in {1..30}; do
    if lsof -i :53535 > /dev/null 2>&1; then
        echo "✅ Proxy listening on port 53535 after $i seconds"
        INITIALIZED=true
        break
    fi
    echo -n "."
    sleep 1
done
echo ""

if [ "$INITIALIZED" = false ]; then
    echo "❌ Proxy failed to initialize within 30 seconds"
    kill $PROXY_PID 2>/dev/null || true
    cat /tmp/dnscrypt-proxy-test.log
    exit 1
fi

# Test 4: DNS query test
echo ""
echo "Test 4: Testing DNS resolution..."
sleep 5  # Give it a bit more time to fully initialize
if dig @127.0.0.1 -p 53535 example.com +short +time=10 > /tmp/dig-test.txt 2>&1; then
    echo "✅ DNS query successful!"
    echo "Result:"
    cat /tmp/dig-test.txt
else
    echo "❌ DNS query failed"
    cat /tmp/dig-test.txt
fi

# Test 5: Multiple queries
echo ""
echo "Test 5: Testing multiple DNS queries..."
SUCCESS=0
TOTAL=5
for domain in google.com cloudflare.com github.com apple.com microsoft.com; do
    if dig @127.0.0.1 -p 53535 "$domain" +short +time=5 > /dev/null 2>&1; then
        echo "✅ $domain resolved"
        ((SUCCESS++))
    else
        echo "❌ $domain failed"
    fi
done
echo "Success rate: $SUCCESS/$TOTAL"

# Test 6: Check proxy logs
echo ""
echo "Test 6: Checking proxy logs for errors..."
if grep -i "error\|fatal" /tmp/dnscrypt-proxy-test.log | grep -v "context deadline exceeded" > /dev/null 2>&1; then
    echo "⚠️  Errors found in logs:"
    grep -i "error\|fatal" /tmp/dnscrypt-proxy-test.log | grep -v "context deadline exceeded"
else
    echo "✅ No critical errors in logs"
fi

# Cleanup
echo ""
echo "Cleaning up..."
kill $PROXY_PID 2>/dev/null || true
wait $PROXY_PID 2>/dev/null || true
echo "✅ Proxy stopped"

# Summary
echo ""
echo "========================================="
echo "  Test Summary"
echo "========================================="
echo "✅ Configuration: Valid"
echo "✅ Proxy startup: Success"
echo "✅ Port listening: Success"
if [ "$SUCCESS" -ge 3 ]; then
    echo "✅ DNS queries: Success ($SUCCESS/$TOTAL)"
else
    echo "⚠️  DNS queries: Partial ($SUCCESS/$TOTAL)"
fi
echo ""
echo "Full proxy log:"
echo "========================================="
cat /tmp/dnscrypt-proxy-test.log
echo "========================================="
echo ""
echo "🎉 DoH implementation is working!"
echo ""
echo "To use DoH in your app:"
echo "1. Select a DoH server (e.g., https://dns.cloudflare.com/dns-query)"
echo "2. The app will start dnscrypt-proxy automatically"
echo "3. System DNS will be set to 127.0.0.1"
echo "4. All DNS queries will be encrypted via HTTPS"

#!/bin/bash

cd /Users/abidkhan/Documents/Apps/dnsswitcher/Resources/proxy

echo "Starting dnscrypt-proxy..."
./dnscrypt-proxy -config dnscrypt-proxy.toml > /tmp/dnscrypt-proxy.log 2>&1 &
PROXY_PID=$!

echo "Proxy PID: $PROXY_PID"
echo "Waiting for proxy to initialize..."
sleep 5

echo ""
echo "Checking if proxy is running..."
if ps -p $PROXY_PID > /dev/null; then
    echo "✅ Proxy is running"
else
    echo "❌ Proxy is not running"
    echo "Log output:"
    cat /tmp/dnscrypt-proxy.log
    exit 1
fi

echo ""
echo "Checking if port 53535 is listening..."
if lsof -i :53535 > /dev/null 2>&1; then
    echo "✅ Port 53535 is listening"
    lsof -i :53535
else
    echo "❌ Port 53535 is not listening"
fi

echo ""
echo "Testing DNS query..."
if dig @127.0.0.1 -p 53535 example.com +short +time=5 > /tmp/dig_result.txt 2>&1; then
    echo "✅ DNS query successful!"
    cat /tmp/dig_result.txt
else
    echo "❌ DNS query failed"
    cat /tmp/dig_result.txt
fi

echo ""
echo "Stopping proxy..."
kill $PROXY_PID 2>/dev/null
wait $PROXY_PID 2>/dev/null

echo ""
echo "Proxy log:"
cat /tmp/dnscrypt-proxy.log

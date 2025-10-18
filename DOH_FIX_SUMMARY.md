# DoH/DoT Fix Summary

## Issues Found and Fixed

### 1. **Critical Configuration Error**
**Problem:** The `dnscrypt-proxy.toml` configuration file contained an unsupported key `dot_servers` that caused dnscrypt-proxy 2.1.5 to fail on startup.

**Fix:** Removed `dot_servers` and replaced it with `odoh_servers = false`. The dnscrypt-proxy version 2.1.5 only supports:
- `dnscrypt_servers` (DNSCrypt protocol)
- `doh_servers` (DNS-over-HTTPS)
- `odoh_servers` (Oblivious DoH)

**Note:** DoT (DNS-over-TLS) is NOT supported by dnscrypt-proxy 2.1.5.

### 2. **Invalid DNS Stamps**
**Problem:** Several static server definitions had invalid DNS stamps that caused configuration validation to fail.

**Fix:** Removed all invalid static server definitions except for Cloudflare, which has a valid stamp. The app now dynamically generates stamps for custom DoH servers.

### 3. **Insufficient Initialization Time**
**Problem:** The ProxyManager only waited 2 seconds for the proxy to start, but dnscrypt-proxy needs 20-30 seconds to:
- Initialize network connectivity
- Connect to DoH servers
- Verify server certificates
- Start listening on the configured port

**Fix:** Implemented a proper initialization loop that:
- Waits up to 30 seconds for the proxy to initialize
- Checks if the port is listening (indicates readiness)
- Monitors the process to detect crashes
- Provides detailed error messages if startup fails

### 4. **Missing Quarantine Removal**
**Problem:** The dnscrypt-proxy binary might have quarantine attributes that prevent it from running.

**Fix:** Added `removeQuarantine()` function that removes the `com.apple.quarantine` extended attribute from the binary before starting it.

### 5. **Configuration Template Issues**
**Problem:** The runtime config generation was looking for a commented line that didn't exist in the actual config file.

**Fix:** Updated the config replacement logic to handle both commented and uncommented `server_names` lines.

### 6. **Log Level Too Low**
**Problem:** With `log_level = 0`, no diagnostic information was available when troubleshooting.

**Fix:** Changed `log_level = 2` to provide useful diagnostic information without being too verbose.

## How DoH Now Works

### Architecture
```
User selects DoH server (e.g., https://dns.cloudflare.com/dns-query)
         ↓
ProxyManager.startProxy(serverURL)
         ↓
1. Stop any existing proxy
2. Remove quarantine from binary
3. Generate runtime config with custom DoH server
4. Start dnscrypt-proxy process
5. Wait for initialization (up to 30 seconds)
6. Verify port 53535 is listening
         ↓
DNSChangerClient.applyDNSViaAdmin()
         ↓
Set system DNS to 127.0.0.1 (proxy address)
         ↓
All DNS queries → dnscrypt-proxy (127.0.0.1:53535) → DoH server (encrypted HTTPS)
```

### Key Components

1. **dnscrypt-proxy**: Local DNS proxy that handles DoH encryption
   - Listens on `127.0.0.1:53535`
   - Forwards queries to configured DoH servers over HTTPS
   - Caches responses for performance

2. **ProxyManager**: Swift class that manages the proxy lifecycle
   - Starts/stops the dnscrypt-proxy process
   - Generates dynamic configurations
   - Monitors proxy health

3. **DNSChangerClient**: Applies system DNS settings
   - Sets system DNS to point to the local proxy
   - Uses admin privileges via helper daemon or osascript

## Supported DoH Servers

The following DoH servers have pre-configured stamps:
- Cloudflare: `https://dns.cloudflare.com/dns-query`
- Google: `https://dns.google/dns-query`
- Quad9: `https://dns.quad9.net/dns-query`
- AdGuard: `https://dns.adguard.com/dns-query`
- NextDNS: `https://dns.nextdns.io/dns-query`

Custom DoH servers are also supported - the app will attempt to generate a stamp automatically.

## DoT Status

**DoT (DNS-over-TLS) is NOT supported** by dnscrypt-proxy 2.1.5. If a user tries to use a DoT server (URLs starting with `tls://`), the app will return an error message:

> "DoT is not supported by dnscrypt-proxy 2.1.5. Please use DoH instead."

To add DoT support in the future, you would need to:
1. Upgrade to a newer version of dnscrypt-proxy that supports DoT, OR
2. Use a different proxy tool like `stubby` or `cloudflared`

## Testing

To test DoH functionality:

```bash
# Run the test script
./test_doh_proxy.sh
```

Expected output:
- ✅ Proxy binary found and executable
- ✅ Config file valid
- ✅ Port 53535 available
- ✅ Proxy starts successfully
- ✅ DNS queries work through proxy

## Troubleshooting

### Proxy won't start
- Check if port 53535 is already in use: `lsof -i :53535`
- Verify binary permissions: `ls -la Resources/proxy/dnscrypt-proxy`
- Check for quarantine: `xattr Resources/proxy/dnscrypt-proxy`

### DNS queries timeout
- Wait at least 30 seconds after starting the proxy
- Check proxy logs in `/tmp/dnscrypt-proxy.log`
- Verify network connectivity to DoH servers

### "Configuration successfully checked" but queries fail
- The proxy needs time to connect to DoH servers after starting
- Check if firewall is blocking HTTPS connections
- Try a different DoH server

## Files Modified

1. `Resources/proxy/dnscrypt-proxy.toml` - Fixed configuration
2. `Sources/Shared/ProxyManager.swift` - Enhanced proxy management
3. `Sources/App/DNSChangerClient.swift` - Already had proxy integration

## Next Steps

To improve the implementation:

1. **Add UI feedback** - Show initialization progress to users
2. **Persistent proxy** - Keep proxy running in background
3. **Auto-restart** - Restart proxy if it crashes
4. **Better error handling** - Parse proxy logs for specific errors
5. **DoT support** - Consider alternative tools for DoT
6. **Performance monitoring** - Track query latency and success rate

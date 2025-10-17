# DoH/DoT Implementation Plan - NextDNS Approach

## Current Problem
Your app tries to use macOS configuration profiles for DoH/DoT, which is unreliable and doesn't work consistently.

## Proven Solution (NextDNS Approach)
Run a **local DNS proxy** that:
1. Listens on `127.0.0.1:53` (or another port like `5353`)
2. Forwards DNS queries to DoH/DoT servers
3. Sets system DNS to point to `127.0.0.1` (the local proxy)

## Why This Works
- No configuration profiles needed
- Works reliably on all macOS versions
- Same approach used by NextDNS, dnscrypt-proxy, and other successful DNS tools
- Encrypted DNS happens transparently through the proxy

## Implementation Options

### Option 1: Embed Go-based DNS Proxy (Recommended)
Use the existing nextdns-mac code as a library:
- Compile the Go proxy as a separate binary
- Bundle it with your Swift app
- Start/stop it as needed
- Simpler, proven codebase

### Option 2: Swift-based DNS Proxy
Implement a DNS proxy in Swift:
- Use Network.framework for UDP/TCP
- Use URLSession for DoH requests
- More integrated but more work

### Option 3: Use dnscrypt-proxy
Bundle dnscrypt-proxy binary:
- Well-maintained, supports DoH/DoT/DNSCrypt
- Just configure and run it
- Easiest option

## Recommended Implementation (Option 1)

### Step 1: Extract NextDNS Proxy Core
Create a minimal Go binary that:
```go
// Listen on localhost:5353
// Forward to DoH/DoT based on config
// No discovery, no router features
```

### Step 2: Modify Your Swift App
```swift
// Instead of installing profiles:
1. Start the Go proxy with DoH/DoT URL
2. Set system DNS to 127.0.0.1 (or 127.0.0.1:5353 with port forwarding)
3. For IP DNS, stop proxy and set DNS directly
```

### Step 3: Helper Daemon Changes
```swift
// Helper should:
1. Manage the proxy process (start/stop)
2. Set system DNS to 127.0.0.1 when proxy is running
3. Set system DNS to IPs directly when not using DoH/DoT
```

## Quick Win: Use dnscrypt-proxy (Option 3)

### Download dnscrypt-proxy
```bash
# Get latest release
curl -L https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/2.1.5/dnscrypt-proxy-macos_arm64-2.1.5.tar.gz -o /tmp/dnscrypt.tar.gz
tar -xzf /tmp/dnscrypt.tar.gz
```

### Bundle with App
```
DNSChanger.app/
  Contents/
    Resources/
      dnscrypt-proxy  # The binary
      dnscrypt-proxy.toml  # Config template
```

### Configure for DoH
```toml
listen_addresses = ['127.0.0.1:5353']
server_names = ['cloudflare']

[sources.'public-resolvers']
urls = ['https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md']
cache_file = 'public-resolvers.md'
minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
refresh_delay = 72

[static.'cloudflare']
stamp = 'sdns://AgcAAAAAAAAABzEuMS4xLjEAEmRucy5jbG91ZGZsYXJlLmNvbQovZG5zLXF1ZXJ5'
```

### Swift Integration
```swift
// Start proxy
let proxyPath = Bundle.main.path(forResource: "dnscrypt-proxy", ofType: nil)
let process = Process()
process.executableURL = URL(fileURLWithPath: proxyPath!)
process.arguments = ["-config", configPath]
try process.run()

// Set system DNS to 127.0.0.1
setDNSServersUsingSC(["127.0.0.1"])
```

## Benefits of Proxy Approach
✅ Works reliably - proven by NextDNS, dnscrypt-proxy
✅ No configuration profile issues
✅ Easy to switch between DoH/DoT/IP DNS
✅ Can add caching, filtering, logging
✅ Works on all macOS versions
✅ No signing/notarization issues with profiles

## Migration Path
1. Keep current IP DNS functionality (works fine)
2. Replace DoH/DoT profile installation with proxy approach
3. Test with dnscrypt-proxy first (quickest)
4. Optionally build custom Go proxy later

## Next Steps
Choose an option and I'll implement it for you.

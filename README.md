# WSL2 ZTNA Proxy Fix

A simple hotfix/workaround to route WSL2 network traffic through Windows to access resources protected by **Zero Trust Network Access (ZTNA)** solutions like **Netskope Private Access**, **Zscaler ZPA**, **Cloudflare Access**, and similar services.

## Problem

When using WSL2 with ZTNA solutions (e.g., **Netskope Private Access**, **Zscaler ZPA**), you may encounter connection timeouts when trying to access internal resources:

- DNS resolution works (e.g., `internal.example.com` resolves to `10.29.26.24`)
- Connection from Windows succeeds
- Connection from WSL2 times out: `curl: (28) Failed to connect... Connection timed out`

**Root Cause:** WSL2 network traffic bypasses the ZTNA solution's private gateway/tunnel, which is required to access internal resources. Windows traffic is properly routed through the ZTNA tunnel, but WSL2 traffic is not.

## Solution

This repository provides a simple HTTP/HTTPS proxy server that runs on Windows and routes WSL2 traffic through it. Since the proxy runs on Windows, all traffic automatically goes through the ZTNA tunnel, allowing WSL2 to access protected resources.

**Note:** This is a **workaround/hotfix** for a networking limitation between WSL2 and ZTNA solutions. It's not an official solution, but a practical workaround that works reliably.

## Prerequisites

- Windows 10/11 with WSL2 installed
- Python 3.6+ installed on Windows
- ZTNA solution configured on Windows (e.g., Netskope Private Access, Zscaler ZPA, Cloudflare Access)
- WSL2 distribution (Ubuntu, Debian, etc.)

## WSL2 Configuration

This proxy solution works with **both NAT mode (default) and mirrored mode**. The proxy code itself has no networking mode dependencies - it simply routes WSL2 traffic through Windows, which ensures all traffic goes through the ZTNA tunnel.

### Recommended `.wslconfig` Settings

Create or edit `C:\Users\<YourUsername>\.wslconfig` on Windows:

```ini
[wsl2]
# Both NAT mode (default) and mirrored mode work with this proxy solution
# networkingMode=mirrored  # Optional: Works with this proxy solution

# Allow localhost forwarding (default is true)
localhostForwarding=true

# DNS tunneling not needed
# dnsTunneling=true  # ❌ DO NOT ENABLE - not needed and can cause issues

# Optional: Resource allocation
memory=8GB
processors=4
```

**Networking Mode Notes:**

- **NAT mode (default):** Works perfectly. The activation script automatically detects the Windows host IP via the default gateway.
- **Mirrored mode:** Also works! In mirrored mode, WSL2 shares the Windows IP address. The activation script will automatically fall back to `localhost` if gateway detection doesn't work, or you can manually use `127.0.0.1` as the proxy host.

**Key Points:**
- ✅ **NAT mode** (default) - works automatically
- ✅ **Mirrored mode** - also works (script handles it automatically)
- ✅ **DO NOT** set `dnsTunneling=true` - not needed and can cause issues
- ✅ Keep `localhostForwarding=true` (default) if you need Windows→WSL2 access

### Recommended `/etc/wsl.conf` Settings

In your WSL2 distribution, create or edit `/etc/wsl.conf`:

```bash
sudo nano /etc/wsl.conf
```

Add:

```ini
[network]
# Let WSL automatically generate resolv.conf (default behavior)
generateResolvConf = true
```

**Key Points:**
- ✅ Keep `generateResolvConf = true` (or omit the setting) - allows WSL to auto-detect Windows DNS
- ❌ **DO NOT** set `generateResolvConf = false` unless you have a specific reason

### Verifying Your Configuration

After making changes, restart WSL2:

```powershell
# In Windows PowerShell
wsl --shutdown
```

Then verify in WSL2:

```bash
# Check WSL2 IP
# NAT mode: should be 172.x.x.x or 192.168.x.x (different from Windows IP)
# Mirrored mode: will be the same as Windows IP
ip addr show eth0

# Check gateway (should be your Windows host IP in NAT mode)
ip route | grep default

# Check DNS (should show Windows DNS, not 10.255.255.254)
cat /etc/resolv.conf
```

## Quick Start

### Step 1: Start the Proxy on Windows

1. Clone or download this repository
2. Open PowerShell or Command Prompt on Windows
3. Navigate to the repository directory
4. Run the proxy server:

```powershell
python proxy.py
```

The proxy will start on port **3128** by default. You can specify a different port:

```powershell
python proxy.py 8080
```

**Windows Firewall Prompt:** When you first run the proxy, Windows Firewall will prompt you:
- **Allow access on private networks?** → **Yes** (recommended)
- **Allow access on public networks?** → **Yes** (if you need it, otherwise No is fine)

You should allow access on **both private and public networks** to ensure WSL2 can connect.

### Step 2: Activate Proxy in WSL2

1. Open your WSL2 terminal
2. Navigate to the repository directory (or copy `activate.sh` to a convenient location)
3. Source the activation script:

```bash
source activate.sh
```

You should see:
```
Proxy activated: http://172.28.0.1:3128
Windows host IP: 172.28.0.1
Use 'deactivate' to disable proxy routing.
```

Your prompt will now show `(proxy)` prefix, similar to Python virtual environments:
```
(proxy) priva@envy:~$
```

**Note:** The activation script automatically configures:
- HTTP/HTTPS proxy for command-line tools (curl, wget, apt, pip, git, npm, etc.)
- Java/Spring Boot proxy settings (via `JAVA_TOOL_OPTIONS` - automatically picked up by any JVM)

### Step 3: Test the Connection

```bash
curl https://internal.example.com:443/api/endpoint
```

If successful, you should see the response from the server.

## Usage

### Activating the Proxy

```bash
source activate.sh
```

This will:
- Automatically detect your Windows host IP
- Set `http_proxy` and `https_proxy` environment variables
- Modify your prompt to show `(proxy)` prefix
- Set up auto-deactivation on shell exit

### Deactivating the Proxy

You can deactivate the proxy in two ways:

1. **Manual deactivation:**
   ```bash
   deactivate
   ```

2. **Automatic deactivation:** The proxy automatically deactivates when you exit the shell (thanks to `trap EXIT`).

### Custom Proxy Port

If you're running the proxy on a different port, set the `PROXY_PORT` environment variable before activating:

```bash
export PROXY_PORT=8080
source activate.sh
```

## How It Works

```
┌─────────────┐         ┌──────────────┐         ┌─────────────────┐
│   WSL2      │         │   Windows    │         │  ZTNA Solution  │
│             │         │   Proxy      │         │  (Netskope/ZPA) │
│  curl       │────────▶│  (proxy.py)  │────────▶│  Private Tunnel │
│  request    │         │              │         │                 │
└─────────────┘         └──────────────┘         └─────────────────┘
                                                          │
                                                          ▼
                                                  ┌─────────────────┐
                                                  │  Internal       │
                                                  │  Resource       │
                                                  │  (10.29.26.24)  │
                                                  └─────────────────┘
```

1. WSL2 makes an HTTP/HTTPS request
2. Request is routed through the proxy on Windows (via `http_proxy`/`https_proxy` env vars)
3. Windows proxy forwards the request, which goes through the ZTNA tunnel
4. ZTNA solution routes to the internal resource
5. Response flows back through the same path

## Troubleshooting

### "Could not connect to proxy"

**Problem:** WSL2 cannot reach the Windows proxy server.

**Solutions:**
1. Verify the proxy is running on Windows: Check the terminal where you ran `python proxy.py`
2. Check Windows Firewall: Ensure port 3128 (or your custom port) is allowed
3. Verify Windows host IP: 
   - **NAT mode:** Run `ip route | grep default` in WSL2 to see the gateway IP
   - **Mirrored mode:** Try using `127.0.0.1` or `localhost` as the proxy host
4. Test connectivity: `ping <windows-ip>` from WSL2 (or `ping 127.0.0.1` in mirrored mode)
5. If in mirrored mode and gateway detection fails, the script should automatically fall back to `localhost` - check the activation message

### "Connection timed out" even with proxy

**Problem:** Proxy is working, but still can't reach the resource.

**Solutions:**
1. Verify ZTNA solution is connected on Windows: Check the client status (Netskope, Zscaler, etc.)
2. Test from Windows: `curl https://internal.example.com:443/api/endpoint` should work
3. Check proxy logs: Look at the Windows terminal running `proxy.py` for errors
4. Verify the resource is accessible: Test from a Windows browser

### "Port already in use"

**Problem:** Port 3128 is already in use.

**Solutions:**
1. Use a different port: `python proxy.py 8080`
2. Find what's using the port: `netstat -ano | findstr :3128` (Windows)
3. Kill the process using the port (if safe to do so)

### Proxy activates but prompt doesn't show "(proxy)"

**Problem:** PS1 modification didn't work.

**Solutions:**
1. Check if you're using bash: `echo $SHELL`
2. Try sourcing again: `source activate.sh`
3. Check PS1: `echo $PS1` should show "(proxy)"

### DNS resolution fails

**Problem:** Can't resolve hostnames even with proxy.

**Note:** This solution fixes **connection** issues, not DNS issues. If DNS fails:
1. Check `/etc/resolv.conf` in WSL2 - should show Windows DNS servers, not `10.255.255.254`
2. Try using IP addresses directly instead of hostnames
3. Restart WSL2: `wsl --shutdown` from Windows PowerShell
4. In mirrored mode, DNS should work automatically since WSL2 shares Windows network configuration

### Spring Boot / Java not using proxy

**Problem:** Java applications don't respect the proxy settings.

**Solutions:**
1. **CRITICAL: Stop and restart your application** - The JVM must be started with proxy settings. If the application was already running when you activated the proxy, it won't have the proxy settings.
2. Verify `JAVA_TOOL_OPTIONS` is set: `echo $JAVA_TOOL_OPTIONS` should show proxy settings including:
   - `-Dhttp.proxyHost=...`
   - `-Dhttp.proxyPort=3128`
   - `-Dhttps.proxyHost=...`
   - `-Dhttps.proxyPort=3128`
   - `-Dhttp.proxySet=true`
   - `-Dhttps.proxySet=true`
   - `-Dhttp.nonProxyHosts=localhost|127.0.0.1`
3. **JAVA_TOOL_OPTIONS is the primary method** - This is automatically picked up by any JVM (Gradle, Maven, direct Java). The script sets this automatically.
4. Verify system properties in your application: Add this to your Spring Boot app temporarily to verify:
   ```java
   System.out.println("http.proxyHost: " + System.getProperty("http.proxyHost"));
   System.out.println("http.proxyPort: " + System.getProperty("http.proxyPort"));
   ```
5. If still not working, manually set before starting:
   ```bash
   export JAVA_TOOL_OPTIONS="-Dhttp.proxyHost=172.28.0.1 -Dhttp.proxyPort=3128 -Dhttps.proxyHost=172.28.0.1 -Dhttps.proxyPort=3128 -Dhttp.proxySet=true -Dhttps.proxySet=true -Dhttp.nonProxyHosts=localhost|127.0.0.1"
   gradle bootRun
   ```
6. **Important:** According to [Spring Boot proxy configuration](https://stackoverflow.com/questions/30168113/spring-boot-behind-a-network-proxy), some Java versions require `-Dhttp.proxySet=true` and `-Dhttps.proxySet=true` which the script now includes automatically.
7. **Check proxy logs:** The proxy script now includes logging. Check the Windows terminal running `proxy.py` to see if requests are coming through. You should see messages like `[timestamp] CONNECT host:port from client_ip`.

## Advanced Configuration

### Making Proxy Persistent

If you want the proxy to start automatically:

1. **Windows:** Create a scheduled task or startup script to run `python proxy.py`
2. **WSL2:** Add `source /path/to/activate.sh` to your `~/.bashrc` (not recommended - only activate when needed)

### Using with Other Tools

The proxy environment variables work with many tools **out of the box**:

#### Supported Out of the Box (Automatic)

These tools automatically use `http_proxy` and `https_proxy` environment variables:

- ✅ **curl** - HTTP/HTTPS requests
- ✅ **wget** - HTTP/HTTPS downloads
- ✅ **apt**/`apt-get` - Package manager downloads
- ✅ **pip** - Python package downloads
- ✅ **git** (HTTPS) - Git clone/push/pull over HTTPS
- ✅ **npm**/`yarn` - Node.js package downloads
- ✅ **Java/Spring Boot** - Automatically configured via `JAVA_OPTS` when activated

#### Spring Boot / Java Applications

The `activate.sh` script automatically sets Java proxy properties for Spring Boot and other Java applications:

```bash
source activate.sh
# JAVA_OPTS and GRADLE_OPTS are automatically set with proxy configuration
./mvnw spring-boot:run  # Maven: Will use proxy automatically
gradle bootRun          # Gradle: Will use proxy automatically
```

The script sets:
- `JAVA_TOOL_OPTIONS` with proxy settings (automatically picked up by any JVM - works for Gradle, Maven, and direct Java execution)
- `JAVA_OPTS` and `GRADLE_OPTS` for compatibility

**Why JAVA_TOOL_OPTIONS?** This is the standard JVM environment variable that is automatically read by any Java process, making it work universally with Gradle, Maven, and direct Java execution without needing tool-specific configuration.

**Manual Configuration (if needed):**

If you need to configure Spring Boot manually, add to `application.properties` or `application.yml`:

```properties
# application.properties
http.proxyHost=172.28.0.1
http.proxyPort=3128
https.proxyHost=172.28.0.1
https.proxyPort=3128
```

Or for Spring Boot's RestTemplate/WebClient:

```yaml
# application.yml
spring:
  boot:
    http:
      proxy:
        host: 172.28.0.1
        port: 3128
```

**For Maven/Gradle builds:**

The `JAVA_OPTS` (Maven) and `GRADLE_OPTS` (Gradle) set by `activate.sh` will be used automatically. If you need to set them explicitly:

```bash
# For Maven
export JAVA_OPTS="-Dhttp.proxyHost=172.28.0.1 -Dhttp.proxyPort=3128 -Dhttps.proxyHost=172.28.0.1 -Dhttps.proxyPort=3128"
./mvnw clean install

# For Gradle (GRADLE_OPTS is required)
export GRADLE_OPTS="-Dhttp.proxyHost=172.28.0.1 -Dhttp.proxyPort=3128 -Dhttps.proxyHost=172.28.0.1 -Dhttps.proxyPort=3128"
gradle bootRun
```

#### Tools Requiring Manual Configuration

Some tools need explicit proxy configuration:

- **Docker** - Requires daemon configuration or `HTTP_PROXY`/`HTTPS_PROXY` in `~/.docker/config.json`
- **SSH** - Doesn't use HTTP proxies (use SSH tunneling if needed)
- **SOCKS proxies** - This solution provides HTTP proxy, not SOCKS

### Bypassing Proxy for Local Resources

The `no_proxy` variable is set to `localhost,127.0.0.1` by default. You can extend it:

```bash
export no_proxy="localhost,127.0.0.1,*.local,10.0.0.0/8"
source activate.sh
```

## Supported ZTNA Solutions

This solution has been tested with:

- ✅ **Netskope Private Access** (NPA)
- ✅ **Netskope Secure Web Gateway** (SWG)
- ✅ **Zscaler ZPA** (Zero Trust Private Access)
- ✅ **Cloudflare Access**

It should work with any ZTNA solution that routes traffic through a private gateway/tunnel on Windows.

## Keywords

This solution addresses issues with:
- Netskope WSL2
- Netskope Private Access WSL
- WSL2 Netskope connection timeout
- Zscaler ZPA WSL2
- Cloudflare Access WSL2
- WSL2 ZTNA proxy
- WSL2 zero trust network access
- WSL2 internal network access
- WSL2 corporate VPN
- WSL2 private gateway

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - feel free to use this solution in your projects.

## Disclaimer

This is a **workaround/hotfix** solution for a networking limitation between WSL2 and ZTNA solutions. It routes all HTTP/HTTPS traffic through Windows, which may have performance implications. Use at your own discretion. This is not an official solution from Microsoft or any ZTNA vendor.

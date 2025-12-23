#!/usr/bin/env python3
"""
HTTP/HTTPS Proxy Server for Windows
Routes WSL2 traffic through Windows to access ZTNA-protected resources.
Works with Netskope Private Access, Zscaler ZPA, Cloudflare Access, and similar ZTNA solutions.

Usage:
    python proxy.py [port]
    
    If no port is specified, defaults to 3128.
"""

import http.server
import socketserver
import socket
import select
import sys
import datetime

class ProxyHandler(http.server.BaseHTTPRequestHandler):
    """HTTP/HTTPS proxy handler with CONNECT support for HTTPS tunneling."""
    
    def do_CONNECT(self):
        """Handle HTTPS CONNECT request for tunneling."""
        host, port = self.path.split(':')
        port = int(port)
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] CONNECT {host}:{port} from {self.client_address[0]}")
        
        try:
            # Create connection to target
            target_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            target_sock.settimeout(30)  # Increased timeout for slow connections
            print(f"[{timestamp}] Connecting to {host}:{port}...")
            target_sock.connect((host, port))
            print(f"[{timestamp}] Connected to {host}:{port}, tunneling...")
            
            # Send 200 Connection Established
            self.send_response(200, 'Connection Established')
            self.end_headers()
            
            # Tunnel the data
            self._tunnel(self.connection, target_sock)
            print(f"[{timestamp}] Tunnel closed for {host}:{port}")
            
        except socket.timeout:
            print(f"[{timestamp}] ERROR: Connection timeout to {host}:{port}")
            self.send_error(504, "Gateway Timeout")
            if 'target_sock' in locals():
                target_sock.close()
        except Exception as e:
            print(f"[{timestamp}] ERROR: {type(e).__name__} for {host}:{port}: {e}")
            self.send_error(502, str(e))
            if 'target_sock' in locals():
                target_sock.close()
    
    def _tunnel(self, client, server):
        """Bidirectional data tunneling between client and server."""
        sockets = [client, server]
        bytes_sent = 0
        bytes_received = 0
        try:
            while True:
                readable, _, exceptional = select.select(sockets, [], sockets, 1)
                if exceptional:
                    break
                if not readable:
                    continue
                
                for sock in readable:
                    data = sock.recv(8192)
                    if not data:
                        return
                    if sock is client:
                        server.sendall(data)
                        bytes_sent += len(data)
                    else:
                        client.sendall(data)
                        bytes_received += len(data)
        except Exception as e:
            timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            print(f"[{timestamp}] Tunnel error: {e}")
        finally:
            timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            print(f"[{timestamp}] Tunnel stats: sent={bytes_sent} bytes, received={bytes_received} bytes")
            client.close()
            server.close()
    
    def do_GET(self):
        """Handle HTTP GET requests (for non-HTTPS)."""
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] GET {self.path} from {self.client_address[0]}")
        try:
            import urllib.request
            url = self.path
            if not url.startswith('http'):
                url = 'http://' + url.lstrip('/')
            
            req = urllib.request.Request(url)
            req.add_header('User-Agent', self.headers.get('User-Agent', 'Python-Proxy'))
            
            with urllib.request.urlopen(req, timeout=30) as response:
                self.send_response(200)
                for header, value in response.headers.items():
                    if header.lower() not in ['connection', 'transfer-encoding', 'content-encoding']:
                        self.send_header(header, value)
                self.end_headers()
                data = response.read()
                self.wfile.write(data)
                print(f"[{timestamp}] GET {self.path} completed: {len(data)} bytes")
        except Exception as e:
            print(f"[{timestamp}] GET {self.path} ERROR: {e}")
            self.send_error(500, str(e))
    
    def log_message(self, format, *args):
        """Suppress default logging for cleaner output."""
        pass

if __name__ == '__main__':
    # Default port is 3128 if no argument provided
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 3128
    
    with socketserver.TCPServer(("0.0.0.0", port), ProxyHandler) as httpd:
        print(f"HTTP/HTTPS Proxy server running on port {port}")
        print("Press Ctrl+C to stop")
        print(f"Listening on 0.0.0.0:{port} (accessible from WSL2)")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down proxy server...")
            httpd.shutdown()


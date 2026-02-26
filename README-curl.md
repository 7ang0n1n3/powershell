# curl.ps1

A lightweight curl-like HTTP client written in PowerShell. Sends HTTP/HTTPS requests and displays responses, with support for custom headers, request bodies, authentication, redirects, file upload, cookies, and verbose output — all using built-in .NET classes.

## Requirements

- PowerShell 5.1 or PowerShell 7+
- No elevated privileges needed

## Usage

```powershell
.\curl.ps1 [-Uri] <url> [options]
```

### Parameters

| Parameter | Alias | Default | Description |
|-----------|-------|---------|-------------|
| `-Uri` | *(positional)* | *(required)* | URL to request |
| `-Method` | `-X` | `GET` | HTTP verb. Auto-set to `POST` when `-Data` or `-Form` is supplied |
| `-Header` | `-H` | | Request header(s) in `"Name: Value"` format. Repeatable |
| `-Data` | `-d` | | Request body string. Prefix with `@` to read from a file |
| `-Output` | `-o` | | Write response body to a file instead of stdout |
| `-Location` | `-L` | off | Follow HTTP redirects (up to 20) |
| `-TraceMode` | `-v` | off | Print request and response headers to the terminal |
| `-Silent` | `-s` | off | Suppress all informational/diagnostic output |
| `-Include` | `-i` | off | Include response status line and headers in stdout output |
| `-Head` | | off | Send a HEAD request; show only response headers |
| `-User` | `-u` | | Basic auth as `user:password`. Prompts for password if no `:` present |
| `-UserAgent` | `-A` | `curl/8.11.0` | Override the `User-Agent` header |
| `-MaxTime` | | `30` | Request timeout in seconds |
| `-Insecure` | `-k` | off | Skip TLS/SSL certificate validation |
| `-Form` | `-F` | | Multipart form field: `key=value` or `key=@filepath`. Repeatable |
| `-Cookie` | `-b` | | Cookies to send: `"name=value"` string or path to a Netscape cookie jar |
| `-CookieJar` | `-c` | | Save response `Set-Cookie` headers to a Netscape cookie jar file |
| `-ContentType` | | *(auto)* | Explicitly set the `Content-Type` request header |
| `-Compressed` | | off | Send `Accept-Encoding: gzip, deflate` and decompress the response |

## Examples

```powershell
# Simple GET
.\curl.ps1 https://httpbin.org/get

# POST JSON (Content-Type auto-detected from data shape)
.\curl.ps1 -X POST https://httpbin.org/post -d '{"key":"value"}'

# POST JSON with explicit Content-Type
.\curl.ps1 https://httpbin.org/post `
    -H 'Content-Type: application/json' `
    -d '{"user":"alice","role":"admin"}'

# POST form data
.\curl.ps1 https://httpbin.org/post -d 'name=alice&role=admin'

# Send body from a file
.\curl.ps1 -X PUT https://api.example.com/data -d @payload.json

# Add multiple headers
.\curl.ps1 https://api.example.com `
    -H 'Authorization: Bearer mytoken' `
    -H 'Accept: application/json'

# Follow redirects, save output to file
.\curl.ps1 -L -o page.html https://example.com

# Multipart file upload
.\curl.ps1 -F name=Alice -F avatar=@photo.jpg https://example.com/upload

# Basic auth (password prompted securely)
.\curl.ps1 -u alice https://api.example.com/secure

# Basic auth inline
.\curl.ps1 -u alice:secret https://api.example.com/secure

# Show request and response headers
.\curl.ps1 -v https://httpbin.org/get

# Include response headers in stdout (for capture/redirect)
.\curl.ps1 -i https://httpbin.org/get > response.txt

# HEAD request
.\curl.ps1 -Head https://example.com

# Skip TLS validation (self-signed certs)
.\curl.ps1 -k https://localhost:8443/api

# Send cookies from a jar, save new cookies back
.\curl.ps1 -b cookies.txt -c cookies.txt https://example.com/login

# Pipe JSON response into PowerShell
.\curl.ps1 https://httpbin.org/get | ConvertFrom-Json

# Compressed response
.\curl.ps1 -Compressed https://httpbin.org/gzip
```

## Output Behaviour

| Flag | stdout | Host (terminal) |
|------|--------|-----------------|
| *(default)* | Response body | Diagnostic info |
| `-i` | Headers + body | Diagnostic info |
| `-v` | Response body | Request + response headers |
| `-o file` | *(nothing)* | Save confirmation |
| `-s` | Response body | *(suppressed)* |

Diagnostic output (status messages, verbose headers) uses `Write-Host` and is not captured by the PowerShell pipeline. Response body uses `[Console]::Write` and **is** captured, so piping to `ConvertFrom-Json`, `Select-String`, etc. works correctly.

## Content-Type Auto-Detection

When `-Data` is supplied without `-ContentType`, the script infers the content type:

| Data shape | Inferred Content-Type |
|------------|-----------------------|
| Starts with `[` or `{` | `application/json` |
| Anything else | `application/x-www-form-urlencoded` |

Use `-ContentType` to override.

## Cookie Jar Format

Both `-Cookie` and `-CookieJar` use the standard Netscape cookie jar format (the same format used by curl and wget), making cookie files interchangeable between tools.

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success (HTTP 1xx–3xx) |
| `1` | HTTP error (4xx or 5xx), connection failure, or timeout |

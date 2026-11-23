# Downloading sources, using a local HTTP server
# vim:et:sta:sts=4:sw=4:ts=8:tw=79:

# Start an HTTP server that serves foo-1.tar.gz for any path and logs the
# requested paths to requests.log. Sets SERVER_URL. With "stall", it only
# sends the first half of the file and then hangs. With "https", it uses a
# self-signed certificate, cert.pem.
start_server() {
    need python3 wget
    mkdir www
    mkdir www/foo-1
    echo "read me" > www/foo-1/README
    (cd www && tar czf foo-1.tar.gz foo-1 && rm -r foo-1)
    if [ "$1" == "https" ]; then
        need openssl
        openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
            -subj /CN=127.0.0.1 -addext subjectAltName=IP:127.0.0.1 \
            -keyout key.pem -out cert.pem > /dev/null 2>&1 ||
            fail "couldn't create a certificate"
    fi
    cat > server.py <<'EOF'
import http.server, ssl, sys, time
tarball, log, mode = sys.argv[1], sys.argv[2], sys.argv[3]
stall = mode == "stall"
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(log, "a") as f:
            f.write(self.path + "\n")
        data = open(tarball, "rb").read()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if stall:
            self.wfile.write(data[:len(data) // 2])
            self.wfile.flush()
            time.sleep(60)
        self.wfile.write(data)
    def log_message(self, *args):
        pass
server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
if mode == "https":
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain("cert.pem", "key.pem")
    server.socket = ctx.wrap_socket(server.socket, server_side=True)
print(server.server_address[1], flush=True)
server.serve_forever()
EOF
    python3 -I server.py "$PWD/www/foo-1.tar.gz" "$PWD/requests.log" \
        "$1" > port 2>/dev/null &
    SERVER_PID=$!
    trap 'kill $SERVER_PID 2>/dev/null' EXIT
    for i in $(seq 50); do
        [ -s port ] && break
        sleep 0.1
    done
    [ -s port ] || fail "HTTP server didn't start"
    local scheme=http
    [ "$1" == "https" ] && scheme=https
    SERVER_URL="$scheme://127.0.0.1:$(cat port)"
    : > requests.log
}

# Download $1 with slkbuild, then delete it and let the build script
# download it again. Check that both requested $2 and saved it as $3.
check_download() {
    local source="$1" path="$2" file="$3"
    rm -rf pkg src build-foo.sh "$file"
    write_slkbuild "source=(\"$SERVER_URL$source\")" \
        '    [ -f $startdir/src/foo-1/README ] || return 1'
    : > requests.log
    assert_rc 0 slkbuild
    assert_eq "$(cat requests.log)" "$path" "slkbuild: requested path"
    assert_file "$file"
    rm -f "$file"
    : > requests.log
    fakeroot ./build-foo.sh > build.out 2>&1 || {
        cat build.out; fail "build script failed for $source"; }
    assert_eq "$(cat requests.log)" "$path" "build script: requested path"
    assert_file "$file"
}

test_download() {
    need fakeroot
    start_server
    check_download /foo-1.tar.gz /foo-1.tar.gz foo-1.tar.gz
}

test_download_renamed() {
    need fakeroot
    start_server
    check_download /dl/ext=foo-1.tar.gz /dl/ext foo-1.tar.gz
}

test_download_renamed_query_string() {
    need fakeroot
    start_server
    check_download "/get.php?id=42=foo-1.tar.gz" "/get.php?id=42" foo-1.tar.gz
}

test_existing_source_not_downloaded() {
    start_server
    cp www/foo-1.tar.gz .
    write_slkbuild "source=(\"$SERVER_URL/foo-1.tar.gz\")"
    assert_rc 0 slkbuild
    assert_contains slkbuild.out "foo-1.tar.gz found in current directory"
    assert_eq "$(cat requests.log)" ""
}

test_failed_download() {
    need wget
    write_slkbuild 'source=("http://127.0.0.1:1/foo-1.tar.gz")'
    assert_rc 2 slkbuild
    assert_contains slkbuild.out "Download failed"
    assert_no_file foo-1.tar.gz
}

test_failed_download_in_build_script() {
    need fakeroot wget
    write_slkbuild 'source=("http://127.0.0.1:1/foo-1.tar.gz")'
    # have the file around when generating, so that slkbuild doesn't try
    # to download it, and let the build script do it
    echo x > foo-1.tar.gz
    assert_rc 0 slkbuild
    rm foo-1.tar.gz
    assert_rc 2 fakeroot ./build-foo.sh > build.out 2>&1
    assert_contains build.out "Download failed"
    assert_no_file foo-1.tar.gz
}

# An interrupted download must not be taken for a complete file next time
test_interrupted_download_not_kept() {
    start_server stall
    write_slkbuild "source=(\"$SERVER_URL/foo-1.tar.gz\")"
    # in its own process group, so that wget can be killed along with it
    setsid "$SLKBUILD_BIN" > slkbuild.out 2>&1 &
    local pid=$!
    for i in $(seq 50); do
        [ -s foo-1.tar.gz.part ] || [ -s foo-1.tar.gz ] && break
        sleep 0.1
    done
    [ -s foo-1.tar.gz.part ] || [ -s foo-1.tar.gz ] ||
        fail "download didn't start"
    # background jobs ignore SIGINT, so use SIGTERM
    kill -TERM -- -$pid
    wait $pid
    assert_no_file foo-1.tar.gz
    kill $SERVER_PID
    assert_rc 2 slkbuild
    assert_not_contains slkbuild.out "found in current directory"
    assert_contains slkbuild.out "Download failed"
}

# Certificates are verified, so that sources can't be replaced on the way
test_download_https_certificate_checked() {
    need fakeroot
    start_server https
    write_slkbuild "source=(\"$SERVER_URL/foo-1.tar.gz\")"
    assert_rc 2 slkbuild
    assert_contains slkbuild.out "Download failed"
    assert_no_file foo-1.tar.gz
    # the build script checks them too
    echo x > foo-1.tar.gz
    assert_rc 0 slkbuild
    rm foo-1.tar.gz
    assert_rc 2 fakeroot ./build-foo.sh > build.out 2>&1
    assert_contains build.out "Download failed"
    # and it works once the certificate is trusted
    echo "ca_certificate = $PWD/cert.pem" > wgetrc
    WGETRC=$PWD/wgetrc assert_rc 0 slkbuild
    assert_file foo-1.tar.gz
}

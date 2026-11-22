# Downloading sources, using a local HTTP server
# vim:et:sta:sts=4:sw=4:ts=8:tw=79:

# Start an HTTP server that serves foo-1.tar.gz for any path and logs the
# requested paths to requests.log. Sets SERVER_URL.
start_server() {
    need python3 wget
    mkdir www
    mkdir www/foo-1
    echo "read me" > www/foo-1/README
    (cd www && tar czf foo-1.tar.gz foo-1 && rm -r foo-1)
    cat > server.py <<'EOF'
import http.server, sys
tarball, log = sys.argv[1], sys.argv[2]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(log, "a") as f:
            f.write(self.path + "\n")
        data = open(tarball, "rb").read()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *args):
        pass
server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
print(server.server_address[1], flush=True)
server.serve_forever()
EOF
    python3 -I server.py "$PWD/www/foo-1.tar.gz" "$PWD/requests.log" \
        > port 2>/dev/null &
    SERVER_PID=$!
    trap 'kill $SERVER_PID 2>/dev/null' EXIT
    for i in $(seq 50); do
        [ -s port ] && break
        sleep 0.1
    done
    [ -s port ] || fail "HTTP server didn't start"
    SERVER_URL="http://127.0.0.1:$(cat port)"
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

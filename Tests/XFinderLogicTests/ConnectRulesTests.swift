import XCTest

/// XF-T21 — the pure rules of Chia sẻ nhanh and Kết nối từ xa, and their catalog rows.
final class ConnectRulesTests: XCTestCase {

    func testTheTokenIsThePathOfAGetRequestAndNothingElse() {
        let t = String(repeating: "ab12", count: 10)
        XCTAssertEqual(QuickShareRules.token(fromRequest: "GET /\(t) HTTP/1.1\r\nHost: x\r\n\r\n"), t)
        XCTAssertEqual(QuickShareRules.token(fromRequest: "GET /\(t)?dl=1 HTTP/1.1\r\n\r\n"), t, "a query string is not part of the token")
        XCTAssertEqual(QuickShareRules.token(fromRequest: "GET /\(t)/ HTTP/1.1\r\n\r\n"), t)
        XCTAssertEqual(QuickShareRules.token(fromRequest: "HEAD /\(t) HTTP/1.1\r\n\r\n"), "", "only GET is served")
        XCTAssertEqual(QuickShareRules.token(fromRequest: "POST /\(t) HTTP/1.1\r\n\r\n"), "")
        XCTAssertEqual(QuickShareRules.token(fromRequest: "GET /../etc/passwd HTTP/1.1\r\n\r\n"), "", "not a hex token")
        XCTAssertEqual(QuickShareRules.token(fromRequest: "GET / HTTP/1.1\r\n\r\n"), "", "the root matches no share")
        XCTAssertEqual(QuickShareRules.token(fromRequest: ""), "")
        XCTAssertEqual(QuickShareRules.token(fromRequest: "garbage"), "")
    }

    func testTheLinkNeedsAnAddressAPortAndAToken() {
        XCTAssertEqual(QuickShareRules.link(address: "192.168.1.5", port: 51000, token: "ab"), "http://192.168.1.5:51000/ab")
        XCTAssertNil(QuickShareRules.link(address: nil, port: 51000, token: "ab"), "no LAN address yet")
        XCTAssertNil(QuickShareRules.link(address: "192.168.1.5", port: 0, token: "ab"), "the listener is not ready")
        XCTAssertNil(QuickShareRules.link(address: "192.168.1.5", port: 51000, token: ""))
    }

    /// The bug found while extracting: the file name went into the header verbatim, so CR/LF or a quote in it ended the
    /// header and injected another one.
    func testNoFileNameCanEndTheContentDispositionHeader() {
        let evil = "a\"\r\nX-Evil: 1.txt"
        let h = QuickShareRules.contentDisposition(filename: evil)
        XCTAssertFalse(h.contains("\r") || h.contains("\n"), h)
        XCTAssertEqual(h.filter { $0 == "\"" }.count, 2, "only the two quotes around the fallback: \(h)")
        XCTAssertTrue(h.hasPrefix("attachment; filename=\"a___X-Evil: 1.txt\"; filename*=UTF-8''"), h)
        XCTAssertTrue(h.hasSuffix("a%22%0D%0AX-Evil%3A%201.txt"), h)

        let vi = QuickShareRules.contentDisposition(filename: "Báo cáo.pdf")
        XCTAssertTrue(vi.contains("filename=\"B_o c_o.pdf\""), "non-ASCII becomes _ in the fallback: \(vi)")
        XCTAssertTrue(vi.hasSuffix("filename*=UTF-8''B%C3%A1o%20c%C3%A1o.pdf"), "the real name survives as RFC 5987: \(vi)")
        XCTAssertEqual(QuickShareRules.contentDisposition(filename: "plain.txt"),
                       "attachment; filename=\"plain.txt\"; filename*=UTF-8''plain.txt")
        XCTAssertFalse(QuickShareRules.contentDisposition(filename: "a\\b").contains("\\"), "a backslash would escape the quote")
    }

    /// One QR code opens this page; a file name is user text and must not become markup.
    func testTheIndexPageEscapesFileNamesAndLinksEveryShareByItsToken() {
        let evil = "<img src=x onerror=alert(1)>.png"
        let strings = QuickShareRules.IndexStrings(title: "T & <U>", empty: "nothing", footer: "f")
        let page = QuickShareRules.indexPage(entries: [
            .init(name: evil, token: "ab12", detail: "1 MB"),
            .init(name: "Báo cáo \"Q3\".pdf", token: "cd34", detail: "2 MB"),
        ], strings: strings)
        XCTAssertFalse(page.contains("<img"), "the file name rendered as markup")
        XCTAssertTrue(page.contains("&lt;img src=x onerror=alert(1)&gt;.png"))
        XCTAssertTrue(page.contains("href=\"/ab12\" download"), "links go by token, relative to whatever address the phone used")
        XCTAssertTrue(page.contains("href=\"/cd34\" download"))
        XCTAssertTrue(page.contains("Báo cáo &quot;Q3&quot;.pdf"))
        XCTAssertTrue(page.contains("<title>T &amp; &lt;U&gt;</title>"))
        XCTAssertTrue(page.contains("width=device-width"), "a phone page")
        XCTAssertFalse(page.contains("http://"), "no absolute address baked in")

        let empty = QuickShareRules.indexPage(entries: [], strings: strings)
        XCTAssertTrue(empty.contains("nothing")); XCTAssertFalse(empty.contains("<li>"))
        XCTAssertEqual(QuickShareRules.htmlEscape("a&b<c>d\"e'f"), "a&amp;b&lt;c&gt;d&quot;e&#39;f")
        XCTAssertEqual(QuickShareRules.htmlEscape("plain.txt"), "plain.txt")
    }

    func testSshAndScpArgumentsFailFastAndEndOptionsBeforeUserText() {
        let t = RemoteConnectRules.testArguments(host: "-oProxyCommand=touch /tmp/x", port: 2222, user: "me", keyPath: "")
        XCTAssertEqual(Array(t.prefix(6)), ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-p", "2222"])
        XCTAssertFalse(t.contains("-i"), "no key path ⇒ the agent / default identity")
        let dd = t.firstIndex(of: "--")
        XCTAssertNotNil(dd, "options end before the destination")
        XCTAssertEqual(t[(dd ?? 0) + 1], "me@-oProxyCommand=touch /tmp/x")
        XCTAssertEqual(t.last, "echo ok")

        let k = RemoteConnectRules.testArguments(host: "h", port: 22, user: "u", keyPath: "/k")
        XCTAssertEqual(k, ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-p", "22", "-i", "/k", "--", "u@h", "echo ok"])

        let u = RemoteConnectRules.uploadArguments(files: ["-rf.txt", "/a b"], host: "h", port: 22, user: "u", remotePath: "/srv", keyPath: "")
        XCTAssertEqual(u, ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-P", "22", "-r", "--", "-rf.txt", "/a b", "u@h:/srv"],
                       "scp's port flag is -P, and a file named like an option comes after --")
    }

    func testEveryKnownSshFailureHasAnExplanationAndTheKeysAreTheOnesTheControllerTranslates() throws {
        let cases: [(String, Int)] = [
            ("u@h: Permission denied (publickey).", 0),
            ("ssh: Could not resolve hostname nope: nodename nor servname provided", 1),
            ("ssh: connect to host h port 22: Connection refused", 2),
            ("ssh: connect to host h port 22: Operation timed out", 3),
            ("Host key verification failed.", 4),
        ]
        for (out, i) in cases { XCTAssertEqual(RemoteConnectRules.explanationKey(out), RemoteConnectRules.explanationKeys[i], out) }
        XCTAssertNil(RemoteConnectRules.explanationKey("scp: /srv: No such file or directory"), "unknown ⇒ the caller shows the last line")
        XCTAssertEqual(Set(RemoteConnectRules.explanationKeys).count, 5)
        let store = try L10nFixture.load()
        for k in RemoteConnectRules.explanationKeys { XCTAssertNotNil(store.entries[k], "missing from the L10n store: \(k)") }
    }

    func testBothConnectFeaturesAreCatalogRowsAndQuietStopsTheServer() {
        let qs = FeatureCatalog.def(.quickShare), rc = FeatureCatalog.def(.remoteConnect)
        XCTAssertEqual(qs.enabledKey, QuickShareRules.enabledKey)
        XCTAssertEqual(rc.enabledKey, RemoteConnectRules.enabledKey)
        XCTAssertEqual(qs.group, .connect); XCTAssertEqual(rc.group, .connect)
        XCTAssertTrue(qs.defaultOn && rc.defaultOn, "a permission switch: on changes nothing for people who never set it")
        XCTAssertEqual(qs.idle, .timerWhileActive, "an NWListener + the 60 s expiry sweep while a link is live")
        XCTAssertEqual(rc.idle, .nothingAtRest)
        let quiet = FeatureCatalog.bundles.first { $0.id == "quiet" }!
        XCTAssertTrue(quiet.turnOff.contains(.quickShare), "Yên tĩnh must stop a forgotten LAN server")
        XCTAssertFalse(quiet.turnOff.contains(.remoteConnect))
    }
}

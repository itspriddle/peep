import Testing

@testable import PeepCore

/// `HTMLSanitizerMode.processorOutput` (#106): the raw-HTML allowlist plus what Markdown
/// renderers write for ordinary syntax, and nothing that runs script or loads content.
@Suite("HTML sanitizer, processor output")
struct HTMLSanitizerProcessorModeTests {
    private func sanitize(_ html: String) -> String {
        HTMLSanitizer(mode: .processorOutput).sanitize(fragment: html)
    }

    @Test("class is kept, minus Peep's reserved names")
    func classes() {
        #expect(
            sanitize("<pre class=\"sourceCode  swift\"><code class=\"hljs-keyword\">x</code></pre>")
                == "<pre class=\"sourceCode swift\"><code class=\"hljs-keyword\">x</code></pre>")
        #expect(
            sanitize("<span class=\"markdown-body remote-image peep-find ok\">x</span>")
                == "<span class=\"ok\">x</span>")
        #expect(sanitize("<span class=\"peep-x\" class>x</span>") == "<span>x</span>")
        #expect(sanitize("<span class=\"a&quot;b\">x</span>") == "<span class=\"a&quot;b\">x</span>")
    }

    @Test("raw HTML mode still drops class")
    func rawModeUnchanged() {
        #expect(
            HTMLSanitizer().sanitize(fragment: "<span class=\"a\" id=\"b\">x</span>")
                == "<span id=\"user-content-b\">x</span>")
    }

    @Test("ids and names are kept as written")
    func identifiers() {
        #expect(sanitize("<h2 id=\"intro\">Intro</h2>") == "<h2 id=\"intro\">Intro</h2>")
        #expect(sanitize("<a name=\"fn1\" href=\"#fnref1\">1</a>") == "<a name=\"fn1\" href=\"#fnref1\">1</a>")
        #expect(sanitize("<span id=\"\">x</span>") == "<span>x</span>")
    }

    @Test("task-list checkboxes are kept, always disabled; other inputs are removed")
    func checkboxes() {
        #expect(
            sanitize("<p><input type=\"checkbox\" checked=\"\" onclick=\"x()\" />done</p>")
                == "<p><input type=\"checkbox\" checked disabled />done</p>")
        #expect(
            sanitize("<ul><li><input type=\"CHECKBOX\" checked class=\"task peep-x\">done</li></ul>")
                == "<ul><li><input type=\"checkbox\" class=\"task\" checked disabled>done</li></ul>")
        #expect(
            sanitize("<ul><li><input type=\"checkbox\" />todo</li></ul>")
                == "<ul><li><input type=\"checkbox\" disabled />todo</li></ul>")
        #expect(sanitize("<input type=\"text\" value=\"x\"><input>").isEmpty)
    }

    @Test("footnote sections are kept")
    func sections() {
        #expect(
            sanitize("<section class=\"footnotes\"><ol><li id=\"fn1\">x</li></ol></section>")
                == "<section class=\"footnotes\"><ol><li id=\"fn1\">x</li></ol></section>")
    }

    @Test("script, style, event handlers, foreign content, and bad URLs are still removed")
    func hostile() {
        #expect(sanitize("<script>alert(1)</script><style>p{}</style>ok") == "ok")
        #expect(sanitize("<p onclick=\"x()\" style=\"color:red\">t</p>") == "<p>t</p>")
        #expect(sanitize("<a href=\"javascript:alert(1)\">l</a>") == "<a>l</a>")
        #expect(sanitize("<svg><script>x</script></svg><math><mi>x</mi></math>t") == "t")
        #expect(sanitize("<iframe src=\"https://e.com\"></iframe><form><button>b</button></form>").isEmpty)
        #expect(sanitize("<p>open") == "<p>open</p>")
    }
}

import Foundation
import PeepCore
import Testing

@testable import PeepCLIKit

/// `--processor` and `--processor-arg` (#106): another renderer in place of Peep's, its HTML
/// sanitized and wrapped in Peep's page, failing loudly. The runner and its Ctrl-C handling are
/// `--preprocessor`'s (`CustomProgramCommand`, covered end to end in `PreprocessorTests`).
@Suite("Processor")
struct ProcessorTests {
    @Test("--processor renders the program's HTML, sanitized, for the body after the frontmatter")
    func fragment() async throws {
        let folder = try TempFolder()
        let document = try folder.file("doc.md", "---\ntitle: T\n---\n# Body\n")
        let script = try PreprocessorTests.script("html-processor", in: folder)
        let result = await CLIHarness.run(["--fragment", "--processor", script, document])
        #expect(result.status == 0)
        #expect(result.stdout.contains("<pre class=\"body\"># Body\n</pre>"))
        #expect(result.stdout.contains("<h1 id=\"processed-title\">"))
        #expect(!result.stdout.contains("<script"))
        #expect(!result.stdout.contains("title: T"))
        #expect(result.stderr.isEmpty)
    }

    @Test("--html wraps it in Peep's page, titled from the frontmatter")
    func page() async throws {
        let folder = try TempFolder()
        let document = try folder.file("doc.md", "---\ntitle: From Frontmatter\n---\nx\n")
        let script = try PreprocessorTests.script("html-processor", in: folder)
        let result = await CLIHarness.run(["--html", "--processor", script, document])
        #expect(result.status == 0)
        #expect(result.stdout.contains("<title>From Frontmatter</title>"))
        #expect(result.stdout.contains("Content-Security-Policy"))
        #expect(result.stdout.contains("<article class=\"markdown-body\">"))
    }

    @Test("arguments are passed as given, and values may look like options")
    func arguments() async throws {
        let folder = try TempFolder()
        let script = try PreprocessorTests.script("report", in: folder)
        let result = await CLIHarness.run(
            ["--fragment", "--processor", script, "--processor-arg", "--html", "--processor-arg", "two words"],
            stdin: Data("x".utf8))
        #expect(result.status == 0)
        // The report script writes plain text, which is the page body as text.
        #expect(result.stdout.contains("arg=--html\narg=two words"))
    }

    @Test("it runs after --preprocessor, on its output")
    func afterPreprocessor() async throws {
        let folder = try TempFolder()
        let upcase = try PreprocessorTests.script("upcase", in: folder)
        let processor = try PreprocessorTests.script("html-processor", in: folder)
        let result = await CLIHarness.run(
            ["--fragment", "--preprocessor", upcase, "--processor", processor], stdin: Data("# piped\n".utf8))
        #expect(result.status == 0)
        #expect(result.stdout.contains("<pre class=\"body\"># PIPED\n</pre>"))
    }

    @Test("a failing processor exits 70 with its stderr tail, and nothing is written")
    func failure() async throws {
        let folder = try TempFolder()
        let document = try folder.file("doc.md", "# Title\n")
        let script = try PreprocessorTests.script("fail", in: folder)
        let result = await CLIHarness.run(["--html", "--processor", script, document])
        #expect(result.status == 70)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("doc.md: The processor exited with status 3."))
        #expect(result.stderr.contains("something went wrong"))
    }

    @Test("a missing processor exits 70")
    func missing() async throws {
        let folder = try TempFolder()
        let document = try folder.file("doc.md", "# Title\n")
        let result = await CLIHarness.run(["--html", "--processor", folder.path("nope"), document])
        #expect(result.status == 70)
        #expect(result.stderr.contains("The processor can’t run"))
    }

    @Test("without --processor nothing runs, even when the document asks")
    func optInOnly() async {
        let result = await CLIHarness.run(
            ["--fragment"], stdin: Data("---\npeep:\n  processor: /bin/echo\n---\n# plain\n".utf8))
        #expect(result.status == 0)
        #expect(result.stdout.contains(">plain</h1>"))
    }

    @Test(
        "processor flags need HTML output, and --processor-arg needs --processor",
        arguments: [
            ["--processor", "/bin/cat", "doc.md"],
            ["--html", "--processor-arg", "x", "doc.md"],
            ["--html", "--processor", "", "doc.md"],
        ])
    func usage(_ arguments: [String]) async {
        let result = await CLIHarness.run(arguments)
        #expect(result.status == 64)
        #expect(result.stdout.isEmpty)
        #expect(result.openedInApp.isEmpty)
    }

    @Test("end to end: a relative --processor path runs from the working directory")
    func endToEnd() throws {
        let folder = try TempFolder()
        try folder.file("doc.md", "# Title\n")
        _ = try PreprocessorTests.script("html-processor", in: folder)
        guard
            let result = try CLIBinary.run(
                ["--fragment", "--processor", "html-processor.sh", "doc.md"], in: folder.url)
        else { return }
        #expect(result.status == 0)
        #expect(result.stdout.contains("<pre class=\"body\"># Title\n</pre>"))
    }
}

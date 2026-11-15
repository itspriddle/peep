import Foundation
import Testing

@testable import PeepCore

/// The custom processor (#106): an external renderer in place of stages 4-6, its output always
/// sanitized. Nested in the preprocessor suite so it runs serialized with it: the runner's
/// descriptor leak checks count every run in flight.
extension CustomPreprocessorTests {
    @Suite("Custom processor")
    struct CustomProcessorTests {
        /// What `html-processor.sh` writes before the escaped body.
        private static let source = """
            ---
            title: From Frontmatter
            peep:
              theme: serif
              flavor: commonmark
            ---
            # Markdown <Heading>

            One two three ~~four~~.

            """

        private func render(
            _ source: String = Self.source, options: RenderOptions = RenderOptions(), script: String = "html-processor"
        ) async throws -> RenderedDocument {
            let fixtures = try PreprocessorFixtures()
            let processor = try fixtures.processor(script)
            return try await HTMLRenderer(options: options).render(
                source, preprocessor: nil, processor: processor.for(documentURL: nil))
        }

        // MARK: - Contract

        @Test("the processor gets the body after the frontmatter, and its HTML is the page body")
        func bodyInFragmentOut() async throws {
            let rendered = try await render()
            #expect(
                rendered.html.contains(
                    "<pre class=\"body\"># Markdown &lt;Heading&gt;\n\nOne two three ~~four~~.\n</pre>"))
            #expect(!rendered.html.contains("title: From Frontmatter"))
            #expect(rendered.frontmatter?.title == "From Frontmatter")
            #expect(rendered.title == "From Frontmatter")
        }

        @Test("the frontmatter table is Peep's, before the processor's HTML")
        func frontmatterTable() async throws {
            var options = RenderOptions()
            options.frontmatterDisplay = .table
            let rendered = try await render(options: options)
            let table = try #require(rendered.html.range(of: "From Frontmatter"))
            let body = try #require(rendered.html.range(of: "<h1"))
            #expect(table.lowerBound < body.lowerBound)
        }

        @Test("document overrides still apply: the theme is reported and the flavor is resolved")
        func overridesApply() async throws {
            let rendered = try await render()
            #expect(rendered.overrides.theme == "serif")
            #expect(rendered.flavor == .commonmark)
        }

        @Test("headings come from the processor's HTML, with slugs and anchors; an id of its own is kept")
        func headings() async throws {
            let rendered = try await render("No frontmatter.\n")
            #expect(rendered.headings.map(\.text) == ["Processed Title", "Own Id"])
            #expect(rendered.headings.map(\.slug) == ["processed-title", "own-id"])
            #expect(rendered.headings.allSatisfy { $0.sourceLine == nil })
            #expect(rendered.title == "Processed Title")
            #expect(
                rendered.html.contains(
                    "<h1 id=\"processed-title\"><a class=\"anchor\" aria-hidden=\"true\" href=\"#processed-title\"></a>"
                ))
            // The heading's own id is the slug, so the anchor link doesn't repeat it.
            #expect(
                rendered.html.contains(
                    "<h2 id=\"own-id\"><a class=\"anchor\" aria-hidden=\"true\" href=\"#own-id\"></a>"))
        }

        @Test("the output is sanitized even when raw HTML sanitizing is off")
        func alwaysSanitized() async throws {
            let rendered = try await render(options: RenderOptions(sanitize: false))
            #expect(!rendered.html.contains("<script"))
            #expect(!rendered.html.contains("alert(1)"))
            #expect(!rendered.html.contains("onclick"))
            #expect(!rendered.html.contains("style="))
            #expect(rendered.html.contains("<p class=\"lead\">"))
        }

        @Test("remote images in the output follow the remote image policy")
        func remoteImages() throws {
            var options = RenderOptions()
            options.remoteImages = .block
            let renderer = HTMLRenderer(options: options)
            let rendered = renderer.render(
                processedHTML: "<p><img src=\"https://example.com/a.png\" alt=\"A\"></p>", of: renderer.prepare("x\n"))
            #expect(rendered.blockedRemoteImages.count == 1)
            #expect(!rendered.html.contains("<img"))
            #expect(rendered.html.contains("remote-image"))
        }

        @Test("the word count is of the body, without frontmatter")
        func wordCount() async throws {
            let rendered = try await render()
            #expect(rendered.wordCount == 5)  // Markdown One two three four (`<Heading>` is raw HTML)
        }

        @Test("the processor runs after the preprocessor, on the preprocessed body")
        func afterPreprocessor() async throws {
            let fixtures = try PreprocessorFixtures()
            let rendered = try await HTMLRenderer().render(
                "# hello\n", preprocessor: try fixtures.preprocessor("upcase").for(documentURL: nil),
                processor: try fixtures.processor("html-processor").for(documentURL: nil))
            #expect(rendered.html.contains("<pre class=\"body\"># HELLO\n</pre>"))
        }

        // MARK: - Failures

        @Test("failures are the processor's, by name")
        func failureNamesProcessor() async throws {
            let fixtures = try PreprocessorFixtures()
            let error = await #expect(throws: PreprocessorError.self) {
                try await fixtures.processor("fail").run(input: Data("x".utf8), documentURL: nil)
            }
            #expect(error?.kind == .processor)
            #expect(error?.message == "The processor exited with status 3.")
            #expect(error?.standardError == "something went wrong\n")
        }

        @Test("an executable that went away is reported as the processor's")
        func missingExecutable() async throws {
            let fixtures = try PreprocessorFixtures()
            let processor = try fixtures.processor("fail")
            try FileManager.default.removeItem(atPath: processor.configuration.executablePath)
            let error = await #expect(throws: PreprocessorError.self) {
                try await processor.run(input: Data(), documentURL: nil)
            }
            #expect(error?.kind == .processor)
            #expect(error?.message.hasPrefix("The processor can’t run:") == true)
        }

        @Test("a hanging processor times out and leaves no descriptors open")
        func timeout() async throws {
            let fixtures = try PreprocessorFixtures()
            let error = await #expect(throws: PreprocessorError.self) {
                try await fixtures.processor("hang").run(input: Data(), documentURL: nil)
            }
            #expect(error?.reason.kind == "timedOut")
            #expect(PreprocessorDescriptors.openCount == 0)
        }
    }
}

extension PreprocessorFixtures {
    func processor(
        _ name: String, arguments: [String] = [], limits: PreprocessorLimits = shortLimits
    ) throws -> CustomProcessor {
        let configuration = try PreprocessorConfiguration(
            executablePath: try script(name), arguments: arguments, limits: limits)
        return CustomProcessor(configuration: configuration)
    }
}

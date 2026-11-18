import Testing

@testable import PeepCore

@Suite("Mermaid blocks")
struct MermaidBlocksTests {
    func render(_ markdown: String, options: RenderOptions = RenderOptions()) -> RenderedDocument {
        HTMLRenderer(options: options).render(markdown)
    }

    @Test(
        "a fenced block whose language is mermaid, in any case, is a diagram",
        arguments: ["mermaid", "Mermaid", "MERMAID", "mermaid title=x"])
    func languages(info: String) {
        #expect(render("```\(info)\ngraph TD\n  A --> B\n```\n").hasMermaidBlocks)
    }

    @Test(
        "other blocks are not",
        arguments: [
            "```mermaidx\ngraph TD\n```\n", "```js\nmermaid\n```\n", "    mermaid\n", "`mermaid`\n",
            "~~~\nmermaid\n~~~\n", "# mermaid\n",
        ])
    func notDiagrams(markdown: String) {
        #expect(!render(markdown).hasMermaidBlocks)
    }

    @Test("found inside quotes, lists, alerts, and footnotes")
    func nested() {
        let fence = "```mermaid\n  graph TD\n  ```"
        #expect(render("> ```mermaid\n> graph TD\n> ```\n").hasMermaidBlocks)
        #expect(render("- item\n\n  \(fence)\n").hasMermaidBlocks)
        #expect(render("> [!NOTE]\n> ```mermaid\n> graph TD\n> ```\n").hasMermaidBlocks)
        #expect(render("Text[^1]\n\n[^1]: Note\n\n    ```mermaid\n    graph TD\n    ```\n").hasMermaidBlocks)
    }

    @Test("the HTML keeps the code block, in every flavor")
    func htmlUnchanged() {
        for flavor in [Flavor.gfm, .commonmark] {
            var options = RenderOptions()
            options.flavor = flavor
            let rendered = render("```mermaid\ngraph TD\n  A --> B\n```\n", options: options)
            #expect(rendered.hasMermaidBlocks)
            #expect(
                rendered.html.contains("<pre><code class=\"language-mermaid\">graph TD\n  A --&gt; B\n</code></pre>"))
        }
    }

    @Test("with diagrams off, nothing is drawn")
    func diagramsOff() {
        var options = RenderOptions()
        options.diagrams = false
        let rendered = render("```mermaid\ngraph TD\n```\n", options: options)
        #expect(!rendered.hasMermaidBlocks)
        #expect(rendered.html.contains("<code class=\"language-mermaid\">"))
    }

    @Test("a processor's page reads the body as Peep parses it")
    func processor() {
        let renderer = HTMLRenderer()
        let prepared = renderer.prepare("```mermaid\ngraph TD\n```\n")
        #expect(renderer.render(processedHTML: "<p>x</p>", of: prepared).hasMermaidBlocks)
        let plain = renderer.prepare("text\n")
        #expect(!renderer.render(processedHTML: "<p>x</p>", of: plain).hasMermaidBlocks)
    }
}

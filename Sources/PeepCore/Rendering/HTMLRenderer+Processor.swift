// The custom processor's side of the pipeline (#106): its HTML in place of stages 4-6.

extension HTMLRenderer {
    /// Finishes a document whose body a custom processor rendered (`SourceProcessor`):
    /// `processedHTML` is the processor's output for `prepared.body`.
    ///
    /// The output is untrusted: it is always sanitized, under `HTMLSanitizerMode.processorOutput`
    /// (whatever `options.sanitize` says), with `options`' remote image policy and link root.
    /// Headings come from the sanitized HTML's `<h1>`–`<h6>` with GitHub-style slugs, and each
    /// gets an anchor (a heading with its own `id` keeps it; the slug goes on the anchor link),
    /// so the outline and in-page links work. Headings have no source line: the processor's
    /// HTML has no `data-source-line`. The word count is of the body as Peep parses it with the
    /// resolved flavor, which is close to what any renderer shows; so is `hasMermaidBlocks` (the
    /// viewer then draws any `language-mermaid` code blocks in the processor's HTML).
    public func render(processedHTML: String, of prepared: PreparedSource) -> RenderedDocument {
        let renderer = prepared.renderer(from: self)
        var blockedRemoteImages: [RemoteImage] = []
        let clean = HTMLSanitizer(for: renderer.options, mode: .processorOutput)
            .sanitize(fragment: processedHTML, blockedImages: &blockedRemoteImages)

        let tree = MarkdownNode(.document, children: [MarkdownNode(.htmlBlock(clean))])
        let collection = HeadingCollection(tree, includingRawHTML: true)
        var body = clean
        if renderer.options.headingAnchors,
            case .htmlBlock(let anchored)? = collection.anchoringRawHeadings(in: tree).children.first?.kind
        {
            body = anchored
        }

        var output = HTMLOutput(capacity: body.utf8.count + 64)
        if let frontmatter = prepared.frontmatter, options.frontmatterDisplay == .table {
            FrontmatterHTML.render(frontmatter, into: &output)
        }
        output.raw(body)

        let parsed = MarkdownParser(extensions: renderer.options.flavor.extensions)
            .parse(prepared.body, lineOffset: prepared.lineOffset)
        return RenderedDocument(
            html: output.string,
            title: Self.title(frontmatter: prepared.frontmatter, headings: collection.headings),
            headings: collection.headings,
            frontmatter: prepared.frontmatter,
            blockedRemoteImages: blockedRemoteImages,
            overrides: prepared.overrides,
            flavor: renderer.options.flavor,
            wordCount: WordCount.count(in: parsed),
            hasMermaidBlocks: MermaidBlocks.contains(in: parsed)
        )
    }
}

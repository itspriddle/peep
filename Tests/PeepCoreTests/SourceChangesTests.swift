import Testing

@testable import PeepCore

@Suite("Source changes")
struct SourceChangesTests {
    static let base = "# Title\n\nFirst paragraph.\n\nSecond paragraph.\n\nThird paragraph.\n"

    @Test("Identical text has no changes")
    func identical() {
        #expect(SourceChanges.between(old: Self.base, new: Self.base).isEmpty)
    }

    @Test("An edited line is changed")
    func editedLine() {
        let new = Self.base.replacingOccurrences(of: "Second paragraph.", with: "Second, edited.")
        #expect(SourceChanges.between(old: Self.base, new: new) == SourceChanges(changedLines: [5...5]))
    }

    @Test("Inserted lines are changed, coalesced into one range")
    func insertedLines() {
        let new = Self.base.replacingOccurrences(of: "Second paragraph.\n", with: "Second paragraph.\nmore\nand more\n")
        #expect(SourceChanges.between(old: Self.base, new: new) == SourceChanges(changedLines: [6...7]))
    }

    @Test("A new block is changed, not the blank line before it")
    func newBlock() {
        let new = Self.base + "\nFourth paragraph.\n"
        #expect(SourceChanges.between(old: Self.base, new: new) == SourceChanges(changedLines: [9...9]))
    }

    @Test("A removed block is a deletion before the next block")
    func removedBlock() {
        let new = Self.base.replacingOccurrences(of: "Second paragraph.\n\n", with: "")
        #expect(SourceChanges.between(old: Self.base, new: new) == SourceChanges(deletionsBefore: [5]))
    }

    @Test("A removed block whose blank line goes first still points at the next block")
    func removedBlockLeadingBlank() {
        let new = Self.base.replacingOccurrences(of: "\n\nSecond paragraph.", with: "")
        let changes = SourceChanges.between(old: Self.base, new: new)
        #expect(changes == SourceChanges(deletionsBefore: [5]))
    }

    @Test("Removing the end of the file is a deletion at the end")
    func removedAtEnd() {
        let new = "# Title\n\nFirst paragraph.\n"
        #expect(SourceChanges.between(old: Self.base, new: new) == SourceChanges(deletedAtEnd: true))
        let trailingBlank = "# Title\n\nFirst paragraph.\n\n"
        #expect(SourceChanges.between(old: Self.base, new: trailingBlank) == SourceChanges(deletedAtEnd: true))
    }

    @Test("Removing the start of the file is a deletion before the first line")
    func removedAtStart() {
        let new = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph.\n"
        #expect(SourceChanges.between(old: Self.base, new: new) == SourceChanges(deletionsBefore: [1]))
    }

    @Test("A replaced line is a change, not a deletion")
    func replacedLine() {
        let new = Self.base.replacingOccurrences(of: "Third paragraph.", with: "Another one.")
        #expect(SourceChanges.between(old: Self.base, new: new) == SourceChanges(changedLines: [7...7]))
    }

    @Test("Separate edits are separate ranges")
    func separateEdits() {
        let new = Self.base.replacingOccurrences(of: "# Title", with: "# New title")
            .replacingOccurrences(of: "Third paragraph.", with: "Third, edited.")
        #expect(SourceChanges.between(old: Self.base, new: new) == SourceChanges(changedLines: [1...1, 7...7]))
    }

    @Test("Blank-only edits are not changes")
    func blankOnly() {
        let new = Self.base.replacingOccurrences(of: "\n\nThird", with: "\n\n\n  \nThird")
        #expect(SourceChanges.between(old: Self.base, new: new).isEmpty)
    }

    @Test("Frontmatter edits count lines like the renderer")
    func frontmatter() {
        let old = "---\ntitle: A\n---\n\n# Body\n"
        let new = "---\ntitle: B\n---\n\n# Body\n"
        #expect(SourceChanges.between(old: old, new: new) == SourceChanges(changedLines: [2...2]))
    }

    @Test("CRLF and CR are one line break each", arguments: ["\r\n", "\r"])
    func lineEndings(_ ending: String) {
        let old = ["a", "", "b", "", "c"].joined(separator: ending)
        let new = ["a", "", "b2", "", "c"].joined(separator: ending)
        #expect(SourceChanges.between(old: old, new: new) == SourceChanges(changedLines: [3...3]))
        #expect(SourceChanges.lines(of: "a\r\nb\rc\n") == ["a", "b", "c"])
    }

    @Test("Other Unicode line separators don't split lines")
    func unicodeSeparators() {
        #expect(SourceChanges.lines(of: "a\u{2028}b\u{0085}c\u{0C}d") == ["a\u{2028}b\u{0085}c\u{0C}d"])
    }

    @Test("Empty text before or after")
    func empty() {
        #expect(SourceChanges.between(old: "", new: "# Hi\n") == SourceChanges(changedLines: [1...1]))
        #expect(SourceChanges.between(old: "# Hi\n", new: "") == SourceChanges(deletedAtEnd: true))
        #expect(SourceChanges.between(old: "", new: "").isEmpty)
    }

    @Test("A rewrite larger than the limit is one changed range")
    func overLimit() {
        let count = SourceChanges.lineDiffLimit + 10
        let old = (0..<count).map { "old \($0)" }.joined(separator: "\n")
        let new = "# Same\n" + (0..<count).map { "new \($0)" }.joined(separator: "\n") + "\n# End"
        let changes = SourceChanges.between(old: "# Same\n" + old + "\n# End", new: new)
        #expect(changes == SourceChanges(changedLines: [2...(count + 1)]))
    }

    @Test("Removing more than the limit is one deletion")
    func overLimitRemoval() {
        let middle = (0..<(SourceChanges.lineDiffLimit + 1)).map { "line \($0)" }.joined(separator: "\n")
        let changes = SourceChanges.between(old: "# A\n" + middle + "\n# B\n", new: "# A\n# B\n")
        #expect(changes == SourceChanges(deletionsBefore: [2]))
    }
}

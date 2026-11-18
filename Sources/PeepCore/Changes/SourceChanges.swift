/// Which lines of a document's new text changed since its previous text: what the app marks
/// after a live reload ("Highlight changes when a file is saved").
///
/// Lines are 1-based lines of the new text, counted as `data-source-line` counts them (a CRLF or
/// CR line ending is one line break, like LF), so the page can map them to rendered blocks.
/// Blank lines (spaces and tabs only) are never reported: they separate blocks, and marking the
/// block before one would point at text that didn't change.
public struct SourceChanges: Sendable, Equatable {
    /// Lines added or edited in the new text, in order, coalesced into ranges.
    public var changedLines: [ClosedRange<Int>]
    /// For each place lines were removed with nothing added in their stead: the line of the new
    /// text that now follows the removal (past any blank lines), in order.
    public var deletionsBefore: [Int]
    /// Whether lines were removed from the end, with only blank lines (or nothing) after them.
    public var deletedAtEnd: Bool

    public init(changedLines: [ClosedRange<Int>] = [], deletionsBefore: [Int] = [], deletedAtEnd: Bool = false) {
        self.changedLines = changedLines
        self.deletionsBefore = deletionsBefore
        self.deletedAtEnd = deletedAtEnd
    }

    /// Whether nothing changed (or only blank lines did).
    public var isEmpty: Bool { changedLines.isEmpty && deletionsBefore.isEmpty && !deletedAtEnd }

    /// The most lines on either side of the changed middle (what remains after the common first
    /// and last lines are set aside) that are diffed line by line. A longer middle is reported as
    /// one changed range, so a rewrite of a large file can't stall: the diff is O((N + M) × D).
    public static let lineDiffLimit = 2000

    /// The changes from `old` to `new`.
    public static func between(old: String, new: String) -> SourceChanges {
        let oldLines = lines(of: old)
        let newLines = lines(of: new)
        let prefix = commonPrefixCount(oldLines, newLines)
        let suffix = commonSuffixCount(oldLines, newLines, excludingPrefix: prefix)
        let oldMiddle = oldLines[prefix..<(oldLines.count - suffix)]
        let newMiddle = newLines[prefix..<(newLines.count - suffix)]

        var builder = Builder(newLines: newLines)
        if oldMiddle.count > lineDiffLimit || newMiddle.count > lineDiffLimit {
            if newMiddle.isEmpty {
                builder.deleted(beforeIndex: prefix)
            } else {
                for index in newMiddle.indices {
                    builder.changed(index)
                }
            }
            return builder.result()
        }

        walk(old: oldMiddle, new: newMiddle, offset: prefix, into: &builder)
        return builder.result()
    }

    /// Diffs the middles line by line and walks both in step: inserted lines are changed, and a
    /// removal run that no non-blank insertion follows is a deletion, placed before the next
    /// common line (or the end of the middle). `offset` is the middles' first index.
    private static func walk(
        old oldMiddle: ArraySlice<Substring>, new newMiddle: ArraySlice<Substring>, offset prefix: Int,
        into builder: inout Builder
    ) {
        let difference = Array(newMiddle).difference(from: Array(oldMiddle))
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _):
                removed.insert(offset)
            case .insert(let offset, _, _):
                inserted.insert(offset)
            }
        }
        var oldIndex = 0
        var newIndex = 0
        var pendingDeletion = false
        while oldIndex < oldMiddle.count || newIndex < newMiddle.count {
            if oldIndex < oldMiddle.count, removed.contains(oldIndex) {
                pendingDeletion = true
                oldIndex += 1
            } else if newIndex < newMiddle.count, inserted.contains(newIndex) {
                if builder.changed(prefix + newIndex) {
                    pendingDeletion = false
                }
                newIndex += 1
            } else {
                if pendingDeletion {
                    builder.deleted(beforeIndex: prefix + newIndex)
                    pendingDeletion = false
                }
                oldIndex += 1
                newIndex += 1
            }
        }
        if pendingDeletion {
            builder.deleted(beforeIndex: prefix + newMiddle.count)
        }
    }

    /// Collects changed lines and deletions as 0-based indexes into the new lines.
    private struct Builder {
        let newLines: [Substring]
        private var changed: [Int] = []
        private var deletions: [Int] = []

        init(newLines: [Substring]) {
            self.newLines = newLines
        }

        /// Records `index` as changed unless it is blank; returns whether it was recorded.
        @discardableResult
        mutating func changed(_ index: Int) -> Bool {
            guard !SourceChanges.isBlank(newLines[index]) else {
                return false
            }
            changed.append(index)
            return true
        }

        /// Records a deletion before `index` (moved past blank lines).
        mutating func deleted(beforeIndex index: Int) {
            var index = index
            while index < newLines.count, SourceChanges.isBlank(newLines[index]) {
                index += 1
            }
            deletions.append(index)
        }

        func result() -> SourceChanges {
            var ranges: [ClosedRange<Int>] = []
            for index in changed {
                let line = index + 1
                if let last = ranges.last, last.upperBound + 1 == line {
                    ranges[ranges.count - 1] = last.lowerBound...line
                } else {
                    ranges.append(line...line)
                }
            }
            let changedLines = Set(changed)
            var seen = Set<Int>()
            let lines = deletions.filter {
                $0 < newLines.count && !changedLines.contains($0) && seen.insert($0).inserted
            }
            return SourceChanges(
                changedLines: ranges, deletionsBefore: lines.map { $0 + 1 },
                deletedAtEnd: deletions.contains(newLines.count))
        }
    }

    /// `text` split into lines at LF, CRLF, and CR (the line breaks the parser counts), without
    /// the breaks. A final line break ends the last line rather than starting an empty one.
    static func lines(of text: String) -> [Substring] {
        var lines: [Substring] = []
        let utf8 = text.utf8
        var start = utf8.startIndex
        var index = utf8.startIndex
        while index < utf8.endIndex {
            let byte = utf8[index]
            if byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") {
                lines.append(text[start..<index])
                var next = utf8.index(after: index)
                if byte == UInt8(ascii: "\r"), next < utf8.endIndex, utf8[next] == UInt8(ascii: "\n") {
                    next = utf8.index(after: next)
                }
                start = next
                index = next
            } else {
                index = utf8.index(after: index)
            }
        }
        if start < utf8.endIndex {
            lines.append(text[start..<utf8.endIndex])
        }
        return lines
    }

    static func isBlank(_ line: Substring) -> Bool {
        line.utf8.allSatisfy { $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\t") }
    }

    private static func commonPrefixCount(_ old: [Substring], _ new: [Substring]) -> Int {
        var count = 0
        while count < old.count, count < new.count, old[count] == new[count] {
            count += 1
        }
        return count
    }

    private static func commonSuffixCount(
        _ old: [Substring], _ new: [Substring], excludingPrefix prefix: Int
    ) -> Int {
        var count = 0
        while count < old.count - prefix, count < new.count - prefix,
            old[old.count - 1 - count] == new[new.count - 1 - count]
        {
            count += 1
        }
        return count
    }
}

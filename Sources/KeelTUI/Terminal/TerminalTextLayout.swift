import Foundation

public struct TerminalStyledTextSegment: Equatable {
    public var text: String
    public var style: TerminalStyle

    public init(_ text: String, style: TerminalStyle = .plain) {
        self.text = text
        self.style = style
    }
}

public enum TerminalTextWrapPolicy: Equatable, Sendable {
    /// Prefer whitespace boundaries and hard-wrap tokens that have no usable boundary.
    case wordBoundary
}

public enum TerminalTextLayout {
    private struct StyledCharacter {
        var character: Character
        var style: TerminalStyle
    }

    public static func wrap(
        _ text: String,
        width: Int,
        style: TerminalStyle = .plain,
        continuationIndent: String = "",
        policy: TerminalTextWrapPolicy = .wordBoundary
    ) -> [TerminalModalLine] {
        wrap(
            [
                TerminalModalLine(
                    text: text,
                    style: style,
                    continuationIndent: continuationIndent
                )
            ],
            width: width,
            policy: policy
        )
    }

    public static func wrap(
        _ lines: [TerminalModalLine],
        width: Int,
        policy: TerminalTextWrapPolicy = .wordBoundary
    ) -> [TerminalModalLine] {
        lines.flatMap { line in
            logicalLines(from: line).flatMap { logicalLine in
                wrapLogicalLine(
                    logicalLine.characters,
                    width: width,
                    style: logicalLine.style,
                    continuationIndent: line.continuationIndent,
                    continuationIndentStyle: line.continuationIndentStyle,
                    policy: policy
                )
            }
        }
    }

    private static func logicalLines(
        from line: TerminalModalLine
    ) -> [(characters: [StyledCharacter], style: TerminalStyle)] {
        var result: [(characters: [StyledCharacter], style: TerminalStyle)] = []
        var characters: [StyledCharacter] = []
        var emptyLineStyle = line.style

        for segment in line.segments {
            for character in segment.text {
                let value = String(character)
                if value == "\n" || value == "\r" || value == "\r\n" {
                    result.append((characters, characters.first?.style ?? emptyLineStyle))
                    characters = []
                    emptyLineStyle = segment.style
                } else {
                    characters.append(StyledCharacter(character: character, style: segment.style))
                }
            }
        }
        result.append((characters, characters.first?.style ?? emptyLineStyle))
        return result
    }

    private static func wrapLogicalLine(
        _ characters: [StyledCharacter],
        width: Int,
        style: TerminalStyle,
        continuationIndent: String,
        continuationIndentStyle: TerminalStyle,
        policy: TerminalTextWrapPolicy
    ) -> [TerminalModalLine] {
        guard width > 0 else {
            return [TerminalModalLine(text: "", style: style)]
        }
        guard !characters.isEmpty else {
            return [TerminalModalLine(text: "", style: style)]
        }

        var remaining = characters
        var result: [TerminalModalLine] = []
        var isContinuation = false

        while !remaining.isEmpty {
            let indent = isContinuation
                ? TerminalDisplayWidth.truncate(continuationIndent, toWidth: max(0, width - 1))
                : ""
            let indentWidth = TerminalDisplayWidth.width(of: indent)
            let availableWidth = max(1, width - indentWidth)

            var fitCount = 0
            var usedWidth = 0
            for unit in remaining {
                let characterWidth = TerminalDisplayWidth.width(of: unit.character)
                if usedWidth + characterWidth > availableWidth {
                    break
                }
                fitCount += 1
                usedWidth += characterWidth
            }

            if fitCount == 0 {
                fitCount = 1
            }

            var takeCount = fitCount
            var consumeCount = fitCount
            if fitCount < remaining.count, policy == .wordBoundary {
                var boundary: Int?
                var sawNonWhitespace = false
                for index in 0 ..< fitCount {
                    if remaining[index].character.isWhitespace {
                        if sawNonWhitespace {
                            boundary = index
                        }
                    } else {
                        sawNonWhitespace = true
                    }
                }

                if sawNonWhitespace, remaining[fitCount].character.isWhitespace {
                    boundary = fitCount
                }

                if let boundary {
                    takeCount = boundary
                    consumeCount = boundary
                    while consumeCount < remaining.count, remaining[consumeCount].character.isWhitespace {
                        consumeCount += 1
                    }
                }
            }

            if takeCount == 0 {
                takeCount = fitCount
                consumeCount = fitCount
            }

            var output: [StyledCharacter] = []
            if !indent.isEmpty {
                output.append(contentsOf: indent.map {
                    StyledCharacter(character: $0, style: continuationIndentStyle)
                })
            }
            output.append(contentsOf: remaining.prefix(takeCount))
            result.append(makeLine(from: output, fallbackStyle: style))
            remaining.removeFirst(min(consumeCount, remaining.count))
            isContinuation = true
        }

        return result
    }

    private static func makeLine(
        from characters: [StyledCharacter],
        fallbackStyle: TerminalStyle
    ) -> TerminalModalLine {
        guard !characters.isEmpty else {
            return TerminalModalLine(text: "", style: fallbackStyle)
        }

        var segments: [TerminalStyledTextSegment] = []
        for unit in characters {
            if let lastIndex = segments.indices.last, segments[lastIndex].style == unit.style {
                segments[lastIndex].text.append(unit.character)
            } else {
                segments.append(TerminalStyledTextSegment(String(unit.character), style: unit.style))
            }
        }
        return TerminalModalLine(segments: segments)
    }
}

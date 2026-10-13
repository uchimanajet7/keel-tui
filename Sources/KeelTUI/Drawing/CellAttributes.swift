import Foundation

struct CellAttributes: Equatable {
    var bold: Bool
    var dim: Bool
    var italic: Bool
    var underline: Bool
    var strikethrough: Bool
    var inverted: Bool

    init(
        bold: Bool = false,
        dim: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false,
        inverted: Bool = false
    ) {
        self.bold = bold
        self.dim = dim
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.inverted = inverted
    }
}

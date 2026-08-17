import Foundation

public enum TerminalKey: Equatable {
    case character(Character)
    case enter
    case tab
    case escape
    case backspace
    case ctrlC
    case ctrlD
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case home
    case end
    case pageUp
    case pageDown
}

public struct TerminalKeyDecoder {
    private enum State {
        case ground
        case escape
        case csi
        case csiParameter(String)
    }

    private var state: State = .ground

    public init() {}

    public mutating func parse(data: Data) -> [TerminalKey] {
        guard let string = String(data: data, encoding: .utf8) else {
            return []
        }
        return parse(string)
    }

    public mutating func parse(_ string: String) -> [TerminalKey] {
        var keys: [TerminalKey] = []

        for character in string {
            switch state {
            case .ground:
                consumeGround(character, into: &keys)
            case .escape:
                if character == "[" {
                    state = .csi
                } else {
                    keys.append(.escape)
                    state = .ground
                    consumeGround(character, into: &keys)
                }
            case .csi:
                switch character {
                case "A":
                    keys.append(.arrowUp)
                case "B":
                    keys.append(.arrowDown)
                case "C":
                    keys.append(.arrowRight)
                case "D":
                    keys.append(.arrowLeft)
                case "H":
                    keys.append(.home)
                case "F":
                    keys.append(.end)
                case "1" ... "9":
                    state = .csiParameter(String(character))
                    continue
                default:
                    break
                }
                state = .ground
            case .csiParameter(var parameter):
                if character.isNumber {
                    parameter.append(character)
                    state = .csiParameter(parameter)
                    continue
                }
                if character == "~" {
                    switch parameter {
                    case "1", "7":
                        keys.append(.home)
                    case "4", "8":
                        keys.append(.end)
                    case "5":
                        keys.append(.pageUp)
                    case "6":
                        keys.append(.pageDown)
                    default:
                        break
                    }
                }
                state = .ground
            }
        }

        return keys
    }

    public mutating func flush() -> [TerminalKey] {
        guard case .escape = state else {
            state = .ground
            return []
        }
        state = .ground
        return [.escape]
    }

    private mutating func consumeGround(_ character: Character, into keys: inout [TerminalKey]) {
        switch character {
        case "\u{1B}":
            state = .escape
        case "\n", "\r":
            keys.append(.enter)
        case "\t":
            keys.append(.tab)
        case "\u{7F}":
            keys.append(.backspace)
        case "\u{3}":
            keys.append(.ctrlC)
        case "\u{4}":
            keys.append(.ctrlD)
        default:
            keys.append(.character(character))
        }
    }
}

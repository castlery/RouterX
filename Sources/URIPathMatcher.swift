import Foundation

public enum RouteMatchingResult {
    case Matched(parameters: [String:String], handler: RouteTerminalHandlerType, pattern: String)
    case UnMatched
}

public enum URIPathToken {
    case Slash
    case Dot
    case Literal(String)

    var routeEdge: RouteEdge {
        switch self {
        case .Slash:
            return .Slash
        case .Dot:
            return .Dot
        case let .Literal(value):
            return .Literal(value)
        }
    }
}

extension URIPathToken: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .Slash:
            return "/"
        case .Dot:
            return "."
        case .Literal(let value):
            return value
        }
    }

    public var debugDescription: String {
        switch self {
        case .Slash:
            return "[Slash]"
        case .Dot:
            return "[Dot]"
        case .Literal(let value):
            return "[Literal \"\(value)\"]"
        }
    }
}

extension URIPathToken: Equatable { }

public func == (lhs: URIPathToken, rhs: URIPathToken) -> Bool {
    switch (lhs, rhs) {
    case (.Slash, .Slash):
        return true
    case (.Dot, .Dot):
        return true
    case (let .Literal(lval), let .Literal(rval)):
        return lval == rval
    default:
        return false
    }
}


public struct URIPathScanner {
    private static let stopWordsSet: Set<Character> = [".", "/"]

    public let path: String
    private(set) var position: String.Index

    public init(path: String) {
        self.path = path
        self.position = self.path.startIndex
    }

    public var isEOF: Bool {
        return self.position == self.path.endIndex
    }

    private var unScannedFragment: String {
        return self.path.substringFromIndex(self.position)
    }

    public mutating func nextToken() -> URIPathToken? {
        if self.isEOF {
            return nil
        }

        let firstChar = self.unScannedFragment.characters.first!

        self.position = self.position.advancedBy(1)

        switch firstChar {
        case "/":
            return .Slash
        case ".":
            return .Dot
        default:
            break
        }

        var fragment = ""
        var stepPosition = 0
        for char in self.unScannedFragment.characters {
            if URIPathScanner.stopWordsSet.contains(char) {
                break
            }

            fragment.append(char)
            stepPosition += 1
        }

        self.position = self.position.advancedBy(stepPosition)

        return .Literal("\(firstChar)\(fragment)")
    }

    public static func tokenize(path: String) -> [URIPathToken] {
        var scanner = self.init(path: path)

        var tokens: [URIPathToken] = []
        while let token = scanner.nextToken() {
            tokens.append(token)
        }

        return tokens
    }
}

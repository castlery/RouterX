import Foundation

public enum RoutingPatternParserError: ErrorType {
    case UnexpectToken(got: RoutingPatternToken?, message: String)
    case AmbiguousOptionalPattern
}

public class RoutingPatternParser {
    private typealias RoutingPatternTokenGenerator = IndexingGenerator<Array<RoutingPatternToken>>

    private let routingPatternTokens: [RoutingPatternToken]
    private let terminalHandler: RouteTerminalHandlerType

    public init(routingPatternTokens: [RoutingPatternToken], terminalHandler: RouteTerminalHandlerType) {
        self.routingPatternTokens = routingPatternTokens
        self.terminalHandler = terminalHandler
    }

    public func parseAndAppendTo(rootRoute: RouteVertex) throws {
        var tokenGenerator = self.routingPatternTokens.generate()
        if let token = tokenGenerator.next() {
            switch token {
            case .Slash:
                try parseSlash(rootRoute, generator: tokenGenerator)
            default:
                throw RoutingPatternParserError.UnexpectToken(got: token, message: "Pattern must start with slash.")
            }
        } else {
            rootRoute.handler = self.terminalHandler
        }
    }

    public class func parseAndAppendTo(rootRoute: RouteVertex, routingPatternTokens: [RoutingPatternToken], terminalHandler: RouteTerminalHandlerType) throws {
        let parser = RoutingPatternParser(routingPatternTokens: routingPatternTokens, terminalHandler: terminalHandler)
        try parser.parseAndAppendTo(rootRoute)
    }

    private func parseLParen(context: RouteVertex, isFirstEnter: Bool = true, var generator: RoutingPatternTokenGenerator) throws {
        if isFirstEnter && !context.isFinish {
            throw RoutingPatternParserError.AmbiguousOptionalPattern
        }

        assignTerminalHandlerIfNil(context)

        var subTokens: [RoutingPatternToken] = []
        var parenPairingCount = 0
        while let token = generator.next() {
            if token == .LParen {
                parenPairingCount += 1
            } else if token == .RParen {
                if parenPairingCount == 0 {
                    break
                } else if parenPairingCount > 0 {
                    parenPairingCount -= 1
                } else {
                    throw RoutingPatternParserError.UnexpectToken(got: .RParen, message: "Unexpect \(token)")
                }
            }

            subTokens.append(token)
        }

        var subGenerator = subTokens.generate()
        if let token = subGenerator.next() {
            for ctx in contextTerminals(context) {
                switch token {
                case .Slash:
                    try parseSlash(ctx, generator: subGenerator)
                case .Dot:
                    try parseDot(ctx, generator: subGenerator)
                default:
                    throw RoutingPatternParserError.UnexpectToken(got: token, message: "Unexpect \(token)")
                }
            }
        }

        if let nextToken = generator.next() {
            if nextToken == .LParen {
                try parseLParen(context, isFirstEnter: false, generator: generator)
            } else {
                throw RoutingPatternParserError.UnexpectToken(got: nextToken, message: "Unexpect \(nextToken)")
            }
        }
    }

    private func parseSlash(context: RouteVertex, var generator: RoutingPatternTokenGenerator) throws {
        let pattern = context.pattern + "/"

        guard let nextToken = generator.next() else {
            if let terminalRoute = context.nextRoutes[.Slash] {
                assignTerminalHandlerIfNil(terminalRoute)
            } else {
                context.nextRoutes[.Slash] = RouteVertex(pattern: pattern, handler: self.terminalHandler)
            }

            return
        }

        var nextRoute: RouteVertex!
        if let route = context.nextRoutes[.Slash] {
            nextRoute = route
        } else {
            nextRoute = RouteVertex(pattern: pattern)
            context.nextRoutes[.Slash] = nextRoute
        }

        switch nextToken {
        case let .Literal(value):
            try parseLiteral(nextRoute, value: value, generator: generator)
        case let .Symbol(value):
            try parseSymbol(nextRoute, value: value, generator: generator)
        case let .Star(value):
            try parseStar(nextRoute, value: value, generator: generator)
        case .LParen:
            try parseLParen(nextRoute, generator: generator)
        default:
            throw RoutingPatternParserError.UnexpectToken(got: nextToken, message: "Unexpect \(nextToken)")
        }
    }

    private func parseDot(context: RouteVertex, var generator: RoutingPatternTokenGenerator) throws {
        let pattern = context.pattern + "."

        guard let nextToken = generator.next() else {
            throw RoutingPatternParserError.UnexpectToken(got: nil, message: "Expect a token after \".\"")
        }

        var nextRoute: RouteVertex!
        if let route = context.nextRoutes[.Dot] {
            nextRoute = route
        } else {
            nextRoute = RouteVertex(pattern: pattern)
            context.nextRoutes[.Dot] = nextRoute
        }

        switch nextToken {
        case let .Literal(value):
            try parseLiteral(nextRoute, value: value, generator: generator)
        case let .Symbol(value):
            try parseSymbol(nextRoute, value: value, generator: generator)
        default:
            throw RoutingPatternParserError.UnexpectToken(got: nextToken, message: "Unexpect \(nextToken)")
        }
    }

    private func parseLiteral(context: RouteVertex, value: String, var generator: RoutingPatternTokenGenerator) throws {
        let pattern = context.pattern + value

        guard let nextToken = generator.next() else {
            if let terminalRoute = context.nextRoutes[.Literal(value)] {
                assignTerminalHandlerIfNil(terminalRoute)
            } else {
                context.nextRoutes[.Literal(value)] = RouteVertex(pattern: pattern, handler: self.terminalHandler)
            }

            return
        }

        var nextRoute: RouteVertex!
        if let route = context.nextRoutes[.Literal(value)] {
            nextRoute = route
        } else {
            nextRoute = RouteVertex(pattern: pattern)
            context.nextRoutes[.Literal(value)] = nextRoute
        }

        switch nextToken {
        case .Slash:
            try parseSlash(nextRoute, generator: generator)
        case .Dot:
            try parseDot(nextRoute, generator: generator)
        case .LParen:
            try parseLParen(nextRoute, generator: generator)
        default:
            throw RoutingPatternParserError.UnexpectToken(got: nextToken, message: "Unexpect \(nextToken)")
        }
    }

    private func parseSymbol(context: RouteVertex, value: String, var generator: RoutingPatternTokenGenerator) throws {
        let pattern = context.pattern + ":\(value)"

        guard let nextToken = generator.next() else {
            if let terminalRoute = context.nextRoutes[.Any] {
                assignTerminalHandlerIfNil(terminalRoute)
            } else {
                context.nextRoutes[.Any] = RouteVertex(pattern: pattern, handler: terminalHandler)
            }

            return
        }

        var nextRoute: RouteVertex!
        if let route = context.nextRoutes[.Any] {
            nextRoute = route
        } else {
            nextRoute = RouteVertex(pattern: pattern)
            context.nextRoutes[.Any] = nextRoute
        }

        switch nextToken {
        case .Slash:
            try parseSlash(nextRoute, generator: generator)
        case .Dot:
            try parseDot(nextRoute, generator: generator)
        case .LParen:
            try parseLParen(nextRoute, generator: generator)
        default:
            throw RoutingPatternParserError.UnexpectToken(got: nextToken, message: "Unexpect \(nextToken)")
        }
    }

    private func parseStar(context: RouteVertex, value: String, var generator: RoutingPatternTokenGenerator) throws {
        let pattern = context.pattern + "*\(value)"

        if let nextToken = generator.next() {
            throw RoutingPatternParserError.UnexpectToken(got: nextToken, message: "Unexpect \(nextToken)")
        }

        if let terminalRoute = context.nextRoutes[.Any] {
            assignTerminalHandlerIfNil(terminalRoute)
        } else {
            context.nextRoutes[.Any] = RouteVertex(pattern: pattern, handler: terminalHandler)
        }
    }

    private func contextTerminals(context: RouteVertex) -> [RouteVertex] {
        var contexts: [RouteVertex] = []

        if context.isTerminal {
            contexts.append(context)
        }

        for ctx in context.nextRoutes.values {
            contexts.appendContentsOf(contextTerminals(ctx))
        }

        return contexts
    }

    private func assignTerminalHandlerIfNil(context: RouteVertex) {
        if context.handler == nil {
            context.handler = self.terminalHandler
        }
    }
}

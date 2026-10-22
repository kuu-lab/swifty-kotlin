import Foundation

/// Audits the supported source grammar before Sema. BuildAST deliberately
/// tolerates/discards some tokens; JVM must never silently compile that loss.
final class JVMSourceValidationPhase: CompilerPhase {
    static let name = "JVMSourceValidation"

    func run(_ ctx: CompilationContext) throws {
        for file in ctx.tokensByFile.filter({ ctx.sourceManager.origin(of: $0.0) == .user }).sorted(by: { $0.0.rawValue < $1.0.rawValue }) {
            var grammar = JVMSourceGrammar(tokens: file.1, context: ctx)
            do { try grammar.file() }
            catch {
                ctx.diagnostics.error("KSWIFTK-JVM-0001", "Unsupported or invalid syntax in JVM M11 source.", range: grammar.currentRange)
            }
        }
    }
}

private struct JVMSourceGrammar {
    let tokens: [Token]
    let context: CompilationContext
    var index = 0
    var inDelegationHeader = false
    struct Unsupported: Error {}

    var kind: TokenKind { tokens[min(index, tokens.count - 1)].kind }
    var currentRange: SourceRange { tokens[min(index, tokens.count - 1)].range }
    mutating func take(_ expected: TokenKind) -> Bool {
        guard kind == expected else { return false }
        index += 1
        return true
    }
    mutating func require(_ expected: TokenKind) throws {
        guard take(expected) else { throw Unsupported() }
    }
    mutating func name() throws {
        guard kind.isLabelName else { throw Unsupported() }
        index += 1
    }
    mutating func semicolons() { while take(.symbol(.semicolon)) {} }
    func newlineBeforeCurrent() -> Bool {
        guard index > 0, index < tokens.count else { return false }
        let a = tokens[index - 1].range.end.offset
        let b = tokens[index].range.start.offset
        let data = context.sourceManager.contents(of: currentRange.start.file)
        guard a <= b, a >= 0, b <= data.count else { return false }
        return data[a..<b].contains(10) || data[a..<b].contains(13)
    }
    mutating func separator() throws {
        if take(.symbol(.semicolon)) { semicolons(); return }
        guard kind == .eof || kind == .symbol(.rBrace) || newlineBeforeCurrent() else { throw Unsupported() }
    }
    mutating func type(nullable: Bool = true, receiverSuffix: Bool = true) throws {
        while kind == .symbol(.at) { try annotation() }
        _ = take(.keyword(.suspend))
        if take(.symbol(.lParen)) {
            if !take(.symbol(.rParen)) {
                repeat { try type() } while take(.symbol(.comma))
                try require(.symbol(.rParen))
            }
            if take(.symbol(.arrow)) { try type() }
            if nullable { _ = take(.symbol(.question)) }
            if receiverSuffix, take(.symbol(.dot)) { try type() }
            return
        }
        try name()
        while kind == .symbol(.dot), tokens[min(index + 1, tokens.count - 1)].kind != .symbol(.lParen) { index += 1; try name() }
        if take(.symbol(.lessThan)) {
            repeat {
                if !take(.symbol(.star)) {
                    while kind == .symbol(.at) { try annotation() }
                    _ = take(.keyword(.in)) || take(.softKeyword(.out))
                    try type()
                }
            } while take(.symbol(.comma))
            try require(.symbol(.greaterThan))
        }
        if nullable, receiverSuffix, take(.symbol(.questionDot)) { try type(); return }
        if nullable { _ = take(.symbol(.question)) }
        if receiverSuffix, take(.symbol(.dot)) { try type() }
    }
    mutating func annotation() throws {
        try require(.symbol(.at)); try name()
        if take(.symbol(.colon)) { try name() }
        while take(.symbol(.dot)) { try name() }
        if take(.symbol(.lParen)) {
            var depth = 1
            while depth > 0 {
                guard kind != .eof else { throw Unsupported() }
                if take(.symbol(.lParen)) { depth += 1 }
                else if take(.symbol(.rParen)) { depth -= 1 }
                else { index += 1 }
            }
        }
    }
    mutating func typeParameters() throws {
        if take(.symbol(.lessThan)) {
            repeat {
                _ = take(.keyword(.reified))
                _ = take(.keyword(.in)) || take(.softKeyword(.out))
                try name()
                if take(.symbol(.colon)) { try type() }
            } while take(.symbol(.comma))
            try require(.symbol(.greaterThan))
        }
    }
    mutating func file() throws {
        while kind == .symbol(.at) { try annotation() }
        if take(.keyword(.package)) { try type(nullable: false); try separator() }
        while take(.keyword(.import)) {
            try name()
            while take(.symbol(.dot)) {
                if take(.symbol(.star)) { break }
                try name()
            }
            if take(.keyword(.as)) { try name() }
            try separator()
        }
        while kind != .eof {
            semicolons()
            if kind == .eof { break }
            try declaration(member: false)
            try separator()
        }
    }
    mutating func modifiers() {
        while [.public, .private, .internal, .protected, .open, .final, .abstract, .override, .inline, .tailrec, .suspend, .sealed, .data, .enum, .companion, .inner, .operator, .infix, .lateinit, .annotation, .value, .const].contains(where: { kind == .keyword($0) }) {
            // "value" is also a valid parameter/property name.
            if kind == .keyword(.value), tokens[min(index + 1, tokens.count - 1)].kind != .keyword(.class) { break }
            index += 1
        }
    }
    mutating func parameters(properties: Bool = false, requireTypes: Bool = true, allowDefaults: Bool = true) throws {
        try require(.symbol(.lParen))
        if !take(.symbol(.rParen)) {
            repeat {
                while kind == .symbol(.at) { try annotation() }
                while take(.keyword(.noinline)) || take(.keyword(.crossinline)) || take(.keyword(.vararg)) {}
                if properties { modifiers(); _ = take(.keyword(.val)) || take(.keyword(.var)) }
                try name()
                if requireTypes { try require(.symbol(.colon)); try type() }
                else if take(.symbol(.colon)) { try type() }
                if take(.symbol(.assign)) {
                    guard allowDefaults else { throw Unsupported() }
                    try expression()
                }
            } while take(.symbol(.comma)) && kind != .symbol(.rParen)
            try require(.symbol(.rParen))
        }
    }
    mutating func argument() throws {
        if kind.isLabelName, tokens[min(index + 1, tokens.count - 1)].kind == .symbol(.assign) { index += 2 }
        _ = take(.symbol(.star))
        try expression(allowNewlines: true)
    }
    mutating func arguments() throws {
        try require(.symbol(.lParen))
        if !take(.symbol(.rParen)) {
            repeat { try argument() } while take(.symbol(.comma)) && kind != .symbol(.rParen)
            try require(.symbol(.rParen))
        }
    }
    mutating func declaration(member: Bool) throws {
        let enclosingHeader = inDelegationHeader
        inDelegationHeader = false
        defer { inDelegationHeader = enclosingHeader }
        let declarationStart = index
        while kind == .symbol(.at) { try annotation() }
        modifiers()
        while kind == .symbol(.at) { try annotation(); modifiers() }
        let isEnum = tokens[declarationStart..<index].contains { $0.kind == .keyword(.enum) }
        if take(.keyword(.typealias)) {
            try name(); try typeParameters(); try require(.symbol(.assign)); try type(); return
        }
        if kind == .keyword(.fun), tokens[min(index + 1, tokens.count - 1)].kind != .keyword(.interface) {
            index += 1
            try typeParameters()
            // Parse either a function name or a receiver type followed by its name.
            let start = index
            do { try type(); guard kind == .symbol(.lParen) else { throw Unsupported() } }
            catch { index = start; try name() }
            try parameters()
            if take(.symbol(.colon)) { try type() }
            if take(.symbol(.assign)) { try expression() }
            else if kind == .symbol(.lBrace) { try block() }
            else if !member { throw Unsupported() }
        } else if kind == .keyword(.class) || kind == .keyword(.interface) || kind == .keyword(.fun) || kind == .keyword(.object) {
            _ = take(.keyword(.fun))
            let isInterface = take(.keyword(.interface))
            let isObject = take(.keyword(.object))
            if !isInterface && !isObject { try require(.keyword(.class)) }
            if !isObject || kind != .symbol(.lBrace) && kind != .symbol(.colon) { try name() }
            try typeParameters()
            if !isInterface && !isObject {
                let constructorStart = index
                while kind == .symbol(.at) { try annotation() }
                modifiers()
                if !take(.keyword(.constructor)) && !take(.softKeyword(.constructor)) { index = constructorStart }
                if kind == .symbol(.lParen) { try parameters(properties: true) }
            }
            if take(.symbol(.colon)) {
                repeat {
                    try type(nullable: false)
                    if kind == .symbol(.lParen) { try arguments() }
                    if take(.softKeyword(.by)) { inDelegationHeader = true; try expression(); inDelegationHeader = false }
                } while take(.symbol(.comma))
            }
            if take(.symbol(.lBrace)) {
                if isEnum, kind != .symbol(.semicolon) && kind != .symbol(.rBrace) {
                    repeat {
                        try name()
                        if kind == .symbol(.lParen) { try arguments() }
                        if take(.symbol(.lBrace)) {
                            semicolons()
                            while !take(.symbol(.rBrace)) { try declaration(member: true); try separator(); semicolons() }
                        }
                    } while take(.symbol(.comma)) && kind != .symbol(.semicolon) && kind != .symbol(.rBrace)
                    guard kind == .symbol(.semicolon) || kind == .symbol(.rBrace) else { throw Unsupported() }
                }
                semicolons()
                while !take(.symbol(.rBrace)) {
                    guard kind != .eof else { throw Unsupported() }
                    try declaration(member: true); try separator(); semicolons()
                }
            }
        } else if (take(.keyword(.val)) || take(.keyword(.var))) {
            try name()
            if take(.symbol(.colon)) { try type() }
            if take(.symbol(.assign)) || take(.softKeyword(.by)) { try expression() }
            while true {
                let saved = index
                semicolons(); modifiers()
                if take(.softKeyword(.get)) {
                    try parameters()
                } else if take(.softKeyword(.set)) {
                    if take(.symbol(.lParen)) {
                        try name()
                        if take(.symbol(.colon)) { try type() }
                        try require(.symbol(.rParen))
                    } else { continue }
                } else { index = saved; break }
                if take(.symbol(.assign)) { try expression() }
                else if kind == .symbol(.lBrace) { try block() }
            }
        } else if member && (take(.keyword(.constructor)) || take(.softKeyword(.constructor))) {
            try parameters()
            if take(.symbol(.colon)) {
                guard take(.keyword(.this)) || take(.keyword(.super)) else { throw Unsupported() }
                try arguments()
            }
            if kind == .symbol(.lBrace) { try block() }
        } else if member && take(.softKeyword(.`init`)) {
            try block()
        } else { throw Unsupported() }
    }
    mutating func block() throws {
        try require(.symbol(.lBrace)); semicolons()
        while !take(.symbol(.rBrace)) {
            guard kind != .eof else { throw Unsupported() }
            try statement(); try separator(); semicolons()
        }
    }
    mutating func body() throws {
        while kind == .symbol(.at) { try annotation() }
        if kind == .symbol(.lBrace) { try block() } else { try statement() }
    }
    mutating func condition() throws {
        try require(.symbol(.lParen)); try expression(allowNewlines: true); try require(.symbol(.rParen))
    }
    mutating func statement() throws {
        while kind == .symbol(.at) { try annotation() }
        let late = take(.keyword(.lateinit))
        if late, kind != .keyword(.val), kind != .keyword(.var) { throw Unsupported() }
        if take(.keyword(.val)) || take(.keyword(.var)) {
            var hasTypeAnnotation = false
            if take(.symbol(.lParen)) {
                repeat { try name() } while take(.symbol(.comma))
                try require(.symbol(.rParen))
            } else {
                try name()
                hasTypeAnnotation = take(.symbol(.colon))
                if hasTypeAnnotation { try type() }
            }
            if !late {
                if take(.symbol(.assign)) || take(.softKeyword(.by)) { try expression() }
                else if !hasTypeAnnotation { throw Unsupported() }
            }
        } else if kind == .keyword(.fun) {
            let start = index
            do { try anonymousFunction() }
            catch { index = start; try declaration(member: false) }
        } else if take(.keyword(.while)) {
            try condition(); try body()
        } else if take(.keyword(.do)) {
            try body(); try require(.keyword(.while)); try condition()
        } else if take(.keyword(.for)) {
            try require(.symbol(.lParen)); try name(); try require(.keyword(.in))
            try expression(allowNewlines: true); try require(.symbol(.rParen)); try body()
        } else if take(.keyword(.return)) {
            if take(.symbol(.at)) { try name() }
            if kind != .symbol(.rBrace), kind != .symbol(.semicolon), !newlineBeforeCurrent() { try expression() }
        } else if take(.keyword(.break)) || take(.keyword(.continue)) {
            return
        } else {
            try expression()
            if [.assign, .plusAssign, .minusAssign, .starAssign, .slashAssign, .percentAssign].contains(where: { kind == .symbol($0) }) {
                index += 1; try expression()
            }
        }
    }
    func precedence() -> Int? {
        switch kind {
        case .symbol(.questionColon): 0
        case .symbol(.barBar): 1
        case .symbol(.ampAmp): 2
        case .symbol(.equalEqual), .symbol(.bangEqual), .symbol(.tripleEqual), .symbol(.notTripleEqual): 3
        case .keyword(.as), .keyword(.is), .keyword(.in): 4
        case .symbol(.bang) where tokens.indices.contains(index + 1) && [TokenKind.keyword(.in), .keyword(.is)].contains(tokens[index + 1].kind): 4
        case .symbol(.lessThan), .symbol(.lessOrEqual), .symbol(.greaterThan), .symbol(.greaterOrEqual): 4
        case .symbol(.dotDot), .symbol(.dotDotLt): 5
        case let .identifier(name) where ["zip", "matches", "downTo", "to", "until", "and", "or", "xor", "shl", "shr", "ushr"].contains(context.interner.resolve(name)): 5
        case .symbol(.plus), .symbol(.minus): 6
        case .symbol(.star), .symbol(.slash), .symbol(.percent): 7
        default: nil
        }
    }
    mutating func expression(_ minimum: Int = 0, allowNewlines: Bool = false) throws {
        try primary()
        while let level = precedence(), level >= minimum, allowNewlines || !newlineBeforeCurrent() {
            if take(.keyword(.as)) { _ = take(.symbol(.question)); try type(); continue }
            if take(.keyword(.is)) { try type(); continue }
            if take(.symbol(.bang)) {
                if take(.keyword(.is)) { try type(); continue }
                try require(.keyword(.in))
            } else { index += 1 }
            try expression(level + 1, allowNewlines: allowNewlines)
        }
    }
    mutating func lambda() throws {
        try require(.symbol(.lBrace))
        let start = index
        do {
            if !take(.symbol(.arrow)) {
                repeat {
                    if take(.symbol(.lParen)) {
                        repeat { try name() } while take(.symbol(.comma))
                        try require(.symbol(.rParen))
                    } else { try name() }
                    if take(.symbol(.colon)) { try type() }
                } while take(.symbol(.comma))
                try require(.symbol(.arrow))
            }
        } catch { index = start }
        semicolons()
        while !take(.symbol(.rBrace)) {
            guard kind != .eof else { throw Unsupported() }
            try statement(); try separator(); semicolons()
        }
    }
    mutating func anonymousFunction() throws {
        try require(.keyword(.fun))
        if kind != .symbol(.lParen) {
            try type(receiverSuffix: false)
            guard take(.symbol(.dot)) || take(.symbol(.questionDot)) else { throw Unsupported() }
        }
        try parameters(requireTypes: false, allowDefaults: false)
        if take(.symbol(.colon)) { try type() }
        if take(.symbol(.assign)) { try expression() }
        else { try block() }
    }
    func startsTrailingLambda() -> Bool {
        guard !newlineBeforeCurrent(), !inDelegationHeader else { return false }
        if kind == .symbol(.lBrace) { return true }
        return kind.isLabelName && tokens.indices.contains(index + 2)
            && tokens[index + 1].kind == .symbol(.at)
            && tokens[index + 2].kind == .symbol(.lBrace)
    }
    mutating func primary() throws {
        while kind == .symbol(.at) { try annotation() }
        if take(.keyword(.return)) {
            if take(.symbol(.at)) { try name() }
            if kind != .templateExprEnd, kind != .symbol(.rBrace), kind != .symbol(.semicolon), !newlineBeforeCurrent() { try expression() }
            return
        }
        if take(.keyword(.break)) || take(.keyword(.continue)) { return }
        if take(.keyword(.throw)) { try expression(); return }
        if take(.keyword(.try)) {
            try block()
            var handled = false
            while take(.keyword(.catch)) {
                handled = true
                try require(.symbol(.lParen)); try name(); try require(.symbol(.colon)); try type()
                try require(.symbol(.rParen)); try block()
            }
            if take(.keyword(.finally)) { handled = true; try block() }
            guard handled else { throw Unsupported() }
            return
        }
        if take(.keyword(.when)) {
            if kind == .symbol(.lParen) {
                try require(.symbol(.lParen))
                if take(.keyword(.val)) { try name(); if take(.symbol(.colon)) { try type() }; try require(.symbol(.assign)) }
                try expression(allowNewlines: true); try require(.symbol(.rParen))
            }
            try require(.symbol(.lBrace)); semicolons()
            while !take(.symbol(.rBrace)) {
                if !take(.keyword(.else)) {
                    repeat {
                        if take(.keyword(.is)) { try type() }
                        else if take(.symbol(.bang)) { try require(.keyword(.is)); try type() }
                        else { try expression() }
                    } while take(.symbol(.comma))
                }
                try require(.symbol(.arrow)); try body(); try separator(); semicolons()
            }
            return
        }
        if take(.keyword(.if)) {
            try condition(); try body()
            if take(.keyword(.else)) { try body() }
            return
        }
        if [.plus, .minus, .bang, .plusPlus, .minusMinus].contains(where: { kind == .symbol($0) }) {
            index += 1; try primary(); return
        }
        if take(.symbol(.doubleColon)) { try name()
        } else if kind == .keyword(.fun) {
            try anonymousFunction()
        } else if kind == .keyword(.object) {
            try declaration(member: false)
        } else if take(.keyword(.super)) {
            if take(.symbol(.lessThan)) { try type(nullable: false); try require(.symbol(.greaterThan)) }
        } else { switch kind {
        case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral, .charLiteral, .floatLiteral, .doubleLiteral, .keyword(.true), .keyword(.false), .keyword(.null): index += 1
        case .keyword(.this): index += 1; if take(.symbol(.at)) { try name() }
        case .identifier, .backtickedIdentifier, .softKeyword, .keyword(.value): try name()
        case .stringQuote, .rawStringQuote, .multiDollarStringQuote, .multiDollarRawStringQuote:
            let quote = kind
            index += 1
            while kind != quote {
                if case .stringSegment = kind { index += 1 }
                else if take(.templateSimpleNameStart) { try name() }
                else if take(.templateExprStart) { try expression(); try require(.templateExprEnd) }
                else { throw Unsupported() }
            }
            try require(quote)
        case .symbol(.lBracket):
            index += 1
            if !take(.symbol(.rBracket)) {
                repeat { try expression(allowNewlines: true) } while take(.symbol(.comma)) && kind != .symbol(.rBracket)
                try require(.symbol(.rBracket))
            }
        case .symbol(.lBrace): try lambda()
        case .symbol(.lParen):
            let header = inDelegationHeader; inDelegationHeader = false
            index += 1; try expression(allowNewlines: true); try require(.symbol(.rParen))
            inDelegationHeader = header
        default:
            guard kind.isLabelName else { throw Unsupported() }
            try name()
        } }
        while true {
            if kind == .symbol(.lessThan) {
                let saved = index
                do {
                    index += 1
                    repeat { try type() } while take(.symbol(.comma))
                    try require(.symbol(.greaterThan))
                    guard kind == .symbol(.lParen) || startsTrailingLambda() else { throw Unsupported() }
                } catch { index = saved; break }
            } else if take(.symbol(.lBracket)) {
                try expression(allowNewlines: true); try require(.symbol(.rBracket))
            } else if take(.symbol(.lParen)) {
                let header = inDelegationHeader; inDelegationHeader = false
                if !take(.symbol(.rParen)) {
                    repeat { try argument() } while take(.symbol(.comma)) && kind != .symbol(.rParen)
                    try require(.symbol(.rParen))
                }
                inDelegationHeader = header
            } else if startsTrailingLambda() {
                if kind.isLabelName { index += 2 }
                try lambda()
            } else if kind == .symbol(.at), !newlineBeforeCurrent() { index += 1; try lambda()
            } else if take(.symbol(.dot)) || take(.symbol(.questionDot)) { try name()
            } else if take(.symbol(.doubleColon)) {
                if !take(.keyword(.class)) { try name() }
            } else if take(.symbol(.bangBang)) {
                continue
            } else if take(.symbol(.plusPlus)) || take(.symbol(.minusMinus)) {
                break
            } else { break }
        }
    }
}

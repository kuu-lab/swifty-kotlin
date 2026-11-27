import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum LeanParser {
    private typealias Initialize = @convention(c) () -> Int32
    private typealias ReadToken = @convention(c) (UnsafeMutableRawPointer, Int) -> UInt8
    private typealias CanStart = @convention(c) (UnsafeMutableRawPointer, ReadToken, Int, UInt8) -> Int32

    private typealias FindOffset = @convention(c) (UnsafeMutableRawPointer, ReadToken, Int, Int) -> UInt

    private typealias Scan = @convention(c) (UnsafeMutableRawPointer, ReadToken, ReadToken, Int) -> UInt64

    private typealias ClassifyPolicy = @convention(c) (UInt8, UInt8, UInt8) -> Int32

    private struct Bindings: Sendable {
        let canStart: CanStart
        let findOffset: FindOffset
        let scan: Scan
        let classifyPolicy: ClassifyPolicy
    }

    private static let bindings: Bindings? = {
        #if os(macOS)
        let library = "liblean_parser.dylib"
        #else
        let library = "liblean_parser.so"
        #endif
        guard let url = Bundle.module.resourceURL?.appendingPathComponent("LeanParserResources")
            .appendingPathComponent(library),
            let handle = dlopen(url.path, RTLD_NOW | RTLD_LOCAL)
        else { return nil }
        guard let initialize = dlsym(handle, "kswiftk_lean_parser_init"),
              let canStart = dlsym(handle, "kswiftk_lean_parser_can_start_type_arguments"),
              let findOffset = dlsym(handle, "kswiftk_lean_parser_offset_past_type_arguments"),
              let scan = dlsym(handle, "kswiftk_lean_parser_consume_type_arguments"),
              let classifyPolicy = dlsym(handle, "kswiftk_lean_parser_classify_policy"),
              unsafeBitCast(initialize, to: Initialize.self)() == 1
        else {
            dlclose(handle)
            return nil
        }
        return Bindings(
            canStart: unsafeBitCast(canStart, to: CanStart.self),
            findOffset: unsafeBitCast(findOffset, to: FindOffset.self),
            scan: unsafeBitCast(scan, to: Scan.self),
            classifyPolicy: unsafeBitCast(classifyPolicy, to: ClassifyPolicy.self)
        )
    }()

    private enum TokenCode: UInt8 {
        case other, openAngle, closeAngle, at, dot, colon
        case openParen, closeParen, openBracket, closeBracket, openBrace, closeBrace
        case templateStart, templateEnd, varianceIn, eof
        case identifier, star, varianceOut, comma, question, questionDot, doubleColon
        case forKeyword, whileKeyword, doKeyword, arrow
        case bang, bangBang, questionColon, ampAmp, barBar, isKeyword, asKeyword, objectKeyword
        case fieldKeyword, assign
    }

    private static let readToken: ReadToken = { state, offset in
        let parser = Unmanaged<KotlinParser>.fromOpaque(state).takeUnretainedValue()
        return tokenCode(parser.stream.peek(offset).kind).rawValue
    }

    private static func tokenCode(_ kind: TokenKind) -> TokenCode {
        switch kind {
        case .symbol(.lessThan): .openAngle
        case .symbol(.greaterThan): .closeAngle
        case .symbol(.at): .at
        case .symbol(.dot): .dot
        case .symbol(.colon): .colon
        case .symbol(.lParen): .openParen
        case .symbol(.rParen): .closeParen
        case .symbol(.lBracket): .openBracket
        case .symbol(.rBracket): .closeBracket
        case .symbol(.lBrace): .openBrace
        case .symbol(.rBrace): .closeBrace
        case .templateExprStart: .templateStart
        case .templateExprEnd: .templateEnd
        case .keyword(.in): .varianceIn
        case .eof: .eof
        case .identifier, .backtickedIdentifier: .identifier
        case .symbol(.star): .star
        case .softKeyword(.out): .varianceOut
        case .symbol(.comma): .comma
        case .symbol(.question): .question
        case .symbol(.questionDot): .questionDot
        case .symbol(.doubleColon): .doubleColon
        case .keyword(.for): .forKeyword
        case .keyword(.while): .whileKeyword
        case .keyword(.do): .doKeyword
        case .symbol(.arrow): .arrow
        case .symbol(.bang): .bang
        case .symbol(.bangBang): .bangBang
        case .symbol(.questionColon): .questionColon
        case .symbol(.ampAmp): .ampAmp
        case .symbol(.barBar): .barBar
        case .keyword(.is): .isKeyword
        case .keyword(.as): .asKeyword
        case .keyword(.object): .objectKeyword
        case .softKeyword(.field): .fieldKeyword
        case .symbol(.assign): .assign
        default: .other
        }
    }

    static func canStartTypeArguments(_ parser: KotlinParser, hasAnchorToken: Bool) -> Bool {
        let result = withExtendedLifetime(parser) {
            bindings?.canStart(
                Unmanaged.passUnretained(parser).toOpaque(), readToken,
                parser.stream.tokens.count - parser.stream.index, hasAnchorToken ? 1 : 0
            )
        }
        guard let result, result >= 0 else {
            reportUnavailable(parser)
            return false
        }
        return result == 1
    }

    static func offsetPastTypeArguments(_ parser: KotlinParser, from offset: Int) -> Int {
        let count = parser.stream.tokens.count - parser.stream.index
        guard offset >= 0, offset <= count else { return offset }
        let result = withExtendedLifetime(parser) {
            bindings?.findOffset(Unmanaged.passUnretained(parser).toOpaque(), readToken, count, offset)
        }
        guard let result, result >= UInt(offset), result <= UInt(count) else {
            reportUnavailable(parser)
            return offset
        }
        return Int(result)
    }

    private static let readBoundary: ReadToken = { state, offset in
        let parser = Unmanaged<KotlinParser>.fromOpaque(state).takeUnretainedValue()
        let token = parser.stream.peek(offset)
        guard parser.hasLeadingNewline(token), parser.isLikelyTopLevelDeclarationStart(token, at: offset) else {
            return 0
        }
        return parser.continuesAngleBracketListAtNewlineAnnotation(token, at: offset) ? 0 : 1
    }

    static func scanTypeArguments(_ parser: KotlinParser) -> (consumed: Int, unterminated: Bool)? {
        let count = parser.stream.tokens.count - parser.stream.index
        let result = withExtendedLifetime(parser) {
            bindings?.scan(Unmanaged.passUnretained(parser).toOpaque(), readToken, readBoundary, count)
        }
        guard let result, let consumed = Int(exactly: result >> 2), consumed <= count else {
            reportUnavailable(parser)
            return nil
        }
        return (consumed, result & 3 >= 2)
    }

    private enum Policy: UInt8 {
        case labelStart, loopStart, typeNameStart, whenConditionNewline, objectExpression, backingField
    }

    private static func classify(_ parser: KotlinParser, _ policy: Policy, first: UInt8, second: UInt8 = 0) -> Bool {
        guard let result = bindings?.classifyPolicy(policy.rawValue, first, second), result >= 0 else {
            reportUnavailable(parser)
            return false
        }
        return result == 1
    }

    static func isLabelStart(_ parser: KotlinParser) -> Bool {
        classify(
            parser, .labelStart,
            first: parser.stream.peek().kind.isLabelName ? 1 : 0,
            second: tokenCode(parser.stream.peek(1).kind).rawValue
        )
    }

    static func isLoopStart(_ parser: KotlinParser, kind: TokenKind) -> Bool {
        classify(parser, .loopStart, first: tokenCode(kind).rawValue)
    }

    static func canStartTypeName(_ parser: KotlinParser, after kind: TokenKind?) -> Bool {
        classify(parser, .typeNameStart, first: (kind.map(tokenCode) ?? .other).rawValue)
    }

    static func whenConditionContinuesAfterLineBreak(_ parser: KotlinParser, kind: TokenKind) -> Bool {
        classify(
            parser, .whenConditionNewline,
            first: tokenCode(kind).rawValue, second: tokenCode(parser.stream.peek(1).kind).rawValue
        )
    }

    static func isObjectExpressionStart(_ parser: KotlinParser, kind: TokenKind) -> Bool {
        classify(
            parser, .objectExpression,
            first: tokenCode(kind).rawValue, second: tokenCode(parser.stream.peek(1).kind).rawValue
        )
    }

    static func isExplicitBackingFieldStart(_ parser: KotlinParser, kind: TokenKind) -> Bool {
        classify(
            parser, .backingField,
            first: tokenCode(kind).rawValue, second: tokenCode(parser.stream.peek(1).kind).rawValue
        )
    }

    static func reportUnavailable(_ parser: KotlinParser) {
        parser.diagnostics.error(
            "KSWIFTK-PARSE-0032", "Unable to run the bundled Lean parser. Build it with Scripts/build_lean.sh.",
            range: parser.stream.peek().rangeIfAvailable
        )
    }
}

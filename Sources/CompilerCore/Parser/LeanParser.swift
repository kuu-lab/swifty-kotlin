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

    private struct Bindings: Sendable {
        let canStart: CanStart
        let findOffset: FindOffset
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
              unsafeBitCast(initialize, to: Initialize.self)() == 1
        else {
            dlclose(handle)
            return nil
        }
        return Bindings(
            canStart: unsafeBitCast(canStart, to: CanStart.self),
            findOffset: unsafeBitCast(findOffset, to: FindOffset.self)
        )
    }()

    private enum TokenCode: UInt8 {
        case other, openAngle, closeAngle, at, dot, colon
        case openParen, closeParen, openBracket, closeBracket, openBrace, closeBrace
        case templateStart, templateEnd, varianceIn, eof
        case identifier, star, varianceOut, comma, question, questionDot, doubleColon
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

    static func reportUnavailable(_ parser: KotlinParser) {
        parser.diagnostics.error(
            "KSWIFTK-PARSE-0032", "Unable to run the bundled Lean parser. Build it with Scripts/build_lean.sh.",
            range: parser.stream.peek().rangeIfAvailable
        )
    }
}

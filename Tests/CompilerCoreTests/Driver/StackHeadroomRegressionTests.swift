#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// Regression tests for BUG-144: the structural recursion guards (Sema type
// resolution, type-ref parser, expression parser) are sized for a large stack,
// so on the 512 KiB threads the frontend also runs on (Swift Concurrency
// cooperative pool, Dispatch workers, LSP requests) the stack was exhausted long
// before the depth cap tripped and the process crashed (SIGBUS / SIGSEGV)
// instead of reporting a diagnostic.
@Suite
struct StackHeadroomRegressionTests {
    /// Stack size of a Swift Concurrency cooperative-pool thread.
    private static let smallStackSize = 512 << 10

    private final class ResultBox: @unchecked Sendable {
        var diagnostics: [Diagnostic] = []
    }

    /// Runs `body` on a thread with a deliberately small stack and returns the
    /// diagnostics it produced. A missing guard crashes the whole test process.
    private func onSmallStackThread(
        _ body: @escaping @Sendable (DiagnosticEngine) -> Void
    ) -> [Diagnostic] {
        let box = ResultBox()
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            let diagnostics = DiagnosticEngine()
            body(diagnostics)
            box.diagnostics = diagnostics.diagnostics
            done.signal()
        }
        thread.stackSize = Self.smallStackSize
        thread.start()
        done.wait()
        return box.diagnostics
    }

    @Test func testDeeplyNestedGenericTypeRefEmitsDepthDiagnosticOnSmallStack() {
        let diagnostics = onSmallStackThread { diagnostics in
            let interner = StringInterner()
            let listName = interner.intern("List")
            let intName = interner.intern("Int")

            let symbols = SymbolTable()
            _ = symbols.define(
                kind: .class,
                name: listName,
                fqName: [listName],
                declSite: nil,
                visibility: .public
            )

            let arena = ASTArena()
            var innerRef = arena.appendTypeRef(.named(path: [intName], args: [], nullable: false))
            for _ in 0 ..< 600 {
                let arg = TypeArgRef.invariant(innerRef)
                innerRef = arena.appendTypeRef(.named(path: [listName], args: [arg], nullable: false))
            }

            let ast = ASTModule(files: [], arena: arena, declarationCount: 0, tokenCount: 0)
            _ = DataFlowSemaPhase().resolveTypeRef(
                innerRef,
                ast: ast,
                symbols: symbols,
                types: TypeSystem(),
                interner: interner,
                diagnostics: diagnostics
            )
        }

        #expect(diagnostics.contains { $0.code == "KSWIFTK-SEMA-TYPE-DEPTH" })
    }

    @Test func testDeeplyNestedTypeRefParsingEmitsDepthDiagnosticOnSmallStack() {
        let diagnostics = onSmallStackThread { diagnostics in
            let interner = StringInterner()
            let intName = interner.intern("Int")

            var tokens: [Token] = []
            var offset = 0
            for _ in 0 ..< 600 {
                tokens.append(makeToken(kind: .symbol(.lParen), start: offset, end: offset + 1))
                offset += 1
                tokens.append(makeToken(kind: .symbol(.rParen), start: offset, end: offset + 1))
                offset += 1
                tokens.append(makeToken(kind: .symbol(.arrow), start: offset, end: offset + 2))
                offset += 2
            }
            tokens.append(makeToken(kind: .identifier(intName), start: offset, end: offset + 1))

            _ = TypeRefParserCore.parseTypeRefPrefix(
                tokens[...],
                interner: interner,
                astArena: ASTArena(),
                options: TypeRefParserCore.Options(
                    allowQualifiedPath: true,
                    allowFunctionType: true,
                    allowKeywordIdentifiers: false,
                    reserveVarianceKeywords: false,
                    allowTypeAnnotations: false
                ),
                diagnostics: diagnostics
            )
        }

        #expect(diagnostics.contains { $0.code == "KSWIFTK-PARSE-TYPE-DEPTH" })
    }

    @Test func testDeeplyNestedExpressionParsingEmitsDepthDiagnosticOnSmallStack() {
        let diagnostics = onSmallStackThread { diagnostics in
            let interner = StringInterner()
            let depth = 600

            var tokens: [Token] = []
            var offset = 0
            for _ in 0 ..< depth {
                tokens.append(makeToken(kind: .symbol(.lParen), start: offset, end: offset + 1))
                offset += 1
            }
            tokens.append(makeToken(kind: .intLiteral("1"), start: offset, end: offset + 1))
            offset += 1
            for _ in 0 ..< depth {
                tokens.append(makeToken(kind: .symbol(.rParen), start: offset, end: offset + 1))
                offset += 1
            }

            let parser = BuildASTPhase.ExpressionParser(
                tokens: tokens[...],
                interner: interner,
                astArena: ASTArena(),
                diagnostics: diagnostics
            )
            _ = parser.parseExpression(minPrecedence: 0)
        }

        #expect(diagnostics.contains { $0.code == "KSWIFTK-PARSE-0012" })
    }

    @Test func testShallowRecursionKeepsStackHeadroomOnSmallStack() {
        let diagnostics = onSmallStackThread { diagnostics in
            let interner = StringInterner()
            let listName = interner.intern("List")
            let intName = interner.intern("Int")

            let symbols = SymbolTable()
            _ = symbols.define(
                kind: .class,
                name: listName,
                fqName: [listName],
                declSite: nil,
                visibility: .public
            )

            let arena = ASTArena()
            var innerRef = arena.appendTypeRef(.named(path: [intName], args: [], nullable: false))
            for _ in 0 ..< 8 {
                let arg = TypeArgRef.invariant(innerRef)
                innerRef = arena.appendTypeRef(.named(path: [listName], args: [arg], nullable: false))
            }

            let ast = ASTModule(files: [], arena: arena, declarationCount: 0, tokenCount: 0)
            _ = DataFlowSemaPhase().resolveTypeRef(
                innerRef,
                ast: ast,
                symbols: symbols,
                types: TypeSystem(),
                interner: interner,
                diagnostics: diagnostics
            )
        }

        #expect(diagnostics.isEmpty)
    }
}
#endif

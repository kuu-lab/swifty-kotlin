@testable import CompilerCore
import Foundation
import Testing

/// Verifies the STDLIB-IO-FN-011 synthetic stub for `String.byteInputStream(charset)`.
/// Two overloads are exposed from `kotlin.io`:
/// - `String.byteInputStream(): ByteArrayInputStream` → `kk_string_byteInputStream_flat`
/// - `String.byteInputStream(charset: Charset): ByteArrayInputStream` → `kk_string_byteInputStream_charset_flat`
///
/// Both return `java.io.ByteArrayInputStream`, which is registered as an
/// `InputStream` subtype so that resource-management surfaces (`.use {}`) work
/// out of the box.
@Suite
struct StringByteInputStreamFunctionTests {
    private func allMemberCallExprIDs(
        named member: String,
        in ast: ASTModule,
        interner: StringInterner,
        sourceManager: SourceManager?
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == member
            else { continue }
            if let sourceManager, let range = ast.arena.exprRange(exprID) {
                guard !sourceManager.path(of: range.start.file).hasPrefix("__bundled_") else { continue }
            }
            results.append(exprID)
        }
        return results
    }

    private func fqNameMatches(_ symbolID: SymbolID, expected: [String], sema: SemaModule, interner: StringInterner) -> Bool {
        guard let info = sema.symbols.symbol(symbolID) else { return false }
        return info.fqName.map { interner.resolve($0) } == expected
    }

    @Test func testByteInputStreamResolvesInSource() throws {
        let source = """
        import kotlin.text.Charsets
        import java.io.ByteArrayInputStream

        fun useDefaultCharset(value: String) = value.byteInputStream()

        fun useExplicitCharset(value: String) = value.byteInputStream(Charsets.UTF_16)

        fun consume(value: String): Int {
            val stream: ByteArrayInputStream = value.byteInputStream()
            val available = stream.available()
            val first = stream.read()
            stream.close()
            return available + first
        }

        fun firstByte(value: String): Int = value.byteInputStream().use { it.read() }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let callExprs = allMemberCallExprIDs(
            named: "byteInputStream",
            in: ast,
            interner: interner,
            sourceManager: ctx.sourceManager
        )
        #expect(callExprs.count == 4, "Expected four byteInputStream calls in user source")

        for callExpr in callExprs {
            let chosenCallee = try #require(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected call binding for byteInputStream"
            )
            let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
            #expect(signature.receiverType == sema.types.stringType)

            guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
                Issue.record("Expected byteInputStream to return a class type")
                continue
            }
            let returnInfo = try #require(sema.symbols.symbol(returnClassType.classSymbol))
            #expect(
                returnInfo.fqName.map { interner.resolve($0) } == ["java", "io", "ByteArrayInputStream"]
            )

            if signature.parameterTypes.isEmpty {
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_byteInputStream_flat"
                )
                #expect(
                    fqNameMatches(chosenCallee, expected: ["kotlin", "io", "byteInputStream"], sema: sema, interner: interner)
                )
            } else if signature.parameterTypes.count == 1 {
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_byteInputStream_charset_flat"
                )
                guard case let .classType(paramClassType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                    Issue.record("Expected charset parameter to be a class type")
                    continue
                }
                let paramInfo = try #require(sema.symbols.symbol(paramClassType.classSymbol))
                #expect(
                    paramInfo.fqName.map { interner.resolve($0) } == ["kotlin", "text", "Charset"]
                )
            } else {
                Issue.record("Unexpected byteInputStream parameter count \(signature.parameterTypes.count)")
            }
        }

        let fqName = ["kotlin", "io", "byteInputStream"].map { interner.intern($0) }
        let symbols = sema.symbols.lookupAll(fqName: fqName)
        #expect(symbols.count == 2, "Expected exactly two byteInputStream overloads in kotlin.io")

        let externalLinks = Set(symbols.compactMap { sema.symbols.externalLinkName(for: $0) })
        #expect(
            externalLinks == ["kk_string_byteInputStream_flat", "kk_string_byteInputStream_charset_flat"]
        )

        for symbolID in symbols {
            let signature = try #require(sema.symbols.functionSignature(for: symbolID))
            #expect(signature.receiverType == sema.types.stringType)
        }
    }
}

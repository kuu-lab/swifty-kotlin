#if canImport(Testing)
@testable import CompilerCore
import Testing

/// Byte/Short bitwise operations are scoped extensions, not primitive members.
@Suite
struct ExperimentalBitwiseFunctionTests {

    private static let bitwiseImports = """
    import kotlin.experimental.and
    import kotlin.experimental.inv
    import kotlin.experimental.or
    import kotlin.experimental.xor
    """

    private static let sources: [String] = [
        // 0: testByteBitwiseOperationsResolveWithoutDiagnostics
        """
        package sample0

        \(Self.bitwiseImports)

        fun byteOps(a: Byte, b: Byte) {
            println(a and b)
            println(a or b)
            println(a xor b)
            println(a.inv())
            println(a.and(b))
            println(a.or(b))
            println(a.xor(b))
        }
        """,
        // 1: testShortBitwiseOperationsResolveWithoutDiagnostics
        """
        package sample1

        \(Self.bitwiseImports)

        fun shortOps(a: Short, b: Short) {
            println(a and b)
            println(a or b)
            println(a xor b)
            println(a.inv())
            println(a.and(b))
            println(a.or(b))
            println(a.xor(b))
        }
        """,
        // 2: testIntBitwiseIsNotNarrowedByExperimentalImports
        """
        package sample2

        \(Self.bitwiseImports)

        fun intOps(): Int {
            val wide: Int = 0x1234 and 0xFF00
            return wide
        }
        """,
        // 3: testBitwiseResultKeepsReceiverType (Byte)
        """
        package sample3

        \(Self.bitwiseImports)

        fun ops(a: Byte, b: Byte) {
            println(a and b)
            println(a.inv())
        }
        """,
        // 4: testBitwiseResultKeepsReceiverType (Short)
        """
        package sample4

        \(Self.bitwiseImports)

        fun ops(a: Short, b: Short) {
            println(a and b)
            println(a.inv())
        }
        """,
        // 5: signed narrow receivers have no builtin bitwise members
        """
        package sample5

        fun rejected(b: Byte, s: Short, nb: Byte?, ns: Short?) {
            b and b
            b or b
            b xor b
            b.and(b)
            b.or(b)
            b.xor(b)
            b.inv()
            s and s
            s or s
            s xor s
            s.and(s)
            s.or(s)
            s.xor(s)
            s.inv()
            nb?.and(b)
            nb?.or(b)
            nb?.xor(b)
            nb?.inv()
            ns?.and(s)
            ns?.or(s)
            ns?.xor(s)
            ns?.inv()
            b shl 1
            b shr 1
            b ushr 1
            s shl 1
            s shr 1
            s ushr 1
        }
        """,
        // 6: wildcard imports and safe calls
        """
        package sample6
        import kotlin.experimental.*

        fun ops(b: Byte?, s: Short?, mask: Byte, wideMask: Short) {
            val bAnd: Byte? = b?.and(mask)
            val bOr: Byte? = b?.or(mask)
            val bXor: Byte? = b?.xor(mask)
            val bInv: Byte? = b?.inv()
            val sAnd: Short? = s?.and(wideMask)
            val sOr: Short? = s?.or(wideMask)
            val sXor: Short? = s?.xor(wideMask)
            val sInv: Short? = s?.inv()
        }
        """,
        // 7: aliases must resolve the actual imported declarations
        """
        package sample7
        import kotlin.experimental.and as bitAnd
        import kotlin.experimental.or as bitOr
        import kotlin.experimental.xor as bitXor
        import kotlin.experimental.inv as bitInv

        fun ops(b: Byte, s: Short) {
            val bAnd: Byte = b bitAnd b
            val bOr: Byte = b.bitOr(b)
            val bXor: Byte = b.bitXor(b)
            val bInv: Byte = b.bitInv()
            val sAnd: Short = s bitAnd s
            val sOr: Short = s.bitOr(s)
            val sXor: Short = s.bitXor(s)
            val sInv: Short = s.bitInv()
        }
        """,
        // 8: user extensions retain their own return types
        """
        package sample8
        infix fun Byte.and(other: Byte): String = "byte and"
        infix fun Byte.or(other: Byte): String = "byte or"
        infix fun Byte.xor(other: Byte): String = "byte xor"
        fun Byte.inv(): String = "byte inv"
        infix fun Short.and(other: Short): String = "short and"
        infix fun Short.or(other: Short): String = "short or"
        infix fun Short.xor(other: Short): String = "short xor"
        fun Short.inv(): String = "short inv"

        fun ops(b: Byte, s: Short) {
            val bAnd: String = b and b
            val bOr: String = b.or(b)
            val bXor: String = b.xor(b)
            val bInv: String = b.inv()
            val sAnd: String = s and s
            val sOr: String = s.or(s)
            val sXor: String = s.xor(s)
            val sInv: String = s.inv()
        }
        """,
        // 9: builtin signed/unsigned/Boolean bitwise members remain available
        """
        package sample9
        fun ops(i: Int, l: Long, ui: UInt, ul: ULong, ub: UByte, us: UShort, b: Boolean) {
            val iResult: Int = (i and i) or (i xor i.inv())
            val lResult: Long = (l and l) or (l xor l.inv())
            val uiResult: UInt = (ui and ui) or (ui xor ui.inv())
            val ulResult: ULong = (ul and ul) or (ul xor ul.inv())
            val ubResult: UByte = (ub and ub) or (ub xor ub.inv())
            val usResult: UShort = (us and us) or (us xor us.inv())
            val bResult: Boolean = (b and b) or (b xor b.not())
        }
        """,
    ]

    private static nonisolated(unsafe) var _shared: (ctx: CompilationContext, paths: [String])?

    private func shared() throws -> (ctx: CompilationContext, paths: [String]) {
        if let cached = Self._shared { return cached }
        var result: (ctx: CompilationContext, paths: [String])?
        try withTemporaryFiles(contents: Self.sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = (ctx, paths)
        }
        let pair = try #require(result)
        Self._shared = pair
        return pair
    }

    @Test func testByteBitwiseOperationsResolveWithoutDiagnostics() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Byte bitwise operations to resolve: \(errors.map { $0.message })"
        )
    }

    @Test func testShortBitwiseOperationsResolveWithoutDiagnostics() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[1], in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Short bitwise operations to resolve: \(errors.map { $0.message })"
        )
    }

    @Test func testUnimportedByteShortBitwiseMembersAreRejected() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[5], in: ctx).filter { $0.severity == .error }
        #expect(errors.count == 28, "Expected every unimported bitwise/shift call to fail: \(errors)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        for name in ["and", "or", "xor", "inv", "shl", "shr", "ushr"] {
            let call = try #require(firstExprID(in: ast, path: paths[5], ctx: ctx) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == name
            })
            #expect(sema.bindings.exprType(for: call) == sema.types.errorType)
        }
    }

    @Test(arguments: [6, 7, 8, 9])
    func testScopedExtensionsAndBuiltinMembersResolve(sample: Int) throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[sample], in: ctx).filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected sample \(sample) to resolve: \(errors)")
    }

    @Test func testUnimportedByteShortBitwiseExtensionsAreRejectedInIsolation() throws {
        try withTemporaryFiles(contents: [Self.sources[5]]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(errors.count == 28, "Expected unimported bitwise extensions to be rejected: \(errors)")
        }
    }

    @Test func testAliasedImportsDoNotExposeOriginalNames() throws {
        let source = """
        import kotlin.experimental.and as bitAnd
        import kotlin.experimental.inv as bitInv
        fun ops(b: Byte, s: Short) {
            b.bitAnd(b)
            s.bitAnd(s)
            b.bitInv()
            s.bitInv()
            b.and(b)
            s.and(s)
            b.inv()
            s.inv()
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(errors.count == 4, "Expected only the original names to be unresolved: \(errors)")
        }
    }

    @Test func testBitwiseResultKeepsReceiverType() throws {
        let (ctx, paths) = try shared()
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let samples: [(path: String, typeName: String, receiverType: TypeID)] = [
            (paths[3], "Byte", sema.types.byteType),
            (paths[4], "Short", sema.types.shortType),
        ]

        for (samplePath, typeName, receiverType) in samples {
            for name in ["and", "inv"] {
                let callExpr = try #require(
                    firstExprID(in: ast, path: samplePath, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        return ctx.interner.resolve(callee) == name
                    },
                    "Expected \(typeName).\(name) member call"
                )
                #expect(
                    sema.bindings.exprType(for: callExpr) == receiverType,
                    "\(typeName).\(name) should keep the receiver type"
                )
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName.dropLast().map(ctx.interner.resolve) == ["kotlin", "experimental"])
                #expect(sema.symbols.isSourceBackedSymbol(chosen))
            }
        }
    }

    @Test func testIntBitwiseIsNotNarrowedByExperimentalImports() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[2], in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Int bitwise operations to resolve: \(errors.map { $0.message })"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callExpr = try #require(
            firstExprID(in: ast, path: paths[2], ctx: ctx) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "and"
            },
            "Expected Int.and member call"
        )
        #expect(sema.bindings.exprType(for: callExpr) == sema.types.intType)
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ImplicitReceiverLiteralExtensionTests {
    private let declarations = """
    class Builder {
        fun append(value: Byte): Int = 1
        fun append(value: String): Int = 2
    }
    fun Builder.append(value: UByte): Int = 3
    fun Builder.append(vararg values: Byte): Int = 4
    """

    @Test
    func implicitExtensionsContextualizeLiteralsAndKeepMemberPrecedence() throws {
        let source = declarations + """

        fun Builder.probe(): Int {
            append(103, 104, 105)
            append(0x80U)
            return append(127)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            for value in [103, 104, 105] {
                let literal = try #require(firstExprID(in: ast) { _, expr in
                    if case let .intLiteral(number, _) = expr { return number == Int64(value) }
                    return false
                })
                #expect(sema.bindings.exprType(for: literal) == sema.types.byteType)
            }
            let unsigned = try #require(firstExprID(in: ast) { _, expr in
                if case .uintLiteral(128, _) = expr { return true }
                return false
            })
            #expect(sema.bindings.exprType(for: unsigned) == sema.types.ubyteType)
            let memberCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(_, _, args, _) = expr, args.count == 1 else { return false }
                if case .intLiteral(127, _) = ast.arena.expr(args[0].expr) { return true }
                return false
            })
            let chosen = try #require(sema.bindings.callBinding(for: memberCall)?.chosenCallee)
            #expect(sema.symbols.symbol(chosen)?.fqName.map { ctx.interner.resolve($0) } == ["Builder", "append"])
            #expect(sema.symbols.functionSignature(for: chosen)?.parameterTypes == [sema.types.byteType])
        }
    }

    @Test(arguments: ["append(128, 0)", "append(256U)", "append(signed, 0)", "append(unsigned)"])
    func implicitExtensionsRejectOutOfRangeAndTypedVariables(call: String) throws {
        let source = declarations + """

        fun Builder.probe(signed: Int, unsigned: UInt) { \(call) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "Expected rejected argument: \(call)")
        }
    }

    @Test
    func implicitExtensionCannotAccessPrivateDeclarationInAnotherFile() throws {
        let sources = [
            "package sample; class Builder; private fun Builder.append(value: UByte) {}",
            "package sample; fun Builder.use() { append(128U) }",
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "A file-private extension must stay inaccessible")
        }
    }

    @Test
    func implicitExtensionCanAccessPrivateDeclarationInSameFile() throws {
        let source = """
        package sample
        class Builder
        private fun Builder.append(value: UByte) {}
        fun Builder.use() { append(128U) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-905/KSP-908: published internal storage constructors participate in
/// overload resolution without replacing primitive size-only allocation.
@Suite
struct UnsignedArrayConstructorResolutionTests {
    @Test
    func publishedStorageConstructorsResolveToBundledSource() throws {
        let ctx = makeContextFromSource("""
        @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

        fun fromBytes(storage: ByteArray): UByteArray = UByteArray(storage)
        fun fromInts(storage: IntArray): UIntArray = UIntArray(storage)
        """)
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected unsigned storage constructors to resolve cleanly: \(ctx.diagnostics.diagnostics)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        for (arrayName, storageTypeName) in [
            ("UByteArray", "ByteArray"),
            ("UIntArray", "IntArray"),
        ] {
            let callExpr = try #require(userCall(named: arrayName, ast: ast, ctx: ctx))
            let chosenCallee = try #require(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected \(arrayName)(storage) to bind its source constructor"
            )
            let symbol = try #require(sema.symbols.symbol(chosenCallee))
            let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))

            #expect(symbol.visibility == .internal)
            #expect(!symbol.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
            #expect(signature.parameterTypes.count == 1)
            guard case let .classType(storageType) = sema.types.kind(of: signature.parameterTypes[0]),
                  case let .classType(returnType) = sema.types.kind(of: signature.returnType),
                  let storageSymbol = sema.symbols.symbol(storageType.classSymbol),
                  let returnSymbol = sema.symbols.symbol(returnType.classSymbol)
            else {
                Issue.record("Expected \(arrayName)(storage) to use class-typed storage and return values")
                continue
            }
            #expect(ctx.interner.resolve(storageSymbol.name) == storageTypeName)
            #expect(ctx.interner.resolve(returnSymbol.name) == arrayName)
            #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil)
        }
    }

    @Test
    func storageConstructorsDoNotShadowPrimitiveSizeAllocation() throws {
        let ctx = makeContextFromSource("""
        fun allocateUBytes(size: Int): UByteArray = UByteArray(size)
        fun allocateUInts(size: Int): UIntArray = UIntArray(size)
        """)
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected unsigned size constructors to resolve cleanly: \(ctx.diagnostics.diagnostics)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        for arrayName in ["UByteArray", "UIntArray"] {
            let callExpr = try #require(userCall(named: arrayName, ast: ast, ctx: ctx))
            #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == nil)
            #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == .arrayConstructor)
        }
    }

    private func userCall(
        named expectedName: String,
        ast: ASTModule,
        ctx: CompilationContext
    ) -> ExprID? {
        firstExprID(in: ast) { _, expr in
            guard case let .call(callee, _, _, range) = expr,
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  case let .nameRef(name, _) = ast.arena.expr(callee)
            else {
                return false
            }
            return ctx.interner.resolve(name) == expectedName
        }
    }
}
#endif

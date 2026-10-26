#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct ArrayConstructorResolutionTests {
    @Test
    func initializerConstructorResolvesToBundledSource() throws {
        let ctx = makeContextFromSource("""
        fun make(): Array<Int> = Array(3) { it * 2 }
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "Expected Array initializer to resolve: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(firstArrayCall(in: ast, ctx: ctx, argumentCount: 2))
        let chosen = try #require(
            sema.bindings.callBinding(for: call)?.chosenCallee,
            "Expected Array(size, init) to bind a source declaration"
        )
        let symbol = try #require(sema.symbols.symbol(chosen))
        let signature = try #require(sema.symbols.functionSignature(for: chosen))

        #expect(symbol.kind == .function)
        #expect(sema.symbols.isSourceBackedSymbol(chosen))
        #expect(sema.symbols.externalLinkName(for: chosen) == nil)
        #expect(signature.parameterTypes.count == 2)
        #expect(signature.typeParameterSymbols.count == 1)
    }

    @Test
    func sizeOnlyConstructorUsesCheckedCompilerAllocation() throws {
        let ctx = makeContextFromSource("""
        fun make(): Array<String?> = Array(2)
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "Expected Array(size) to resolve: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(firstArrayCall(in: ast, ctx: ctx, argumentCount: 1))

        #expect(sema.bindings.callBinding(for: call)?.chosenCallee == nil)
        #expect(sema.bindings.stdlibSpecialCallKind(for: call) == .arrayConstructor)
    }

    @Test
    func sizeOnlyPrimitiveArraysResolveLastToTheirElementTypeFromSource() throws {
        try assertSizeOnlyPrimitiveArraysResolveLastToTheirElementType(useArtifact: false)
    }

    @Test
    func sizeOnlyPrimitiveArraysResolveLastToTheirElementTypeFromArtifact() throws {
        try assertSizeOnlyPrimitiveArraysResolveLastToTheirElementType(useArtifact: true)
    }

    private func assertSizeOnlyPrimitiveArraysResolveLastToTheirElementType(useArtifact: Bool) throws {
        if useArtifact {
            TestStdlibCache.shared.prepare()
        }
        let ctx = makeContextFromSource("""
        fun lastBoolean(size: Int): Boolean {
            val valuesBoolean = BooleanArray(size + 1)
            return valuesBoolean.last()
        }
        fun lastByte(size: Int): Byte {
            val valuesByte = ByteArray(size + 1)
            return valuesByte.last()
        }
        fun lastShort(size: Int): Short {
            val valuesShort = ShortArray(size + 1)
            return valuesShort.last()
        }
        fun lastInt(size: Int): Int {
            val valuesInt = IntArray(size + 1)
            return valuesInt.last()
        }
        fun lastLong(size: Int): Long {
            val valuesLong = LongArray(size + 1)
            return valuesLong.last()
        }
        fun lastFloat(size: Int): Float {
            val valuesFloat = FloatArray(size + 1)
            return valuesFloat.last()
        }
        fun lastDouble(size: Int): Double {
            val valuesDouble = DoubleArray(size + 1)
            return valuesDouble.last()
        }
        fun lastChar(size: Int): Char {
            val valuesChar = CharArray(size + 1)
            return valuesChar.last()
        }
        fun preservedArrayPaths(size: Int): Double {
            val values = DoubleArray(size + 1)
            val initialized = DoubleArray(size + 1) { it.toDouble() }
            return values.first() + (values.lastOrNull() ?: 0.0) + values[0] + values.map { it }.size.toDouble() +
                initialized.last() + IntArray(size + 1).last().toDouble()
        }
        """, allowDefaultStdlibLibrary: useArtifact)
        #expect((ctx.options.stdlibLibraryPath != nil) == useArtifact)
        do {
            try runSema(ctx)
        } catch {
            // Keep inspecting recovered bindings to report the selected overload.
        }

        #expect(
            !ctx.diagnostics.hasError,
            "Expected size-only primitive-array last() calls to resolve: \(ctx.diagnostics.diagnostics)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let lastName = ctx.interner.intern("last")
        let cases: [(arrayName: String, receiverName: String, elementType: TypeID)] = [
            ("BooleanArray", "valuesBoolean", sema.types.booleanType),
            ("ByteArray", "valuesByte", sema.types.byteType),
            ("ShortArray", "valuesShort", sema.types.shortType),
            ("IntArray", "valuesInt", sema.types.intType),
            ("LongArray", "valuesLong", sema.types.longType),
            ("FloatArray", "valuesFloat", sema.types.floatType),
            ("DoubleArray", "valuesDouble", sema.types.doubleType),
            ("CharArray", "valuesChar", sema.types.charType),
        ]

        for testCase in cases {
            let receiverName = ctx.interner.intern(testCase.receiverName)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(receiver, callee, _, arguments, range) = expr,
                      callee == lastName,
                      arguments.isEmpty,
                      ctx.sourceManager.origin(of: range.start.file) == .user,
                      case let .nameRef(name, _) = ast.arena.expr(receiver)
                else {
                    return false
                }
                return name == receiverName
            }, "Expected \(testCase.arrayName).last() call")
            let chosenCallee = try #require(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected \(testCase.arrayName).last() to bind its specialized source overload"
            )
            let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
            let receiverType = try #require(signature.receiverType)
            guard case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                  let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
            else {
                Issue.record("Expected \(testCase.arrayName).last() to have a nominal receiver type")
                continue
            }

            #expect(ctx.interner.resolve(receiverSymbol.name) == testCase.arrayName)
            #expect(sema.symbols.symbol(chosenCallee)?.fqName.map(ctx.interner.resolve) == [
                "kotlin", "collections", "last",
            ])
            #expect(signature.returnType == testCase.elementType)
            #expect(sema.bindings.exprType(for: callExpr) == testCase.elementType)
            #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
        }
    }

    private func firstArrayCall(
        in ast: ASTModule,
        ctx: CompilationContext,
        argumentCount: Int
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .call(callee, _, args, _) = ast.arena.expr(exprID),
                  args.count == argumentCount,
                  let range = ast.arena.exprRange(exprID),
                  !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_"),
                  case let .nameRef(name, _) = ast.arena.expr(callee),
                  name == KnownCompilerNames(interner: ctx.interner).array
            else {
                continue
            }
            return exprID
        }
        return nil
    }
}
#endif

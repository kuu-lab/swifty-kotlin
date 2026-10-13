#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache

@Suite
struct LocalLateinitTests {
    private func context(_ source: String, useLibrary: Bool = false,
                         includeStdlib: Bool = true) throws -> CompilationContext {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let library = useLibrary
            ? try #require(CompilerOptions.defaultStdlibLibraryPath,
                           "Library mode must use the published stdlib artifact") : nil
        if let library {
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: library, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
            let directory = URL(fileURLWithPath: library, isDirectory: true)
            #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("manifest.json").path))
            #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("metadata.bin").path))
        }
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: includeStdlib,
                                         stdlibLibraryPath: library, allowDefaultStdlibLibrary: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        #expect(ctx.options.stdlibLibraryPath == library)
        #expect(ctx.options.includeStdlib == (includeStdlib && !useLibrary))
        return ctx
    }

    private func fixture(_ name: String) throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent("Scripts/diff_cases/" + name), encoding: .utf8)
    }

    @Test func preservesLateinitInBlockAndLambdaASTAndDefaultsOrdinaryLocalToFalse() throws {
        let source = """
        fun make() {
            lateinit var direct: String
            var ordinary: String
            val nested = { lateinit var captured: String; captured }
        }
        """
        let ctx = try context(source, includeStdlib: false)
        try runFrontend(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let flags = Dictionary(uniqueKeysWithValues: ast.arena.exprs.compactMap { expr -> (String, Bool)? in
            guard case let .localDecl(name, _, _, _, _, isLateinit, _) = expr else { return nil }
            return (ctx.interner.resolve(name), isLateinit)
        })
        #expect(flags == ["direct": true, "ordinary": false, "nested": false, "captured": true])
        // `default: false` is also part of the programmatic AST API.
        let range = SourceRange(start: SourceLocation(file: .invalid, offset: 0),
                                end: SourceLocation(file: .invalid, offset: 1))
        let generated = Expr.localDecl(name: ctx.interner.intern("generated"), isMutable: true,
                                       typeAnnotation: nil, initializer: nil, range: range)
        guard case let .localDecl(_, _, _, _, _, isLateinit, _) = generated else {
            Issue.record("Expected local declaration"); return
        }
        #expect(!isLateinit)
    }

    @Test(arguments: [false, true])
    func acceptsOriginalRuntimeOracleAndRetainsLateinitSymbolFlags(useLibrary: Bool) throws {
        let ctx = try context(try fixture("local_lateinit_runtime.kt"), useLibrary: useLibrary)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let input = try #require(ctx.options.inputs.first)
        let sourceFile = try #require(ctx.sourceManager.fileID(forPath: input))
        let declarations: [(String, SymbolID)] = try ast.arena.exprs.enumerated().compactMap { index, expr in
            guard case let .localDecl(name, _, _, _, _, true, range) = expr,
                  range.start.file == sourceFile else { return nil }
            let id = ExprID(rawValue: Int32(index))
            let symbol = try #require(sema.bindings.identifierSymbols[id])
            return (ctx.interner.resolve(name), symbol)
        }
        #expect(Set(declarations.map(\.0)) == ["local", "captured", "assigned", "callback"])
        for (_, symbol) in declarations {
            let info = try #require(sema.symbols.symbol(symbol))
            #expect(info.kind == .local)
            #expect(info.flags.contains([.mutable, .lateinitProperty]))
            let type = try #require(sema.symbols.propertyType(for: symbol))
            #expect(sema.types.nullability(of: type) == .nonNull)
        }
    }

    @Test func preservesOrdinaryUninitializedErrorsAndRejectsInvalidLateinitForms() throws {
        // These exact nine functions also have a pinned Kotlin/JVM rejection
        // receipt; this test verifies the candidate's diagnostic classification.
        let source = """
        fun ordinaryVal() { val ordinaryVal: String; println(ordinaryVal) }
        fun ordinaryVar() { var ordinaryVar: String; println(ordinaryVar) }
        fun ordinaryCapture() { var ordinaryCapture: String; val reader = { ordinaryCapture }; println(reader()) }
        fun invalidVal() { lateinit val invalidVal: String }
        fun invalidNullable() { lateinit var invalidNullable: String? }
        fun invalidInt() { lateinit var invalidInt: Int }
        fun invalidByte() { lateinit var invalidByte: Byte }
        fun invalidShort() { lateinit var invalidShort: Short }
        fun invalidInitializer() { lateinit var invalidInitializer: String = "x" }
        """
        let ctx = try context(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 9, "\(errors)")
        let ordinary = errors.filter { $0.code == "KSWIFTK-SEMA-0031" }
        #expect(ordinary.count == 3, "\(ordinary)")
        for name in ["ordinaryVal", "ordinaryVar", "ordinaryCapture"] {
            #expect(ordinary.filter { $0.message.contains("'" + name + "'") }.count == 1)
        }
        #expect(errors.filter { $0.code == "KSWIFTK-SEMA-0418" }.count == 1,
                "The existing parser's invalid-val diagnostic must not be duplicated")
        #expect(errors.filter { $0.code == "KSWIFTK-SEMA-LATEINIT" }.count == 5)
        // Bind each invalid declaration to its own diagnostic range, so a
        // duplicate diagnostic cannot compensate for a silently accepted form.
        let ast = try #require(ctx.ast)
        let input = try #require(ctx.options.inputs.first)
        let sourceFile = try #require(ctx.sourceManager.fileID(forPath: input))
        for expr in ast.arena.exprs {
            guard case let .localDecl(name, _, _, _, _, true, range) = expr,
                  range.start.file == sourceFile else { continue }
            let expected = ctx.interner.resolve(name) == "invalidVal"
                ? "KSWIFTK-SEMA-0418" : "KSWIFTK-SEMA-LATEINIT"
            #expect(errors.filter { diagnostic in
                diagnostic.code == expected && diagnostic.primaryRange.map { range.contains($0) } == true
            }.count == 1, "Expected one declaration-specific diagnostic for \(ctx.interner.resolve(name))")
        }
    }

    @Test func seedsDirectStorageAndChecksReadsWithOrdinaryExceptionPropagation() throws {
        let ctx = try context("""
        fun readDirect(): String { lateinit var value: String; return value }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "readDirect", in: module, interner: ctx.interner)
        let checks = kirCalls(to: .lateinitGetOrThrow, in: body, interner: ctx.interner)
        #expect(checks.count == 1)
        let check = try #require(checks.first)
        #expect(check.canThrow && check.thrownResult == nil)
        try #require(check.arguments.count == 2)
        let value = try #require(check.arguments.first)
        let seeds = body.enumerated().compactMap { index, instruction -> Int? in
            guard case let .copy(from, to) = instruction, to == value,
                  case .null = module.arena.expr(from) else { return nil }
            return index
        }
        #expect(seeds.count == 1 && seeds.allSatisfy { $0 < check.index },
                "The checked read must receive the declaration's stable sentinel slot")
        #expect(module.arena.expr(check.arguments[1]) == .stringLiteral(ctx.interner.intern("value")))
    }

    @Test func capturesRawStringCellAndChecksOnlyInsideEscapingReader() throws {
        let ctx = try context("""
        fun makeReader(): () -> String {
            lateinit var captured: String
            return { captured }
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let maker = try findKIRFunctionBody(named: "makeReader", in: module, interner: ctx.interner)
        #expect(kirCalls(to: .lateinitGetOrThrow, in: maker, interner: ctx.interner).isEmpty,
                "Declaring and capturing the sentinel must not throw")
        let creation = try #require(kirFunctionCreationCalls(in: maker, interner: ctx.interner).first)
        let cellStore = try #require(kirCalls(to: .arraySet, in: maker, interner: ctx.interner).first)
        #expect(cellStore.index < creation.index)
        try #require(cellStore.arguments.count == 3)
        let rawSeed = cellStore.arguments[2]
        #expect(maker.contains { instruction in
            guard case let .copy(from, to) = instruction, to == rawSeed else { return false }
            return module.arena.expr(from) == .null
        }, "String capture must receive the raw sentinel slot")
        let readerBodies = findAllKIRFunctions(in: module).filter { function in
            kirCalls(to: .lateinitGetOrThrow, in: function.body, interner: ctx.interner).contains { call in
                call.arguments.count == 2
                    && module.arena.expr(call.arguments[1]) == .stringLiteral(ctx.interner.intern("captured"))
            }
        }
        #expect(readerBodies.count == 1)
        let reader = try #require(readerBodies.first)
        let check = try #require(kirCalls(to: .lateinitGetOrThrow, in: reader.body, interner: ctx.interner).first)
        #expect(check.canThrow && check.thrownResult == nil)
        try #require(check.arguments.count == 2)
        let cellLoads = kirCalls(to: .arrayGetInbounds, in: reader.body, interner: ctx.interner)
        #expect(cellLoads.contains { $0.index < check.index && $0.result == check.arguments[0] },
                "Every closure invocation checks the live cell's contents")
    }

    @Test func checksCompoundAndReceiverCallableShortcutReads() throws {
        let ctx = try context("""
        fun compound() { lateinit var text: String; text += "x" }
        fun receiverCall(): String {
            lateinit var action: String.() -> String
            return "receiver".action()
        }
        fun safeReceiverCall(receiver: String?): String? {
            lateinit var action: String.() -> String
            return receiver?.action()
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        for name in ["compound", "receiverCall", "safeReceiverCall"] {
            let body = try findKIRFunctionBody(named: name, in: module, interner: ctx.interner)
            let checks = kirCalls(to: .lateinitGetOrThrow, in: body, interner: ctx.interner)
            #expect(checks.count == 1, "\(name): \(body)")
            #expect(checks.allSatisfy { $0.canThrow && $0.thrownResult == nil })
            if name == "safeReceiverCall" {
                let callLabel = try #require(body.compactMap { instruction -> Int32? in
                    if case let .jumpIfNotNull(_, target) = instruction { return target }
                    return nil
                }.first)
                let nonNullStart = try #require(body.enumerated().first { _, instruction in
                    if case let .label(label) = instruction { return label == callLabel }
                    return false
                }?.offset)
                #expect(checks.allSatisfy { $0.index > nonNullStart },
                        "A null receiver must skip the lateinit callable read")
            }
        }
    }

    @Test(arguments: [false, true])
    func acceptsProvenNonNullGenericBounds(useLibrary: Bool) throws {
        let ctx = try context("""
        fun <T : Any> validAny(input: T): T {
            lateinit var value: T; value = input; return value
        }
        fun <T : U, U : Any> validTransitive(input: T): T {
            lateinit var value: T; value = input; return value
        }
        fun <T : Comparable<T>> validSelfBound(input: T): T {
            lateinit var value: T; value = input; return value
        }
        fun validUnit() { lateinit var value: Unit }
        fun validNothing() { lateinit var value: Nothing }
        """, useLibrary: useLibrary)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [false, true])
    func rejectsNullableUpperBoundsAndDirectValueClass(useLibrary: Bool) throws {
        let ctx = try context("""
        fun <T> invalidDefault() { lateinit var defaultBound: T }
        fun <T : Any?> invalidNullable() { lateinit var nullableBound: T }
        fun <T : U, U> invalidTransitive() { lateinit var transitiveBound: T }
        @JvmInline value class InlineValue(val word: Long)
        fun invalidValueClass() { lateinit var inlineValue: InlineValue }
        """, useLibrary: useLibrary)
        try runSema(ctx)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 4, "\(errors)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-LATEINIT" })
        let input = try #require(ctx.options.inputs.first)
        let sourceFile = try #require(ctx.sourceManager.fileID(forPath: input))
        var checkedNames: Set<String> = []
        for (index, expr) in ast.arena.exprs.enumerated() {
            guard case let .localDecl(name, _, _, _, _, true, range) = expr,
                  range.start.file == sourceFile,
                  sema.bindings.identifierSymbols[ExprID(rawValue: Int32(index))] != nil
            else { continue }
            checkedNames.insert(ctx.interner.resolve(name))
            #expect(errors.filter {
                $0.code == "KSWIFTK-SEMA-LATEINIT"
                    && $0.primaryRange.map { range.contains($0) } == true
            }.count == 1)
        }
        #expect(checkedNames == ["defaultBound", "nullableBound", "transitiveBound", "inlineValue"])
    }

    @Test func recursiveBoundProofNeedsConcreteNonNullEvidence() throws {
        let (sema, symbols, types, interner) = makeSemaModule()
        let first = symbols.define(kind: .typeParameter, name: interner.intern("T"),
                                   fqName: [interner.intern("T")], declSite: nil, visibility: .private)
        let second = symbols.define(kind: .typeParameter, name: interner.intern("U"),
                                    fqName: [interner.intern("U")], declSite: nil, visibility: .private)
        let firstType = types.make(.typeParam(TypeParamType(symbol: first, nullability: .nonNull)))
        let secondType = types.make(.typeParam(TypeParamType(symbol: second, nullability: .nonNull)))
        #expect(!lateinitLocalTypeIsDefinitelyNonNull(firstType, sema: sema))
        symbols.setTypeParameterUpperBounds([firstType], for: first)
        #expect(!lateinitLocalTypeIsDefinitelyNonNull(firstType, sema: sema))
        symbols.setTypeParameterUpperBounds([secondType], for: first)
        symbols.setTypeParameterUpperBounds([firstType], for: second)
        #expect(!lateinitLocalTypeIsDefinitelyNonNull(firstType, sema: sema))
        symbols.setTypeParameterUpperBounds([firstType, types.anyType], for: second)
        #expect(lateinitLocalTypeIsDefinitelyNonNull(firstType, sema: sema))
        let nullableFirst = types.make(.typeParam(TypeParamType(symbol: first, nullability: .nullable)))
        #expect(!lateinitLocalTypeIsDefinitelyNonNull(nullableFirst, sema: sema))
    }
}
#endif

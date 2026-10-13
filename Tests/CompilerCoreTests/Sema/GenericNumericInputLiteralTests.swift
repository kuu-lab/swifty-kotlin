#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite
struct GenericNumericInputLiteralTests {
    private func context(_ source: String, library: Bool, cache: Bool) throws -> CompilationContext {
        if library { TestStdlibCache.shared.prepare() }
        let artifact = library ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], frontendFlags: cache ? ["sema-cache"] : [],
                                         stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        #expect(ctx.options.stdlibLibraryPath == artifact)
        #expect(ctx.options.includeStdlib == !library)
        return ctx
    }

    private func sourceFixture(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
    }

    @Test(arguments: [false, true], [false, true])
    func concreteInputsContextualizeSignedAndUnsignedLiterals(library: Bool, cache: Bool) throws {
        let ctx = try context(sourceFixture("Scripts/diff_cases/generic_numeric_input_literals.kt"), library: library, cache: cache)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let expected = [sema.types.longType, sema.types.longType, sema.types.longType, sema.types.longType,
                        sema.types.byteType, sema.types.shortType, sema.types.ubyteType, sema.types.ushortType,
                        sema.types.ulongType, sema.types.intType, sema.types.uintType]
        let sourcePath = try #require(ctx.options.inputs.first)
        let calls = ast.arena.exprs.enumerated().compactMap { index, expr -> ExprID? in
            guard case let .call(callee, _, _, _) = expr,
                  case let .nameRef(name, _) = ast.arena.expr(callee),
                  ctx.interner.resolve(name) == "assertEquals",
                  let range = ast.arena.exprRange(ExprID(rawValue: Int32(index))),
                  ctx.sourceManager.path(of: range.start.file) == sourcePath else { return nil }
            return ExprID(rawValue: Int32(index))
        }
        #expect(calls.count == expected.count)
        for (call, type) in zip(calls, expected) {
            let binding = try #require(sema.bindings.callBinding(for: call))
            #expect(binding.substitutedTypeArguments == [type])
            let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
            #expect(symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "test", "assertEquals"])
            #expect(symbol.flags.contains(.importedLibrary) == library)
            let signature = try #require(sema.symbols.functionSignature(for: symbol.id))
            #expect(signature.typeParameterSymbols.contains { parameter in
                sema.symbols.annotations(for: parameter).contains { $0.annotationFQName == "kotlin.internal.OnlyInputTypes" }
            })
            guard case let .call(_, _, arguments, _) = ast.arena.expr(call) else { continue }
            for (index, argument) in arguments.enumerated() {
                let isContextualLiteral: Bool
                switch ast.arena.expr(argument.expr) {
                case .intLiteral, .uintLiteral:
                    isContextualLiteral = true
                case let .unaryExpr(op, operand, _) where op == .unaryMinus || op == .unaryPlus:
                    if case .intLiteral = ast.arena.expr(operand) { isContextualLiteral = true }
                    else { isContextualLiteral = false }
                default:
                    isContextualLiteral = false
                }
                if isContextualLiteral {
                    #expect(sema.bindings.exprType(for: argument.expr) == type)
                }
                if let label = argument.label {
                    #expect(binding.parameterMapping[index] == (ctx.interner.resolve(label) == "expected" ? 0 : 1))
                }
            }
        }
        let selection = try #require(firstExprID(in: ast, path: sourcePath, ctx: ctx) { _, expr in
            guard case let .call(callee, _, _, _) = expr, case let .nameRef(name, _) = ast.arena.expr(callee) else { return false }
            return ctx.interner.resolve(name) == "chooseNumericInput"
        })
        #expect(sema.bindings.callBinding(for: selection)?.substitutedTypeArguments == [sema.types.byteType])
        #expect(sema.bindings.exprType(for: selection) == sema.types.byteType)
    }

    @Test(arguments: [false, true], [false, true])
    func incompatibleTypedInputsBoundsRangesAndSuffixesRemainRejected(library: Bool, cache: Bool) throws {
        let ctx = try context(sourceFixture("Scripts/kotlinx_io_upstream/fixtures/generic_numeric_input_rejections.kt"), library: library, cache: cache)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 10, "\(errors)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let path = try #require(ctx.options.inputs.first)
        let calls = ast.arena.exprs.enumerated().compactMap { index, expr -> ExprID? in
            guard case let .call(callee, _, _, _) = expr, case let .nameRef(name, _) = ast.arena.expr(callee),
                  ["assertEquals", "numericBound"].contains(ctx.interner.resolve(name)),
                  let range = ast.arena.exprRange(ExprID(rawValue: Int32(index))),
                  ctx.sourceManager.path(of: range.start.file) == path else { return nil }
            return ExprID(rawValue: Int32(index))
        }
        #expect(calls.count == 10)
        for call in calls { #expect(sema.bindings.callBinding(for: call) == nil) }
    }

    // A user annotation with the same short name is not compiler inference policy.
    // Actual source symbols feed MetadataEncoder in both stdlib modes.
    @Test(arguments: [false, true])
    func sameNameUserMarkerDoesNotRestrictOrSerializeInputTypes(library: Bool) throws {
        let ctx = try context("""
        package markercontrol
        @Target(AnnotationTarget.TYPE_PARAMETER)
        annotation class OnlyInputTypes
        fun <@OnlyInputTypes T> ordinary(value: T, other: T): T = other
        fun use() {
            val intValue: Int = 0
            val longValue: Long = 0L
            ordinary(intValue, longValue)
        }
        """, library: library, cache: false)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let function = try #require(sema.symbols.lookup(
            fqName: ["markercontrol", "ordinary"].map(ctx.interner.intern)
        ))
        let signature = try #require(sema.symbols.functionSignature(for: function))
        let parameter = try #require(signature.typeParameterSymbols.first)
        #expect(sema.symbols.annotations(for: parameter).contains {
            $0.annotationFQName == "markercontrol.OnlyInputTypes"
        })
        #expect(!sema.symbols.annotations(for: parameter).contains {
            $0.annotationFQName == "kotlin.internal.OnlyInputTypes"
        })
        let path = try #require(ctx.options.inputs.first)
        let call = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
            guard case let .call(callee, _, _, _) = expr,
                  case let .nameRef(name, _) = ast.arena.expr(callee) else { return false }
            return ctx.interner.resolve(name) == "ordinary"
        })
        #expect(sema.bindings.callBinding(for: call)?.chosenCallee == function)
        let encoder = MetadataEncoder()
        let record = try #require(encoder.buildRecords(
            symbols: sema.symbols, types: sema.types,
            moduleName: "MarkerProducer", interner: ctx.interner, functionLinkNames: [:]
        ).first { $0.fqName == "markercontrol.ordinary" })
        #expect(record.inputOnlyTypeParameterIndices.isEmpty)
        for encoded in [encoder.serialize([record]), encoder.serializeIndexed([record])] {
            let decoded = try #require(MetadataDecoder().decode(encoded).first)
            #expect(decoded.fqName == record.fqName)
            #expect(decoded.inputOnlyTypeParameterIndices.isEmpty,
                    "Impostor marker must not become genuine policy at import")
        }
    }
}
#endif

import Foundation
@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct ReifiedCallableReferenceTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test(arguments: [false, true])
    func referencesStoreDeclarationOrderTypeArgumentsAndOuterTokens(fromSource: Bool) throws {
        let source = try String(contentsOf: repository.appendingPathComponent(
            "Scripts/diff_cases/callable_reference_reified_tokens.kt"), encoding: .utf8)
        let context = try frontend([source], fromSource: fromSource)
        try #require(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let ast = try #require(context.ast)
        let sema = try #require(context.sema)
        let references = ast.arena.exprs.enumerated().compactMap { index, expression -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard isUserSourceExpr(id, in: context), case .callableRef = expression,
                  let target = sema.bindings.identifierSymbol(for: id),
                  sema.symbols.functionSignature(for: target)?.reifiedTypeParameterIndices.isEmpty == false
            else { return nil }
            return id
        }
        #expect(references.count >= 15)
        for reference in references {
            let binding = try #require(sema.bindings.callableReferenceBinding(for: reference))
            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            #expect(binding.substitutedTypeArguments.count == signature.typeParameterSymbols.count)
            #expect(binding.parameterMapping.isEmpty)
            #expect(sema.bindings.callBinding(for: reference) == nil)
            for index in signature.reifiedTypeParameterIndices {
                let argument = binding.substitutedTypeArguments[index]
                #expect(argument != sema.types.errorType)
                if case let .typeParam(parameter) = sema.types.kind(of: argument) {
                    #expect(sema.symbols.symbol(parameter.symbol)?.flags.contains(.reifiedTypeParameter) == true)
                }
            }
        }
        let outerCaptures = sema.symbols.allSymbols().flatMap { owner in
            sema.bindings.objectLiteralCaptureSymbols(for: owner.id)
        }.filter { sema.symbols.symbol($0)?.flags.contains(.reifiedTypeParameter) == true }
        #expect(outerCaptures.count >= 2)
        #expect(outerCaptures.allSatisfy { sema.bindings.capturedLocalType(for: $0) == sema.types.intType })
    }

    @Test(arguments: [false, true])
    func contextualInputEvidenceInfersOnlyTheCallersReturnLeaf(fromSource: Bool) throws {
        let context = try frontend(["""
        inline fun <reified T> name(value: T): String = T::class.simpleName ?: "unknown"
        inline fun <reified T> both(first: T, second: T): String = name(first)
        fun <R> apply(value: Int, reference: (Int) -> R): R = reference(value)
        fun <R> use(value: R, reference: (Int, R) -> String): String = reference(1, value)
        val applied: String = apply(1, ::name)
        class Other
        val correlated: String = use(Other(), ::both)
        val mapped: List<String> = listOf("x", "y").map(::name)
        inline fun <reified T> factory(): () -> ((T) -> String) = { ::name }
        fun pick(value: Int): Int = value
        inline fun <reified T> pick(value: T): String = name(value)
        fun <R : Number> boundedResult(reference: (Int) -> R): R = reference(1)
        val selected: Int = boundedResult(::pick)
        class Shadow<T> { inline fun <reified T> reference(): (T) -> String = ::name }
        val shadowed: (String) -> String = Shadow<Int>().reference<String>()
        inline fun <reified T> maybe(value: T): String? = null
        fun <R : Any> nullableResult(reference: (Int) -> R?): R? = reference(1)
        val nullable: String? = nullableResult(::maybe)
        inline fun <reified T> make(): T = TODO()
        fun <R> result(reference: () -> R): R = reference()
        val made: String = result(::make)
        interface Parent
        interface Child : Parent
        class Impl : Child
        fun <R : Child> boundedReference(reference: () -> R): R = reference()
        val boundedLambda: Parent = boundedReference { Impl() }
        val boundedCallable: Parent = boundedReference(::make)
        """], fromSource: fromSource)
        try #require(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let ast = try #require(context.ast)
        let sema = try #require(context.sema)
        let references = ast.arena.exprs.enumerated().compactMap { index, expression -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard isUserSourceExpr(id, in: context), case let .callableRef(_, member, _) = expression else { return nil }
            // T::class is a class literal; it does not invoke a function or
            // need the callable-reference argument binding under test.
            return context.interner.resolve(member) == "class" ? nil : id
        }
        // Lambda parsing retains provisional nodes in the arena. Check the
        // typed nodes while requiring coverage of every source occurrence.
        let typedReferences = references.filter { sema.bindings.exprType(for: $0) != nil }
        let ranges = Set(references.compactMap { ast.arena.exprRange($0) })
        #expect(ranges == Set(typedReferences.compactMap { ast.arena.exprRange($0) }))
        #expect(ranges.count == 9)
        for id in typedReferences {
            guard case let .callableRef(_, member, _) = ast.arena.expr(id) else { continue }
            #expect(sema.bindings.callableRefKind(for: id) == .functionRef)
            if context.interner.resolve(member) == "pick" {
                let target = try #require(sema.bindings.identifierSymbol(for: id))
                let signature = try #require(sema.symbols.functionSignature(for: target))
                #expect(signature.typeParameterSymbols.isEmpty)
                #expect(signature.returnType == sema.types.intType)
            } else {
                let binding = try #require(sema.bindings.callableReferenceBinding(for: id))
                if let type = sema.bindings.exprType(for: id), case let .functionType(function) = sema.types.kind(of: type),
                   let parameter = function.params.first, case let .typeParam(rigid) = sema.types.kind(of: parameter) {
                    #expect(binding.substitutedTypeArguments.contains(parameter))
                    #expect(sema.symbols.symbol(rigid.symbol)?.flags.contains(.reifiedTypeParameter) == true)
                }
            }
        }
    }

    @Test(arguments: [false, true])
    func invalidReifiedArgumentsAndKnownShapesAreRejected(fromSource: Bool) throws {
        let probes: [(String, String)] = [
            ("fun <U> bad(): (U) -> String = ::name", "KSWIFTK-SEMA-REIFIED"),
            ("val bad: (String) -> String = ::bounded", "KSWIFTK-SEMA-INFER"),
            ("val bad = ::name", "KSWIFTK-SEMA-INFER"),
            ("val bad: (Int, Int) -> String = ::name", "KSWIFTK-SEMA-INFER"),
            ("val bad: (String) -> String = ::suspended", "KSWIFTK-SEMA-INFER"),
            ("val bad: (String?) -> String = ::nonNull", "KSWIFTK-SEMA-INFER"),
            ("val bad: (String) -> Int = ::name", "KSWIFTK-SEMA-INFER"),
            ("fun <R> use(f: (Int, Int) -> R): R = f(1, 2); val bad = use(::name)", "KSWIFTK-SEMA-INFER"),
            ("fun <R> use(f: (Int) -> List<R>): List<R> = f(1); val bad = use(::name)", "KSWIFTK-SEMA-INFER"),
            ("fun <R> use(f: (Int) -> R): R = f(1); val bad = use(::suspended)", "KSWIFTK-SEMA-INFER"),
        ]
        let context = try frontend(probes.enumerated().map { index, probe in
            """
            package reifiednegative\(index)
            inline fun <reified T> name(value: T): String = T::class.simpleName ?: "unknown"
            inline fun <reified T : Number> bounded(value: T): String = name(value)
            inline fun <reified T : Any> nonNull(value: T): String = name(value)
            suspend inline fun <reified T> suspended(value: T): String = name(value)
            \(probe.0)
            """
        }, fromSource: fromSource)
        for (index, probe) in probes.enumerated() {
            let file = try #require(context.sourceManager.fileID(forPath: "/tmp/reified-callable-reference-\(index).kt"))
            #expect(context.diagnostics.diagnostics.contains {
                $0.severity == .error && $0.code == probe.1 && $0.primaryRange?.start.file == file
            }, "\(probe.0): \(context.diagnostics.diagnostics)")
        }
    }

    private func frontend(_ sources: [String], fromSource: Bool) throws -> CompilationContext {
        let paths = sources.indices.map { "/tmp/reified-callable-reference-\($0).kt" }
        let stdlib: String?
        if fromSource {
            stdlib = nil
        } else {
            TestStdlibCache.shared.prepare()
            stdlib = try #require(CompilerOptions.defaultStdlibLibraryPath)
        }
        return CompilerDriver().runFrontend(options: CompilerOptions(
            moduleName: "ReifiedCallableReference", inputs: paths, outputPath: "/tmp/reified-callable-reference", emit: .kirDump,
            target: defaultTargetTriple(), stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: !fromSource
        ), inMemorySources: Dictionary(uniqueKeysWithValues: zip(paths, sources.map { Data($0.utf8) }))).context
    }
}

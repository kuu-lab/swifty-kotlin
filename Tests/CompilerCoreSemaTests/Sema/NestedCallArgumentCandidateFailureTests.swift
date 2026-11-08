#if canImport(Testing)
@testable import CompilerCore
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite
struct NestedCallArgumentCandidateFailureTests {
    @Test(arguments: [true, false])
    func inapplicableBoundedFactoryOverloadDoesNotDiscardMatchingCandidate(stringFirst: Bool) throws {
        let stringOverload = "fun choose(value: String): String = value"
        let intOverload = "fun choose(value: Int): String = \"int\""
        let overloads = stringFirst
            ? "\(stringOverload)\n\(intOverload)"
            : "\(intOverload)\n\(stringOverload)"
        let context = makeContext("""
        fun <T : String> value(): T = "x" as T
        \(overloads)
        fun main() { val actual: String = choose(value()); println(actual) }
        """)

        try runSema(context)

        #expect(!context.diagnostics.hasError, "Unexpected diagnostics: \(context.diagnostics.diagnostics)")
        try expectStringChooseAndFactoryBindings(in: context)
    }

    @Test
    func successfulCandidateKeepsMultipleNestedArgumentBindingsAfterOtherCandidateFails() throws {
        let context = makeContext("""
        fun <T : String> first(): T = "x" as T
        fun <T : String> second(): T = "y" as T
        fun choose(first: String, second: String): String = first + second
        fun choose(first: Int, second: Int): String = "int"
        fun main() { val actual: String = choose(first(), second()); println(actual) }
        """)

        try runSema(context)

        #expect(!context.diagnostics.hasError, "Unexpected diagnostics: \(context.diagnostics.diagnostics)")
        let sema = try #require(context.sema)
        let ast = try #require(context.ast)
        let chooseCall = try #require(nameRefCallExprID(named: "choose", in: ast, interner: context.interner))
        let chosen = try #require(sema.bindings.callBinding(for: chooseCall)?.chosenCallee)
        #expect(sema.symbols.functionSignature(for: chosen)?.parameterTypes == [sema.types.stringType, sema.types.stringType])
        for factoryName in ["first", "second"] {
            let factoryCall = try #require(nameRefCallExprID(named: factoryName, in: ast, interner: context.interner))
            #expect(sema.bindings.exprType(for: factoryCall) == sema.types.stringType)
            #expect(sema.bindings.callBinding(for: factoryCall)?.substitutedTypeArguments == [sema.types.stringType])
        }
    }

    @Test(arguments: [true, false])
    func memberOverloadRetainsMatchingCandidate(stringFirst: Bool) throws {
        let stringOverload = "fun choose(value: String): String = value"
        let intOverload = "fun choose(value: Int): String = \"int\""
        let overloads = stringFirst
            ? "\(stringOverload)\n            \(intOverload)"
            : "\(intOverload)\n            \(stringOverload)"
        let context = makeContext("""
        fun <T : String> value(): T = "x" as T
        class Receiver {
            \(overloads)
        }
        fun main() { val actual: String = Receiver().choose(value()); println(actual) }
        """)

        try runSema(context)

        #expect(!context.diagnostics.hasError, "Unexpected diagnostics: \(context.diagnostics.diagnostics)")
        try expectStringMemberChooseAndFactoryBindings(in: context)
    }

    @Test(arguments: [true, false])
    func extensionOverloadRetainsMatchingCandidate(stringFirst: Bool) throws {
        let stringOverload = "fun Receiver.choose(value: String): String = value"
        let intOverload = "fun Receiver.choose(value: Int): String = \"int\""
        let overloads = stringFirst
            ? "\(stringOverload)\n\(intOverload)"
            : "\(intOverload)\n\(stringOverload)"
        let context = makeContext("""
        fun <T : String> value(): T = "x" as T
        class Receiver
        \(overloads)
        fun main() { val actual: String = Receiver().choose(value()); println(actual) }
        """)

        try runSema(context)

        #expect(!context.diagnostics.hasError, "Unexpected diagnostics: \(context.diagnostics.diagnostics)")
        try expectStringMemberChooseAndFactoryBindings(in: context)
    }

    @Test
    func structuralFunctionTypeExtensionRetainsMatchingCandidate() throws {
        let context = makeContext("""
        fun <T : String> value(): T = "x" as T
        fun ((String) -> Unit).withLabel(label: String): String = label
        fun ((Int) -> Unit).withLabel(label: Int): String = "int"
        fun main() {
            val receiver: (String) -> Unit = {}
            println(receiver.withLabel(value()))
        }
        """)

        try runSema(context)

        #expect(!context.diagnostics.hasError, "Unexpected diagnostics: \(context.diagnostics.diagnostics)")
        let sema = try #require(context.sema)
        let ast = try #require(context.ast)
        let call = try #require(firstMemberCall(named: "withLabel", in: ast, interner: context.interner))
        let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
        #expect(sema.symbols.functionSignature(for: chosen)?.parameterTypes == [sema.types.stringType])
        let receiverType = try #require(sema.symbols.functionSignature(for: chosen)?.receiverType)
        guard case .functionType = sema.types.kind(of: receiverType) else {
            Issue.record("Expected the selected extension receiver to retain its structural function type")
            return
        }
        let factoryCall = try #require(nameRefCallExprID(named: "value", in: ast, interner: context.interner))
        #expect(sema.bindings.exprType(for: factoryCall) == sema.types.stringType)
        #expect(sema.bindings.callBinding(for: factoryCall)?.substitutedTypeArguments == [sema.types.stringType])
    }

    @Test
    func namedGenericConstructorArgumentFallsThroughToApplicableExtension() throws {
        // KUU-4188: `invokeOnCompletion(handler = ResumeAwaitOnCompletion(cont))`
        // — the members agree on a function-type parameter while the internal
        // `JobNode` extension is the real target. The nested generic
        // constructor must not keep the members' function-type expectation:
        // its failed contextual pass used to leak KSWIFTK-TYPE-0001 even
        // though the extension fallback resolved the call.
        let context = makeContext("""
        interface DisposableHandle { fun dispose() }
        open class JobNode { open operator fun invoke(cause: Throwable?) {} }
        interface Job {
            fun invokeOnCompletion(handler: (Throwable?) -> Unit): DisposableHandle
            fun invokeOnCompletion(onCancelling: Boolean, invokeImmediately: Boolean, handler: (Throwable?) -> Unit): DisposableHandle
        }
        internal fun Job.invokeOnCompletion(
            invokeImmediately: Boolean = true,
            handler: JobNode,
        ): DisposableHandle = object : DisposableHandle { override fun dispose() {} }
        class AwaitContinuation<T>
        private class ResumeAwaitOnCompletion<T>(val continuation: AwaitContinuation<T>) : JobNode()
        class JobSupport : Job {
            override fun invokeOnCompletion(handler: (Throwable?) -> Unit): DisposableHandle =
                object : DisposableHandle { override fun dispose() {} }
            override fun invokeOnCompletion(onCancelling: Boolean, invokeImmediately: Boolean, handler: (Throwable?) -> Unit): DisposableHandle =
                object : DisposableHandle { override fun dispose() {} }
            fun <T> awaitSuspend(cont: AwaitContinuation<T>) {
                invokeOnCompletion(handler = ResumeAwaitOnCompletion(cont))
            }
        }
        fun main() {}
        """)

        try runSema(context)

        #expect(!context.diagnostics.hasError, "Unexpected diagnostics: \(context.diagnostics.diagnostics)")
    }

    @Test
    func inapplicableMemberAllowsApplicableExtensionFallback() throws {
        let context = makeContext("""
        fun <T : String> value(): T = "x" as T
        class Receiver {
            fun choose(value: Int): String = "member"
        }
        fun Receiver.choose(value: String): String = value
        fun main() { val actual: String = Receiver().choose(value()); println(actual) }
        """)

        try runSema(context)

        #expect(!context.diagnostics.hasError, "Unexpected diagnostics: \(context.diagnostics.diagnostics)")
        let sema = try #require(context.sema)
        let ast = try #require(context.ast)
        let chooseCall = try #require(firstMemberCall(named: "choose", in: ast, interner: context.interner))
        let chosen = try #require(sema.bindings.callBinding(for: chooseCall)?.chosenCallee)
        #expect(sema.symbols.functionSignature(for: chosen)?.parameterTypes == [sema.types.stringType])
        #expect(sema.symbols.functionSignature(for: chosen)?.receiverType != nil)
        let factoryCall = try #require(nameRefCallExprID(named: "value", in: ast, interner: context.interner))
        #expect(sema.bindings.exprType(for: factoryCall) == sema.types.stringType)
    }

    @Test
    func overloadedGenericConstructorRetainsMatchingCandidate() throws {
        let context = makeContext("""
        fun <T : String> value(): T = "x" as T
        class Widget(val value: String) {
            constructor(value: Int) : this("int")
        }
        fun main() { val actual: Widget = Widget(value()); println(actual.value) }
        """)

        try runSema(context)

        #expect(!context.diagnostics.hasError, "Unexpected diagnostics: \(context.diagnostics.diagnostics)")
        let sema = try #require(context.sema)
        let ast = try #require(context.ast)
        let constructorCall = try #require(nameRefCallExprID(named: "Widget", in: ast, interner: context.interner))
        let chosen = try #require(sema.bindings.callBinding(for: constructorCall)?.chosenCallee)
        #expect(sema.symbols.functionSignature(for: chosen)?.parameterTypes == [sema.types.stringType])
        let factoryCall = try #require(nameRefCallExprID(named: "value", in: ast, interner: context.interner))
        #expect(sema.bindings.exprType(for: factoryCall) == sema.types.stringType)
    }

    @Test
    func explicitTypeArgumentAndTypedLocalStillProvideValidContexts() throws {
        let context = makeContext("""
        fun <T : String> value(): T = "x" as T
        fun choose(value: String): String = value
        fun choose(value: Int): String = "int"
        fun main() {
            choose(value<String>())
            val local: String = value()
            choose(local)
        }
        """)

        try runSema(context)

        #expect(!context.diagnostics.hasError, "Unexpected diagnostics: \(context.diagnostics.diagnostics)")
    }

    @Test
    func unboundedFactoryKeepsGenuineOverloadAmbiguity() throws {
        let context = makeContext("""
        fun <T> value(): T = "x" as T
        fun choose(value: String): String = value
        fun choose(value: Int): String = "int"
        fun main() { choose(value()) }
        """)

        try runSema(context)

        #expect(context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0003" })
    }

    @Test
    func unresolvedMemberCallArgumentsDoNotCascadeAmbiguity() throws {
        let context = makeContext("""
        fun main() {
            println(arrayOf("a").missingMember())
            println(Throwable().missingProperty.joinToString("\\n"))
        }
        """)

        try runSema(context)

        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.map(\.code) == ["KSWIFTK-SEMA-0024", "KSWIFTK-SEMA-0024"],
            "Expected only root unresolved-member diagnostics, got: \(errors)"
        )
    }

    @Test
    func unresolvedMemberArgumentSelectsBroadFallbackOverload() throws {
        let context = makeContext("""
        class Receiver
        fun main() { println(Receiver().missing()) }
        """)

        try runSema(context)

        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.map(\.code) == ["KSWIFTK-SEMA-0024"],
            "Expected only the root unresolved-member diagnostic, got: \(errors)"
        )
        let sema = try #require(context.sema)
        let ast = try #require(context.ast)
        let printlnCall = try #require(nameRefCallExprID(named: "println", in: ast, interner: context.interner))
        let chosen = try #require(sema.bindings.callBinding(for: printlnCall)?.chosenCallee)
        #expect(sema.symbols.functionSignature(for: chosen)?.parameterTypes == [sema.types.nullableAnyType])
    }

    @Test
    func boundedFactoryWithoutExpectedTypeStillCannotInferResult() throws {
        let context = makeContext("""
        fun <T : String> value(): T = "x" as T
        fun main() { val actual = value() }
        """)

        try runSema(context)

        #expect(context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-INFER" })
    }

    @Test
    func allInapplicableCandidatesAreStillRejected() throws {
        let context = makeContext("""
        fun <T : String> value(): T = "x" as T
        fun choose(value: Int): String = "int"
        fun main() { choose(value()) }
        """)

        try runSema(context)

        #expect(context.diagnostics.hasError)
        let sema = try #require(context.sema)
        let ast = try #require(context.ast)
        let chooseCall = try #require(nameRefCallExprID(named: "choose", in: ast, interner: context.interner))
        // Rejection is carried by the diagnostic; error recovery still records
        // the lone inapplicable candidate as a best-effort binding.
        let chosen = try #require(sema.bindings.callBinding(for: chooseCall)?.chosenCallee)
        #expect(sema.symbols.symbol(chosen)?.fqName.map(context.interner.resolve) == ["choose"])
    }

    @Test
    func applicableExplicitImportStillPrecedesInapplicableSamePackageOverload() throws {
        TestStdlibCache.shared.prepare()
        let stdlib = try #require(CompilerOptions.defaultStdlibLibraryPath)
        let imported = """
        package imported
        fun choose(value: String): String = "imported"
        """
        let usage = """
        package app
        import imported.choose
        fun <T : String> value(): T = "x" as T
        fun choose(value: Int): String = "local"
        fun main() { println(choose(value())) }
        """
        try withTemporaryFiles(contents: [imported, usage]) { paths in
            let context = makeCompilationContext(
                inputs: paths,
                stdlibLibraryPath: stdlib,
                allowDefaultStdlibLibrary: false
            )
            try runSema(context)

            #expect(!context.diagnostics.hasError, "Unexpected diagnostics: \(context.diagnostics.diagnostics)")
            let sema = try #require(context.sema)
            let ast = try #require(context.ast)
            let chooseCall = try #require(nameRefCallExprID(named: "choose", in: ast, interner: context.interner))
            let chosen = try #require(sema.bindings.callBinding(for: chooseCall)?.chosenCallee)
            #expect(sema.symbols.symbol(chosen)?.fqName.map(context.interner.resolve) == ["imported", "choose"])
            let factoryCall = try #require(nameRefCallExprID(named: "value", in: ast, interner: context.interner))
            #expect(sema.bindings.exprType(for: factoryCall) == sema.types.stringType)
        }
    }

    @Test
    func streamCollectInfersReturnOnlyCollectorTypeParameter() throws {
        // `Collectors.counting`/`toSet` take no arguments and their `T`
        // occurs only in the return type. `Stream<T>.collect`'s own function
        // type parameters `A`/`R` are bound by the outer call from the nested
        // call's result, so the candidate expected type erases them to `*`
        // while the concrete `Collector` head still pins `T` (KUU-4066).
        let context = makeContext("""
        import java.util.stream.*
        fun main() {
            val count: Long = Stream.of("a", "b", "c").collect(Collectors.counting())
            val set: Set<String> = Stream.of("a", "a", "b").collect(Collectors.toSet())
            println(count)
            println(set.size)
        }
        """)

        try runSema(context)

        #expect(!context.diagnostics.hasError, "Unexpected diagnostics: \(context.diagnostics.diagnostics)")
        let sema = try #require(context.sema)
        let ast = try #require(context.ast)
        for factoryName in ["counting", "toSet"] {
            let factoryCall = try #require(
                firstMemberCall(named: factoryName, in: ast, interner: context.interner)
            )
            #expect(
                sema.bindings.callBinding(for: factoryCall)?.substitutedTypeArguments == [sema.types.stringType],
                "Expected \(factoryName)'s T to bind to String"
            )
        }
    }

    @Test
    func collectionsMaxPropagatesComparatorElementIntoInlineCompareBy() throws {
        // `Collections.max`/`min` declare `Comparator<in T>`, so the sibling
        // collection argument pins the inline `compareBy` selector's element
        // type. Without that expected type the selector's `T` is only used in
        // input positions and collapses to `Any`, materializing
        // `Comparator<Any>` — a valid substitution that traps at runtime
        // (KUU-4048).
        let context = makeContext("""
        import java.util.Collections
        fun main() {
            println(Collections.max(listOf(1, 2), compareBy { -it }))
            println(Collections.min(listOf(1, 2), compareBy { -it }))
        }
        """)

        try runSema(context)

        #expect(!context.diagnostics.hasError, "Unexpected diagnostics: \(context.diagnostics.diagnostics)")
        let sema = try #require(context.sema)
        let ast = try #require(context.ast)
        let comparatorSymbol = try #require(
            sema.symbols.lookup(fqName: [
                context.interner.intern("kotlin"),
                context.interner.intern("Comparator"),
            ])
        )
        var compareByCallIDs: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .call(calleeExprID, _, _, _) = expr,
                  let calleeExpr = ast.arena.expr(calleeExprID),
                  case let .nameRef(calleeName, _) = calleeExpr,
                  context.interner.resolve(calleeName) == "compareBy"
            else {
                continue
            }
            compareByCallIDs.append(exprID)
        }
        #expect(compareByCallIDs.count == 2)
        for callExprID in compareByCallIDs {
            let resultType = try #require(sema.bindings.exprType(for: callExprID))
            guard case let .classType(comparatorType) = sema.types.kind(of: resultType),
                  comparatorType.classSymbol == comparatorSymbol,
                  case let .invariant(elementType) = comparatorType.args.first
            else {
                Issue.record("Expected compareBy to produce Comparator, got \(sema.types.renderType(resultType))")
                continue
            }
            #expect(
                elementType == sema.types.intType,
                "Expected compareBy's element to bind to Int, got \(sema.types.renderType(resultType))"
            )
            #expect(sema.bindings.callBinding(for: callExprID)?.substitutedTypeArguments == [sema.types.intType])
        }
    }

    private func makeContext(_ source: String) -> CompilationContext {
        TestStdlibCache.shared.prepare()
        return makeContextFromSource(source, allowDefaultStdlibLibrary: true)
    }

    private func expectStringChooseAndFactoryBindings(in context: CompilationContext) throws {
        let sema = try #require(context.sema)
        let ast = try #require(context.ast)
        let chooseCall = try #require(nameRefCallExprID(named: "choose", in: ast, interner: context.interner))
        let chosen = try #require(sema.bindings.callBinding(for: chooseCall)?.chosenCallee)
        #expect(sema.symbols.functionSignature(for: chosen)?.parameterTypes == [sema.types.stringType])
        let factoryCall = try #require(nameRefCallExprID(named: "value", in: ast, interner: context.interner))
        #expect(sema.bindings.exprType(for: factoryCall) == sema.types.stringType)
        #expect(sema.bindings.callBinding(for: factoryCall)?.substitutedTypeArguments == [sema.types.stringType])
    }

    private func expectStringMemberChooseAndFactoryBindings(in context: CompilationContext) throws {
        let sema = try #require(context.sema)
        let ast = try #require(context.ast)
        let chooseCall = try #require(firstMemberCall(named: "choose", in: ast, interner: context.interner))
        let chosen = try #require(sema.bindings.callBinding(for: chooseCall)?.chosenCallee)
        #expect(sema.symbols.functionSignature(for: chosen)?.parameterTypes == [sema.types.stringType])
        let factoryCall = try #require(nameRefCallExprID(named: "value", in: ast, interner: context.interner))
        #expect(sema.bindings.exprType(for: factoryCall) == sema.types.stringType)
        #expect(sema.bindings.callBinding(for: factoryCall)?.substitutedTypeArguments == [sema.types.stringType])
    }

    private func firstMemberCall(
        named name: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> ExprID? {
        firstExprID(in: ast) { _, expr in
            switch expr {
            case let .memberCall(_, calleeName, _, _, _), let .safeMemberCall(_, calleeName, _, _, _):
                return interner.resolve(calleeName) == name
            default:
                return false
            }
        }
    }
}
#endif

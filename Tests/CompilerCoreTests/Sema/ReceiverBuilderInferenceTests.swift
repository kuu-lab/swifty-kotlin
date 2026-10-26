#if canImport(Testing)
@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite
struct ReceiverBuilderInferenceTests {
    private let builder = """
    class Builder<T> {
        fun use(block: () -> T) {}
    }
    fun <R> build(builder: Builder<R>.() -> Unit): R = null as R
    """

    private let nonUnitBuilder = """
    class Buildee<T> { fun materialize(): T = null as T }
    class UserKlass
    fun <T> build(block: Buildee<T>.() -> UserKlass): Buildee<T> = null as Buildee<T>
    """

    @Test func callbackResultInfersBuilderType() throws {
        try expectIntResult(builder + """

        fun main() {
            val result = build { use { 1 } }
            println(result)
        }
        """)
    }

    @Test func boundCallableReferenceArgumentInfersBuilderType() throws {
        let source = """
        interface Scope<T> { fun emit(value: T) }
        @kotlin.BuilderInference
        fun <T> build(block: Scope<T>.() -> Unit) {}
        fun consumeString(action: (String) -> Unit) {}
        fun fromBoundReference() { build { consumeString(this::emit) } }
        fun fromLambda() { build { consumeString { emit(it) } } }
        fun withExplicitType() { build<String> { consumeString(this::emit) } }
        fun fromDirectInput() { build { emit("OK") } }
        class StringScope : Scope<String> { override fun emit(value: String) {} }
        fun fromConcreteReceiver(scope: StringScope) { consumeString(scope::emit) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let buildCalls = allExprIDs(in: ast, path: path, ctx: ctx) { exprID, expr in
                guard case let .call(calleeID, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(calleeID)
                else { return false }
                return ctx.interner.resolve(name) == "build"
                    && sema.bindings.callBinding(for: exprID) != nil
            }
            #expect(buildCalls.count == 4)
            #expect(buildCalls.allSatisfy {
                sema.bindings.callBinding(for: $0)?.substitutedTypeArguments == [sema.types.stringType]
            })
        }
    }

    @Test func boundCallableReferenceRejectsExplicitBuilderTypeMismatch() throws {
        let source = """
        interface Scope<T> { fun emit(value: T) }
        @kotlin.BuilderInference
        fun <T> build(block: Scope<T>.() -> Unit) {}
        fun consumeSuspendInt(action: suspend (Int) -> Unit) {}
        fun rejectsMismatch() { build<String> { consumeSuspendInt(this::emit) } }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    @Test func boundCallableReferenceInferenceStillRejectsNoEvidence() throws {
        let source = """
        interface Scope<T> { fun emit(value: T) }
        @kotlin.BuilderInference
        fun <T> build(block: Scope<T>.() -> Unit) {}
        fun rejectsNoEvidence() { build {} }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-INFER", in: ctx)
        }
    }

    @Test func nonUnitReceiverLambdaBodyReturnInfersBuilderType() throws {
        let source = nonUnitBuilder + """

        fun main() {
            val result = build { materialize() }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let calls = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(calleeID, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(calleeID)
                else { return false }
                return ctx.interner.resolve(name) == "build"
            }
            #expect(calls.count == 1)
            let call = try #require(calls.first)
            let userKlass = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("UserKlass")]))
            let expectedType = sema.types.make(.classType(ClassType(
                classSymbol: userKlass, args: [], nullability: .nonNull
            )))
            let binding = try #require(sema.bindings.callBinding(for: call))
            #expect(binding.substitutedTypeArguments == [expectedType])
        }
    }

    @Test func nonUnitReceiverLambdaKeepsExplicitAndExpectedTypes() throws {
        let source = nonUnitBuilder + """

        fun main() {
            val explicit = build<UserKlass> { materialize() }
            val expected: Buildee<UserKlass> = build { materialize() }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func nonUnitReceiverLambdaRejectsIncompatibleReturnType() throws {
        let source = nonUnitBuilder + """

        fun main() {
            val incompatible: Buildee<String> = build { materialize() }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }

    @Test func multipleCallbacksAndNestedCallsInferBuilderType() throws {
        try expectIntResult(builder + """

        fun <T> identity(value: T): T = value
        fun main() {
            val result = build {
                use { identity(1) }
                use { 2 }
            }
            println(result + 1)
        }
        """)
    }

    @Test func nestedGenericReceiverCallDoesNotChangeBuilderInference() throws {
        let source = """
        class Buildee<T> {
            var r: T? = null
            fun yield(arg: T) { r = arg }
        }
        fun <T> build(instructions: Buildee<T>.() -> Unit): Buildee<T> =
            Buildee<T>().apply(instructions)
        class Logger { fun error() { throw RuntimeException("") } }
        fun <T> logger(arg: T): Logger = Logger()
        fun main() {
            val b = build {
                if ("".hashCode() == 0) {
                    yield("OK")
                } else {
                    logger(this).error()
                }
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            TestStdlibCache.shared.prepare()
            let ctx = makeCompilationContext(inputs: [path], allowDefaultStdlibLibrary: true)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            let kir = try #require(ctx.kir)
            let kirDump = kir.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
            let sequenceBuilderYields = kirDump.split(separator: "\n").filter {
                $0.contains("__kk_sequence_builder_yield")
            }
            #expect(
                sequenceBuilderYields.isEmpty,
                "Builder class yield was lowered as a sequence yield: \(sequenceBuilderYields.joined(separator: "\n"))"
            )
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let loggerCalls = allExprIDs(in: ast, path: path, ctx: ctx) { exprID, expr in
                guard case let .call(calleeID, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(calleeID)
                else { return false }
                return ctx.interner.resolve(name) == "logger"
                    && sema.bindings.callBinding(for: exprID) != nil
            }
            #expect(loggerCalls.count == 1)
            let loggerCall = try #require(loggerCalls.first)
            let loggerBinding = try #require(sema.bindings.callBinding(for: loggerCall))
            #expect(loggerBinding.substitutedTypeArguments.count == 1)
            let loggerArgument = try #require(loggerBinding.substitutedTypeArguments.first)
            guard case let .classType(builderType) = sema.types.kind(of: loggerArgument),
                  let buildee = sema.symbols.symbol(builderType.classSymbol)
            else {
                #expect(Bool(false), "Expected logger to receive the inferred Buildee receiver")
                return
            }
            #expect(ctx.interner.resolve(buildee.name) == "Buildee")
            let yieldCalls = allExprIDs(in: ast, path: path, ctx: ctx) { exprID, expr in
                guard case let .call(calleeID, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(calleeID)
                else { return false }
                return ctx.interner.resolve(name) == "yield"
                    && sema.bindings.callBinding(for: exprID) != nil
            }
            #expect(yieldCalls.count == 1)
            let yieldCall = try #require(yieldCalls.first)
            let yieldBinding = try #require(sema.bindings.callBinding(for: yieldCall))
            let yieldSymbol = try #require(sema.symbols.symbol(yieldBinding.chosenCallee))
            #expect(yieldSymbol.fqName == [
                ctx.interner.intern("Buildee"),
                ctx.interner.intern("yield"),
            ])
            let yieldedType = try #require(yieldBinding.substitutedTypeArguments.first)
            #expect(builderType.args == [.invariant(yieldedType)])
        }
    }

    @Test func extensionPropertyReceiverInfersBuilderType() throws {
        try expectBuilderTypeArgument("""
        class Buildee<T>
        fun <FT> build(instructions: Buildee<FT>.() -> Unit): Buildee<FT> = null as Buildee<FT>
        class UserKlass
        val Buildee<UserKlass>.typeInfoSourcingValue: UserKlass get() = UserKlass()
        var Buildee<UserKlass>.typeInfoSourcingVariable: UserKlass
            get() = UserKlass()
            set(value) {}
        fun box() {
            build { this.typeInfoSourcingValue }
            build { this.typeInfoSourcingVariable }
        }
        """, callCount: 2)
    }

    @Test func extensionFunctionReceiverInfersBuilderType() throws {
        try expectBuilderTypeArgument("""
        class Buildee<T>
        fun <FT> build(instructions: Buildee<FT>.() -> Unit): Buildee<FT> = null as Buildee<FT>
        class UserKlass
        fun Buildee<UserKlass>.sourceFunction(): Unit {}
        fun box() {
            build { this.sourceFunction() }
        }
        """)
    }

    @Test func implicitExtensionPropertyReceiverInfersBuilderType() throws {
        try expectBuilderTypeArgument("""
        class Buildee<T>
        fun <FT> build(instructions: Buildee<FT>.() -> Unit): Buildee<FT> = null as Buildee<FT>
        class UserKlass
        val Buildee<UserKlass>.typeInfo: UserKlass get() = UserKlass()
        fun box() { build { typeInfo } }
        """)
    }

    @Test func nestedDslReceiverScopeInfersBuilderFromInnerProperty() throws {
        try expectBuilderTypeArgument("""
        class Scope
        class Buildee<T>
        fun <FT> build(instructions: Buildee<FT>.() -> Unit): Buildee<FT> = null as Buildee<FT>
        class UserKlass
        val Buildee<UserKlass>.typeInfo: UserKlass get() = UserKlass()
        fun inScope(block: Scope.() -> Unit) { Scope().block() }
        fun box() { inScope { build { typeInfo } } }
        """, ignoreUnboundCallNodes: true)
    }

    @Test func extensionPropertyReceiverPreservesInferenceControls() throws {
        try expectBuilderTypeArgument("""
        class Buildee<T>
        fun <FT> build(instructions: Buildee<FT>.() -> Unit): Buildee<FT> = null as Buildee<FT>
        class UserKlass
        val Buildee<UserKlass>.typeInfo: UserKlass get() = UserKlass()
        fun box() {
            build<UserKlass> { this.typeInfo }
            val expected: Buildee<UserKlass> = build { this.typeInfo }
            Buildee<UserKlass>().typeInfo
        }
        """, callCount: 2)
    }

    @Test func extensionPropertyReceiverRejectsConflictingExpectedBuilderType() throws {
        try withTemporaryFile(contents: """
        class Buildee<T>
        fun <FT> build(instructions: Buildee<FT>.() -> Unit): Buildee<FT> = null as Buildee<FT>
        class UserKlass
        val Buildee<UserKlass>.typeInfo: Unit get() = Unit
        fun box() { val wrong: Buildee<Int> = build { this.typeInfo } }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }

    @Test func competingExtensionPropertyReceiversDoNotChooseAnArbitraryBuilderType() throws {
        try withTemporaryFile(contents: """
        class Buildee<T>
        fun <FT> build(instructions: Buildee<FT>.() -> Unit): Buildee<FT> = null as Buildee<FT>
        val Buildee<Int>.typeInfo: Unit get() = Unit
        val Buildee<String>.typeInfo: Unit get() = Unit
        fun box() { build { this.typeInfo } }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }

    @Test func memberExtensionCallbackInfersBuilderType() throws {
        try expectIntResult("""
        class Clause<T>
        class Choice<R> {
            fun <T> Clause<T>.onResult(block: (T) -> R) {}
        }
        fun <R> choose(builder: Choice<R>.() -> Unit): R = null as R
        fun main() {
            val clause = Clause<Int>()
            val result = choose { clause.onResult { it + 1 } }
            println(result)
        }
        """, callee: "choose")
    }

    @Test func localClassInitializerInfersOuterReceiverBuilderType() throws {
        try expectBuilderResultType("""
        class Buildee<T> {
            fun materialize(): T = null as T
        }
        fun <T> build(instructions: Buildee<T>.() -> Unit): Buildee<T> = null as Buildee<T>
        class UserKlass
        fun consume(arg: UserKlass) {}
        fun main() {
            val result = build {
                class LocalClass {
                    init { consume(materialize()) }
                }
            }
        }
        """, expectedArgumentName: "UserKlass")
    }

    @Test func localClassPropertyInitializerInfersOuterReceiverBuilderType() throws {
        try expectBuilderResultType("""
        class Buildee<T> { fun materialize(): T = null as T }
        fun <T> build(instructions: Buildee<T>.() -> Unit): Buildee<T> = null as Buildee<T>
        class UserKlass
        fun main() {
            build {
                class LocalClass { val value: UserKlass = materialize() }
            }
        }
        """, expectedArgumentName: "UserKlass")
    }

    @Test func localClassMemberBodyInfersOuterReceiverBuilderType() throws {
        try expectBuilderResultType("""
        class Buildee<T> { fun materialize(): T = null as T }
        fun <T> build(instructions: Buildee<T>.() -> Unit): Buildee<T> = null as Buildee<T>
        class UserKlass
        fun main() {
            build {
                class LocalClass { fun create(): UserKlass = materialize() }
            }
        }
        """, expectedArgumentName: "UserKlass")
    }

    @Test func localClassInitializerAcceptsExplicitBuilderType() throws {
        try expectBuilderResultType("""
        class Buildee<T> { fun materialize(): T = null as T }
        fun <T> build(instructions: Buildee<T>.() -> Unit): Buildee<T> = null as Buildee<T>
        class UserKlass
        fun consume(arg: UserKlass) {}
        fun main() {
            build<UserKlass> {
                class LocalClass { init { consume(materialize()) } }
            }
        }
        """, expectedArgumentName: "UserKlass")
    }

    @Test func localClassMemberShadowsOuterBuilderMember() throws {
        let source = """
        class Buildee<T> { fun materialize(): T = null as T }
        fun <T> build(instructions: Buildee<T>.() -> Unit): Buildee<T> = null as Buildee<T>
        class UserKlass
        fun consume(arg: UserKlass) {}
        fun main() {
            build {
                class LocalClass {
                    fun materialize(): UserKlass = null as UserKlass
                    init { consume(materialize()) }
                }
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], includeStdlib: false, allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-INFER", in: ctx)
        }
    }

    @Test func localClassInnerReceiverShadowsOuterBuilderReceiver() throws {
        let source = """
        class Buildee<T> { fun materialize(): T = null as T }
        fun <T> build(instructions: Buildee<T>.() -> Unit): Buildee<T> = null as Buildee<T>
        class UserKlass
        class OtherReceiver { fun materialize(): UserKlass = null as UserKlass }
        fun consume(arg: UserKlass) {}
        fun enter(receiver: OtherReceiver, block: OtherReceiver.() -> Unit) {}
        fun main() {
            build {
                enter(OtherReceiver()) {
                    class LocalClass { init { consume(materialize()) } }
                }
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], includeStdlib: false, allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-INFER", in: ctx)
        }
    }

    @Test func localClassInitializerRejectsIncompatibleBuilderReceiverType() throws {
        let source = """
        class Buildee<T> { fun materialize(): T = null as T }
        fun <T> build(instructions: Buildee<T>.() -> Unit): Buildee<T> = null as Buildee<T>
        class UserKlass
        class WrongKlass
        fun consume(arg: UserKlass) {}
        fun main() {
            build<WrongKlass> {
                class LocalClass { init { consume(materialize()) } }
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], includeStdlib: false, allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }

    @Test func expectedTypeAndExplicitArgumentsRemainSupported() throws {
        try expectIntResult(builder + """

        fun main() {
            val expected: Int = build { use { 1 } }
            val explicit = build<Int> { use { 2 } }
            println(expected + explicit)
        }
        """, callCount: 2)
    }

    @Test func inheritedMemberExtensionUsesDispatchTypeArguments() throws {
        try expectIntResult("""
        class Clause<T>
        open class Choice<R> {
            fun <T> Clause<T>.onResult(block: (T) -> R) {}
        }
        class DerivedChoice<R> : Choice<R>()
        fun <R> choose(builder: DerivedChoice<R>.() -> Unit): R = null as R
        fun main() {
            val clause = Clause<Int>()
            val inferred = choose { clause.onResult { it + 1 } }
            val expected: Int = choose { clause.onResult { it + 2 } }
            val explicit = choose<Int> { clause.onResult { it + 3 } }
            println(inferred + expected + explicit)
        }
        """, callee: "choose", callCount: 3)
    }

    @Test func boundedBuilderRejectsIncompatibleCallback() throws {
        let source = """
        class Builder<T> { fun use(block: () -> T) {} }
        fun <R : Number> build(builder: Builder<R>.() -> Unit): R = null as R
        fun main() { val result = build { use { "wrong" } } }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func expectedTypeRejectsIncompatibleCallback() throws {
        let ctx = makeContextFromSource(builder + """

        fun main() { val result: Int = build { use { "wrong" } } }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test(arguments: ["", "println(1)", "val unused = 1"])
    func builderWithoutTypeEvidenceReportsUninferredType(body: String) throws {
        let ctx = makeContextFromSource(builder + """

        fun main() { val result = build { \(body) } }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-INFER", in: ctx)
    }

    @Test func emptyBuilderUsesExpectedExplicitAndArgumentTypes() throws {
        try expectIntResult(builder + """

        fun main() {
            val expected: Int = build {}
            val explicit = build<Int> {}
            println(expected + explicit)
        }
        """, callCount: 2)
        try expectIntResult("""
        class Builder<T>
        fun <R> build(seed: R, builder: Builder<R>.() -> Unit): R = seed
        fun main() { val result = build(1) {} }
        """)
    }

    @Test func partiallyInferredEmptyBuilderReportsMissingType() throws {
        let ctx = makeContextFromSource("""
        class Builder<T>
        fun <R, S> build(seed: S, builder: Builder<R>.() -> Unit): R = null as R
        fun main() { val result = build(1) {} }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-INFER", in: ctx)
    }

    private func expectIntResult(_ source: String, callee: String = "build", callCount: Int = 1) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let calls = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(calleeID, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(calleeID)
                else { return false }
                return ctx.interner.resolve(name) == callee
            }
            #expect(calls.count == callCount)
            #expect(calls.allSatisfy { sema.bindings.exprType(for: $0) == sema.types.intType })
        }
    }

    private func expectBuilderTypeArgument(
        _ source: String,
        callCount: Int = 1,
        ignoreUnboundCallNodes: Bool = false
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let userClass = try #require(
                sema.symbols.lookupByShortName(ctx.interner.intern("UserKlass")).first
            )
            let userType = sema.types.make(.classType(ClassType(
                classSymbol: userClass,
                args: [],
                nullability: .nonNull
            )))
            let calls = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(calleeID, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(calleeID)
                else { return false }
                return ctx.interner.resolve(name) == "build"
            }
            let resolvedCalls = ignoreUnboundCallNodes
                ? calls.filter { sema.bindings.callBinding(for: $0) != nil }
                : calls
            #expect(resolvedCalls.count == callCount)
            for call in resolvedCalls {
                let binding = try #require(sema.bindings.callBinding(for: call))
                #expect(binding.substitutedTypeArguments == [userType])
            }
        }
    }

    private func expectBuilderResultType(_ source: String, expectedArgumentName: String) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], includeStdlib: false, allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let buildCalls = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(calleeID, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(calleeID)
                else { return false }
                return ctx.interner.resolve(name) == "build"
            }
            #expect(buildCalls.count == 1)
            let buildCall = try #require(buildCalls.first)
            let resultType = try #require(sema.bindings.exprType(for: buildCall))
            guard case let .classType(builderType) = sema.types.kind(of: resultType),
                  let builderSymbol = sema.symbols.symbol(builderType.classSymbol)
            else {
                #expect(Bool(false), "Expected a generic builder result type")
                return
            }
            #expect(ctx.interner.resolve(builderSymbol.name) == "Buildee")
            #expect(builderType.args.count == 1)
            guard let builderArgument = builderType.args.first else { return }
            let inferredType: TypeID = switch builderArgument {
            case let .invariant(type), let .in(type), let .out(type): type
            case .star: .invalid
            }
            guard case let .classType(inferredClassType) = sema.types.kind(of: inferredType),
                  let inferredSymbol = sema.symbols.symbol(inferredClassType.classSymbol)
            else {
                #expect(Bool(false), "Expected a concrete class type argument")
                return
            }
            #expect(ctx.interner.resolve(inferredSymbol.name) == expectedArgumentName)
            #expect(inferredClassType.args.isEmpty)
        }
    }
}
#endif

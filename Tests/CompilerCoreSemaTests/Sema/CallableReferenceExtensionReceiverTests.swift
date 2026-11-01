#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-961: A bare `::name` callable reference must not resolve to an
/// extension function or extension property — kotlinc reports
/// `unresolved reference` for `::ext` where `ext` is `fun Int.ext()`.
/// Extensions are only reachable through `Type::ext`, `obj::ext`, or the
/// implicitly-bound `::ext` form inside a receiver scope. Member
/// functions that are also extensions (`fun Int.ext()` inside a class)
/// are unreferenceable in every `::` form ("member and an extension at
/// the same time" is prohibited).
@Suite
struct CallableReferenceExtensionReceiverTests {

    @Test func testBoundCallableReferenceCanBeGenericExtensionReceiver() throws {
        try withTemporaryFile(contents: """
        class Host { fun t() {} }
        fun <T, R> T.let(block: (T) -> R): R = block(this)
        fun main() { (Host()::t).let { it() } }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "A bound callable reference used as a generic extension receiver must type its lambda parameter: \(errors)"
            )
        }
    }

    // MARK: - Bare `::` must reject extension declarations

    @Test func testBareCallableRefRejectsExtensionFunction() throws {
        let source = """
        fun Int.even(): Boolean = this % 2 == 0

        fun main() {
            val f = ::even
            println(f)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.hasError,
            "Bare `::even` to a package-level extension must be rejected like kotlinc"
        )
    }

    @Test func testBareCallableRefRejectsExtensionProperty() throws {
        let source = """
        val Int.lastDigit: Int get() = this % 10

        fun main() {
            val p = ::lastDigit
            println(p)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.hasError,
            "Bare `::lastDigit` to a package-level extension property must be rejected"
        )
    }

    @Test func testBareCallableRefRejectsExtensionInsideClass() throws {
        let source = """
        fun Int.even(): Boolean = this % 2 == 0

        class Probe {
            fun capture() = ::even
        }

        fun main() { println(Probe().capture()) }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.hasError,
            "Bare `::even` stays rejected inside an unrelated class scope"
        )
    }

    @Test func testBareCallableRefRejectsLocalExtension() throws {
        let source = """
        fun main() {
            fun Int.local(): Int = this * 2
            val f = ::local
            println(f)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.hasError,
            "Bare `::local` to a local extension must be rejected"
        )
    }

    // MARK: - Member-extensions are unreferenceable in every `::` form

    @Test func testMemberExtensionRejectedViaThis() throws {
        let source = """
        class C {
            fun Int.ext(): Int = 1
            fun capture() = this::ext
        }

        fun main() { println(C().capture()) }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "`this::ext` member-extension reference must be rejected")
    }

    @Test func testMemberExtensionRejectedViaType() throws {
        let source = """
        class C {
            fun Int.ext(): Int = 1
            fun capture() = C::ext
        }

        fun main() { println(C().capture()) }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "`C::ext` member-extension reference must be rejected")
    }

    @Test func testMemberExtensionRejectedViaInstance() throws {
        let source = """
        class C {
            fun Int.ext(): Int = 1
        }

        fun capture(c: C) = c::ext

        fun main() { println(capture(C())) }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "`c::ext` member-extension reference must be rejected")
    }

    @Test func testMemberExtensionRejectedBareInsideOwner() throws {
        let source = """
        class C {
            fun Int.ext(): Int = 1
            fun capture() = ::ext
        }

        fun main() { println(C().capture()) }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Bare `::ext` inside the declaring class must be rejected")
    }

    @Test func testMemberExtensionPropertyRejected() throws {
        let source = """
        class C {
            val Int.mp: Int get() = 2
            fun capture() = this::mp
        }

        fun main() { println(C().capture()) }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Member-extension property `this::mp` must be rejected")
    }

    @Test func testImplicitBoundRefRejectsMismatchedExtensionReceiver() throws {
        let source = """
        fun String.tag(): String = "ext:" + this

        fun main() {
            val f = with(4) { ::tag }
            println(f)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.hasError,
            "`::tag` inside `with(4)` must reject a String extension (receiver mismatch)"
        )
    }

    // MARK: - Legal forms must keep working

    @Test func testTypeQualifiedExtensionFunctionReference() throws {
        let source = """
        fun Int.even(): Boolean = this % 2 == 0

        fun main() {
            val f: (Int) -> Boolean = Int::even
            println(f(6))
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "`Int::even` unbound extension reference must type-check, got: \(errors)")
    }

    @Test func testBoundExtensionFunctionReference() throws {
        let source = """
        fun Int.even(): Boolean = this % 2 == 0

        fun main() {
            val f: () -> Boolean = 6::even
            println(f())
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "`6::even` bound extension reference must type-check, got: \(errors)")
    }

    @Test func testExtensionPropertyViaTypeAndInstance() throws {
        let source = """
        val Int.lastDigit: Int get() = this % 10

        fun main() {
            val unbound = Int::lastDigit
            val bound = 37::lastDigit
            println(unbound.get(37))
            println(bound.get())
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Extension property refs via `Int::`/`i::` must type-check, got: \(errors)")
    }

    @Test func testFunctionTypeAndGenericExtensionPropertyReferences() throws {
        let source = """
        val (Int.() -> String).baz: String get() = "a"
        val <T> T.quux: T.() -> String get() = { "l" }
        val a = (Int.() -> String)::baz
        val b = String::quux
        fun useQuux(): (String) -> (String.() -> String) = String::quux
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Function-type and generic extension property references must resolve: \(errors)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let references = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .callableRef(_, _, range) = ast.arena.expr(exprID),
                  ctx.sourceManager.origin(of: range.start.file) == .user
            else {
                return nil
            }
            return exprID
        }
        #expect(references.count == 3)
        var referencedProperties = Set<String>()
        for reference in references {
            guard case let .callableRef(_, member, _) = ast.arena.expr(reference),
                  case let .symbol(target)? = sema.bindings.callableTargets[reference],
                  let targetSymbol = sema.symbols.symbol(target)
            else {
                Issue.record("Each property reference should bind to a property symbol.")
                continue
            }
            let memberName = ctx.interner.resolve(member)
            referencedProperties.insert(memberName)
            #expect(targetSymbol.name == member)
            #expect(sema.bindings.callableRefKind(for: reference) == .propertyRef)
            #expect(sema.bindings.isUnboundCallableRef(reference))
            #expect(sema.bindings.exprType(for: reference) != sema.types.errorType)
        }
        #expect(referencedProperties == Set(["baz", "quux"]))

        let contextualQuuxReference = try #require(references.last { reference in
            guard case let .callableRef(_, member, _) = ast.arena.expr(reference) else { return false }
            return ctx.interner.resolve(member) == "quux"
        })
        guard case let .functionType(functionType) = sema.types.kind(
            of: try #require(sema.bindings.exprType(for: contextualQuuxReference))
        ) else {
            Issue.record("The expected String::quux reference should retain a function type.")
            return
        }
        #expect(functionType.params == [sema.types.stringType])
        guard case let .functionType(propertyValueType) = sema.types.kind(of: functionType.returnType) else {
            Issue.record("The generic property value should specialize to a receiver function type.")
            return
        }
        #expect(propertyValueType.receiver == sema.types.stringType)
        #expect(propertyValueType.returnType == sema.types.stringType)
    }

    @Test func testUnboundGenericExtensionPropertyReferenceSpecializesReceiverType() throws {
        let source = """
        val <T> T.identity: T get() = this
        fun use(): (String) -> String = String::identity
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Generic extension property reference should specialize T from String: \(errors)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let reference = try #require(firstExprID(in: ast) { _, expr in
            if case let .callableRef(_, member, _) = expr {
                return ctx.interner.resolve(member) == "identity"
            }
            return false
        })
        #expect(sema.bindings.callableRefKind(for: reference) == .propertyRef)
        #expect(sema.bindings.isUnboundCallableRef(reference))

        let referenceType = try #require(sema.bindings.exprType(for: reference))
        guard case let .functionType(functionType) = sema.types.kind(of: referenceType) else {
            Issue.record("Expected the generic property reference to have a function type.")
            return
        }
        #expect(functionType.params == [sema.types.stringType])
        #expect(functionType.returnType == sema.types.stringType)
    }

    @Test func testUnboundGenericExtensionPropertyReferenceRetainsReifiedTypeArgument() throws {
        let source = """
        inline val <reified T> T.id: T get() = (this as Any) as T
        fun foo(reference: (String) -> String) = reference("OK")
        fun box(): String = foo(String::id)
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "The pinned reified extension-property conformance case should type-check: \(errors)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let reference = try #require(firstExprID(in: ast) { _, expr in
            if case let .callableRef(_, member, _) = expr {
                return ctx.interner.resolve(member) == "id"
            }
            return false
        })
        let binding = try #require(sema.bindings.callableReferenceBinding(for: reference))
        let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
        #expect(signature.reifiedTypeParameterIndices == Set([0]))
        #expect(binding.substitutedTypeArguments.count == 1)
        // #10531 resolves `String` to the builtin string type rather than a
        // `kotlin.String` class type.
        try #require(
            sema.types.isString(binding.substitutedTypeArguments[0]),
            "Expected the reified receiver argument to be kotlin.String."
        )

        let property = try #require(sema.bindings.identifierSymbol(for: reference))
        let module = try #require(ctx.kir)
        let functions = findAllKIRFunctions(in: module)
        let propertyThunkName = "kk_lambda_property_getter_\(property.rawValue)"
        let reifiedThunkPrefix = "kk_reified_ref_thunk_\(reference.rawValue)_"
        #expect(!functions.contains { ctx.interner.resolve($0.name) == propertyThunkName })
        #expect(functions.contains { ctx.interner.resolve($0.name).hasPrefix(reifiedThunkPrefix) })
    }

    @Test func testUnboundGenericExtensionPropertyReferenceRejectsInvalidReceiverBound() throws {
        let source = """
        val <T : Number> T.numeric: T get() = this
        fun use(): (String) -> String = String::numeric
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.hasError,
            "A String receiver must not satisfy a generic extension property's Number bound"
        )
    }

    @Test func testImplicitReceiverBoundExtensionReference() throws {
        let source = """
        fun Int.even(): Boolean = this % 2 == 0

        fun main() {
            // A bare `::ext` inside a receiver scope is a bound reference
            // (`this::ext`): kotlinc types it `() -> Boolean`.
            val f: () -> Boolean = with(4) { ::even }
            println(f())
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "`with(4) { ::even }` must bind the extension to the implicit receiver as `() -> Boolean`, got: \(errors)"
        )
    }

    @Test func testImplicitReceiverExtensionReferencesFromInnerAndOuterClasses() throws {
        let source = """
        class A {
            suspend fun test(): String {
                (::aExtensionFunction).let { it() }
                return "A"
            }

            inner class B {
                suspend fun test(): String {
                    (::aExtensionFunction).let { it() }
                    (::bExtensionFunction).let { it() }
                    return "B"
                }
            }
        }

        suspend fun A.aExtensionFunction() {}
        suspend fun A.B.bExtensionFunction() {}
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Top-level extensions on implicit outer and inner receivers should resolve: \(errors)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let referenceTargets = ast.arena.exprs.indices.compactMap { index -> String? in
            let expression = ExprID(rawValue: Int32(index))
            guard case .callableRef? = ast.arena.expr(expression),
                  case let .symbol(target)? = sema.bindings.callableTargets[expression],
                  let symbol = sema.symbols.symbol(target)
            else {
                return nil
            }
            let name = ctx.interner.resolve(symbol.name)
            return ["aExtensionFunction", "bExtensionFunction"].contains(name) ? name : nil
        }
        #expect(referenceTargets.sorted() == [
            "aExtensionFunction", "aExtensionFunction", "bExtensionFunction"
        ].sorted())
    }

    @Test func testImplicitBoundExtensionInsideExtensionBody() throws {
        let source = """
        fun Int.odd(): Boolean = this % 2 == 1
        fun Int.evenProbe(): () -> Boolean = ::odd

        fun main() { println(4.evenProbe()()) }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "`::odd` inside an Int extension body binds to the extension receiver, got: \(errors)"
        )
    }

    @Test func testBoundMemberReferenceInsideClassStillWorks() throws {
        let source = """
        class C {
            fun m(): Int = 1
            fun capture() = ::m
        }

        fun main() { println(C().capture()()) }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Bound `::m` member reference must keep working, got: \(errors)")
    }

    @Test func testExplicitMemberReferenceOutranksSameNamedPackageExtension() throws {
        let source = """
        class Probe {
            fun label(): String = "member"
        }

        fun Probe.label(): String = "extension"

        fun capture(probe: Probe): () -> String = probe::label
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "The explicit receiver member should remain a valid callable reference: \(errors)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .callableRef(_, member, range) = ast.arena.expr(exprID),
                  ctx.interner.resolve(member) == "label",
                  ctx.sourceManager.origin(of: range.start.file) == .user
            else {
                return nil
            }
            return exprID
        }.first)
        guard case let .symbol(targetID)? = sema.bindings.callableTargets[callableRefExprID],
              let ownerID = sema.symbols.parentSymbol(for: targetID),
              let owner = sema.symbols.symbol(ownerID)
        else {
            Issue.record("probe::label should bind to a member function")
            return
        }
        #expect(owner.kind == .class)
    }

    @Test func testExplicitBoundReferenceFindsLocalExtensionAndSelectsOverload() throws {
        let source = """
        class Host { val text = "OK" }

        fun capture(): () -> String {
            fun Host.label(): String = text
            fun Host.label(prefix: String): String = prefix + text
            val label: () -> String = Host()::label
            return label
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "A local extension must be visible to an explicit bound reference: \(errors)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let reference = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .callableRef(_, member, range) = ast.arena.expr(exprID),
                  ctx.interner.resolve(member) == "label",
                  ctx.sourceManager.origin(of: range.start.file) == .user
            else {
                return nil
            }
            return exprID
        }.first)
        guard case let .symbol(targetID)? = sema.bindings.callableTargets[reference],
              let target = sema.symbols.symbol(targetID),
              let signature = sema.symbols.functionSignature(for: targetID)
        else {
            Issue.record("Host()::label should bind to a local extension function")
            return
        }
        #expect(target.flags.contains(.localFunction))
        #expect(signature.parameterTypes.isEmpty)
        #expect(!sema.bindings.isUnboundCallableRef(reference))

        let functionType = try #require(sema.bindings.exprType(for: reference))
        guard case let .functionType(function) = sema.types.kind(of: functionType) else {
            Issue.record("A bound local extension reference should have a function type")
            return
        }
        #expect(function.params.isEmpty)
        #expect(function.returnType == sema.types.stringType)
    }

    @Test func testExplicitBoundLocalExtensionReferenceCanBeInvoked() throws {
        let ctx = makeContextFromSource("""
        class Host { val text = "OK" }
        fun box(): String {
            fun Host.label() = text
            val label = Host()::label
            return label()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "A local extension reference should stay callable from a same-named local value: \(errors)")
    }

    @Test func testExplicitBoundReferenceToLocalExtensionRejectsIncompatibleReceiver() throws {
        let ctx = makeContextFromSource("""
        class Host
        class Other
        fun capture() {
            fun Host.label(): String = "host"
            val label = Other()::label
            println(label)
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "A local extension must not match an incompatible explicit receiver")
    }

    @Test func testExplicitBoundReferenceDoesNotLeakLocalExtensionOutsideScope() throws {
        let ctx = makeContextFromSource("""
        class Host
        fun declaresLocalExtension() {
            fun Host.label(): String = "host"
        }
        fun outside(): () -> String = Host()::label
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "A local extension must not escape its declaring function scope")
    }

    @Test func testExplicitMemberReferenceOutranksSameNamedLocalExtension() throws {
        let ctx = makeContextFromSource("""
        class Probe {
            fun label(): String = "member"
        }
        fun capture(probe: Probe): () -> String {
            fun Probe.label(): String = "local extension"
            return probe::label
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "The receiver member should remain a valid reference: \(errors)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let reference = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .callableRef(_, member, range) = ast.arena.expr(exprID),
                  ctx.interner.resolve(member) == "label",
                  ctx.sourceManager.origin(of: range.start.file) == .user
            else {
                return nil
            }
            return exprID
        }.first)
        guard case let .symbol(targetID)? = sema.bindings.callableTargets[reference],
              let ownerID = sema.symbols.parentSymbol(for: targetID),
              let owner = sema.symbols.symbol(ownerID)
        else {
            Issue.record("probe::label should bind to the member function")
            return
        }
        #expect(owner.kind == .class)
        #expect(sema.symbols.symbol(targetID)?.flags.contains(.localFunction) != true)
    }

    @Test(arguments: [
        "with(\"s\") { with(1) { ::tag } }",
        "with(\"s\") { with(1) { with(true) { ::tag } } }",
        "with(\"outer\") { with(\"inner\") { ::tag } }",
    ])
    func testImplicitExtensionCallableRefSearchesReceiverStack(expression: String) throws {
        let ctx = makeContextFromSource("""
        fun String.tag(): String = "ext:" + this
        fun main() {
            val f: () -> String = \(expression)
            println(f())
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Implicit reference must bind the matching receiver: \(errors)")
    }

    @Test(arguments: [
        "with(37) { ::lastDigit }",
        "with(37) { with(\"s\") { ::lastDigit } }",
    ])
    func testImplicitExtensionPropertyCallableRefIsBound(expression: String) throws {
        let ctx = makeContextFromSource("""
        val Int.lastDigit: Int get() = this % 10
        fun main() {
            val p: kotlin.reflect.KProperty0<Int> = \(expression)
            println(p.get())
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Implicit extension property must be a bound KProperty0: \(errors)")
    }

    @Test(arguments: [
        "fun Int.ext(): Int = 1",
        "val Int.ext: Int get() = 1",
    ])
    func testMemberExtensionRejectedInNestedReceiverScope(declaration: String) throws {
        let ctx = makeContextFromSource("""
        class C {
            \(declaration)
            fun capture() = with(1) { ::ext }
        }
        fun main() { println(C().capture()) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Member extensions must remain unreferenceable")
    }

    @Test func testBareCallableRefRejectsNominalExtension() throws {
        let ctx = makeContextFromSource("""
        class Receiver
        fun Receiver.tag(): String = "extension"
        fun main() { println(::tag) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Attaching an extension to its receiver must not make it a member")
    }

    @Test func testCallableReferenceDoesNotBindDslHiddenReceiver() throws {
        let ctx = makeContextFromSource("""
        @DslMarker annotation class Marker
        @Marker class Outer
        @Marker class Inner
        fun Outer.tag(): String = "outer"
        fun main() {
            val f = with(Outer()) { with(Inner()) { ::tag } }
            println(f)
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "A shared DSL marker hides the outer implicit receiver")
    }

    @Test func testBareCallableRefToTopLevelFunctionStillWorks() throws {
        let source = """
        fun double(x: Int): Int = x * 2

        fun main() {
            val f = ::double
            println(f(5))
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Bare `::double` to a top-level function must keep working, got: \(errors)")
    }
}
#endif

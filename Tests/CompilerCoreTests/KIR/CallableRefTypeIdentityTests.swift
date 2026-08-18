#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// REFL-003: Tests for KFunction / KProperty type identity on callable references.
@Suite
struct CallableRefTypeIdentityTests {
    // MARK: - Sema binding tests

    @Test func testSemaBindsFunctionRefKindForCallableReference() throws {
        let source = """
        fun inc(x: Int): Int = x + 1
        fun main() {
            val f = ::inc
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
        #expect(refKind == .functionRef, "::inc should be marked as a function reference.")
    }

    @Test func testSemaBindsPropertyRefKindForPropertyCallableReference() throws {
        let source = """
        val answer: Int = 42
        fun main() {
            val ref = ::answer
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
        #expect(refKind == .propertyRef, "::answer should be marked as a property reference.")
    }

    // KSP-496 byproduct bug: unlike the receiver-having branches of
    // inferCallableRefExpr (Type::member, obj::member), the bare/no-receiver
    // branch used to return the property's own type instead of the
    // explicitly-annotated expected type, so `val bare: KProperty0<Int> =
    // ::topLevel` failed with KSWIFTK-TYPE-0001 (assigning an Int-typed
    // expression to a KProperty0<Int>-typed variable).
    @Test func testSemaAcceptsExplicitKPropertyTypeForBareTopLevelPropertyReference() throws {
        let source = """
        import kotlin.reflect.KProperty0

        val topLevel: Int = 7

        fun main() {
            val bare: KProperty0<Int> = ::topLevel
            println(bare.name)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "Explicit KProperty0<Int> annotation on a bare top-level reference should type-check. Diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    // Devin review finding on the fix above: adopting `expectedType` verbatim without
    // checking it against the property's actual type let mismatched annotations compile
    // silently (e.g. `val r: KProperty0<String> = ::intProperty`), producing garbage at
    // runtime instead of a diagnostic. Covers the bare/no-receiver branch, the
    // receiver-having branch (pre-existing hole, same shape), a non-KProperty expected
    // type, and a mutability mismatch (val referenced as KMutableProperty0).
    @Test func testSemaRejectsMismatchedKPropertyValueTypeForBareReference() throws {
        let source = """
        import kotlin.reflect.KProperty0

        val topLevelInt: Int = 7

        fun main() {
            val r: KProperty0<String> = ::topLevelInt
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(ctx.diagnostics.hasError, "A KProperty0<String> annotation on an Int property reference must be a type error, not silently accepted.")
    }

    @Test func testSemaRejectsMismatchedKPropertyValueTypeForReceiverReference() throws {
        let source = """
        import kotlin.reflect.KProperty1

        class Person(val age: Int)

        fun main() {
            val r: KProperty1<Person, String> = Person::age
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(ctx.diagnostics.hasError, "A KProperty1<Person, String> annotation on an Int property reference must be a type error, not silently accepted.")
    }

    @Test func testSemaRejectsBarePropertyReferenceAsMismatchedFunctionType() throws {
        let source = """
        val topLevelInt: Int = 7

        fun main() {
            val f: (Int) -> Int = ::topLevelInt
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(ctx.diagnostics.hasError, "A zero-arg property reference is not a (Int) -> Int; this must be a type error, not silently accepted.")
    }

    @Test func testSemaRejectsImmutablePropertyReferenceAsKMutableProperty() throws {
        let source = """
        import kotlin.reflect.KMutableProperty0

        val topLevelInt: Int = 7

        fun main() {
            val m: KMutableProperty0<Int> = ::topLevelInt
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(ctx.diagnostics.hasError, "A val's reference cannot be typed as KMutableProperty0; this must be a type error, not silently accepted.")
    }

    @Test func testSemaBindsFunctionRefKindForBoundCallableReference() throws {
        let source = """
        class Box {
            fun value(): Int = 42
        }
        fun main(box: Box) {
            val f = box::value
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
        #expect(refKind == .functionRef, "box::value should be marked as a function reference.")
    }

    @Test func testSemaBindsFunctionRefKindForOverloadedCallableReference() throws {
        let source = """
        fun target(x: Int): Int = x + 1
        fun target(x: String): String = x
        fun main() {
            val ref: (Int) -> Int = ::target
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
        #expect(refKind == .functionRef, "Overloaded ::target should be marked as a function reference.")
    }

    // MARK: - KIR lowering tests

    @Test func testKIREmitsKFunctionTagForFunctionCallableRef() throws {
        let source = """
        fun inc(x: Int): Int = x + 1
        fun main(): Int {
            val f = ::inc
            return f(2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(
                callees.contains("kk_callable_ref_tag_kfunction"),
                "KIR main body should contain kk_callable_ref_tag_kfunction call. Callees: \(callees)"
            )
        }
    }

    @Test func testKIREmitsKPropertyTagForPropertyCallableRef() throws {
        let source = """
        val answer: Int = 42
        fun main(): Int {
            val ref = ::answer
            return answer
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            // Property callable refs are lowered inline in main.
            let allCallees = findAllKIRFunctions(in: module).flatMap { function in
                return extractCallees(from: function.body, interner: ctx.interner)
            }
            // Verify the property ref is tagged with the KProperty tag.
            #expect(
                allCallees.contains("kk_callable_ref_tag_kproperty"),
                "Property callable ref should be tagged as KProperty. Callees: \(allCallees)"
            )
            // Verify it does not accidentally tag as kfunction.
            #expect(
                !(allCallees.contains("kk_callable_ref_tag_kfunction")),
                "Property callable ref should NOT be tagged as KFunction."
            )
        }
    }

    // KSP-496 byproduct bug: a bare top-level `val` whose initializer is a
    // compile-time literal never gets a runtime store for its backing
    // global (lowerPropertyInitializer skips `needsInit` for such
    // properties, since ordinary reads are constant-folded and never touch
    // the global). The synthetic KProperty0 getter accessor generated for
    // `::topLevel` must therefore substitute the same literal constant
    // instead of emitting a `loadGlobal` against that never-initialized
    // slot — otherwise `.get()` silently returns the zero value.
    @Test func testKIRBareTopLevelConstantPropertyReferenceAccessorSubstitutesConstant() throws {
        let source = """
        import kotlin.reflect.KProperty0

        val distinctiveConst: Int = 4242

        fun main() {
            val ref: KProperty0<Int> = ::distinctiveConst
            println(ref.get())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let sema = try #require(ctx.sema)
            let propertySymbol = try #require(
                sema.symbols.lookup(fqName: [ctx.interner.intern("distinctiveConst")]),
                "distinctiveConst property symbol should be resolvable."
            )

            let allBodies = findAllKIRFunctions(in: module).map(\.body)

            let loadsOfProperty = allBodies.flatMap { body in
                body.compactMap { instruction -> SymbolID? in
                    guard case let .loadGlobal(_, symbol) = instruction, symbol == propertySymbol else { return nil }
                    return symbol
                }
            }
            #expect(
                loadsOfProperty.isEmpty,
                "distinctiveConst's never-initialized global must not be read via loadGlobal from the property-reference accessor."
            )

            let constantSubstitutions = allBodies.flatMap { body in
                body.compactMap { instruction -> Int64? in
                    guard case let .constValue(_, value) = instruction,
                          case let .intLiteral(literal) = value
                    else { return nil }
                    return literal
                }
            }
            #expect(
                constantSubstitutions.contains(4242),
                "The property-reference accessor should substitute the literal constant 4242 directly."
            )
        }
    }

    @Test func testKIRKFunctionTagIncludesCorrectNameAndArity() throws {
        let source = """
        fun add(a: Int, b: Int): Int = a + b
        fun main(): Int {
            val f = ::add
            return f(1, 2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            // Find the tagging call and verify its arguments.
            let tagCall = mainBody.first { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callee) == "kk_callable_ref_tag_kfunction"
            }
            guard case let .call(_, _, arguments, _, _, _, _, _) = tagCall else {
                Issue.record("Expected kk_callable_ref_tag_kfunction call in main body.")
                return
            }

            // arguments[0] = callable value, arguments[1] = name, arguments[2] = arity,
            // arguments[3] = isSuspend flag.
            #expect(arguments.count == 4)

            // Verify the name argument is the string "add".
            if let nameExpr = module.arena.expr(arguments[1]),
               case let .stringLiteral(nameInterned) = nameExpr
            {
                #expect(ctx.interner.resolve(nameInterned) == "add")
            } else {
                Issue.record("Second argument to tag call should be string literal 'add'.")
            }

            // Verify the arity argument is 2 (two value parameters).
            if let arityExpr = module.arena.expr(arguments[2]),
               case let .intLiteral(arityValue) = arityExpr
            {
                #expect(arityValue == 2, "::add has arity 2 (a, b).")
            } else {
                Issue.record("Third argument to tag call should be int literal for arity.")
            }

            // Non-suspend callable refs should emit an isSuspend flag of 0.
            if let suspendExpr = module.arena.expr(arguments[3]),
               case let .intLiteral(isSuspendValue) = suspendExpr
            {
                #expect(isSuspendValue == 0, "::add is not a suspend function.")
            } else {
                Issue.record("Fourth argument to tag call should be int literal for isSuspend.")
            }
        }
    }

    @Test func testKIRKFunctionTagForBoundCallableRef() throws {
        let source = """
        class Box {
            fun plus(x: Int): Int = x
        }
        fun main(box: Box): Int {
            val f = box::plus
            return f(7)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(
                callees.contains("kk_callable_ref_tag_kfunction"),
                "Bound callable ref box::plus should emit KFunction tag. Callees: \(callees)"
            )
        }
    }

    // MARK: - Non-throwing verification

    @Test func testCallableRefTagCallsAreNonThrowing() throws {
        let source = """
        fun inc(x: Int): Int = x + 1
        fun main(): Int {
            val f = ::inc
            return f(2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            let tagCall = mainBody.first { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callee) == "kk_callable_ref_tag_kfunction"
            }
            guard case let .call(_, _, _, _, canThrow, _, _, _) = tagCall else {
                Issue.record("Expected kk_callable_ref_tag_kfunction call.")
                return
            }
            #expect(!(canThrow), "Callable ref tagging call should be non-throwing.")
        }
    }
}
#endif

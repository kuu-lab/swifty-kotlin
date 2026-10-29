#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

// KUU-1407: declarations and modifier combinations that Kotlin/JVM rejects
// must produce diagnostics instead of being silently accepted.

private func semaContext(for source: String, frontendFlags: [String] = []) throws -> CompilationContext {
    let ctx = makeContextFromSource(
        source,
        frontendFlags: frontendFlags,
        allowDefaultStdlibLibrary: false
    )
    try runSema(ctx)
    return ctx
}

private func semaContextWithoutStdlib(for source: String) throws -> CompilationContext {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
    let ctx = makeCompilationContext(inputs: [path], includeStdlib: false, allowDefaultStdlibLibrary: false)
    _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
    try runSema(ctx)
    return ctx
}

@Suite(.serialized)
struct DeclarationPositionValidationTests {

    @Test(arguments: ["field = 2", "field += 1", "field++"])
    func readOnlyBackingFieldMutationIsRejected(statement: String) throws {
        let ctx = try semaContextWithoutStdlib(for: "class C { val x: Int = 0; get() { \(statement); return field } }")
        assertHasDiagnostic("KSWIFTK-SEMA-0014", in: ctx)
    }

    @Test
    func mutableBackingFieldMutationIsAccepted() throws {
        let ctx = try semaContextWithoutStdlib(for: "class C { var x: Int = 0; get() { field += 1; return field } }")
        #expect(!ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    @Test(arguments: [
        ("fun f(val x: Int) = x", "val"),
        ("fun f(var x: Int) = x", "var"),
        ("class C { fun f(val x: Int) = x }", "val"),
        ("fun outer() { fun f(var x: Int) = x }", "var"),
        ("val f = fun(val x: Int): Int = x", "val"),
    ])
    func propertyModifiersOnFunctionParametersAreRejected(source: String, modifier: String) throws {
        let ctx = try semaContextWithoutStdlib(for: source)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0444" }

        #expect(diagnostics.contains {
            $0.message == "'\(modifier)' on function parameter is prohibited."
        })
    }

    @Test
    func primaryConstructorPropertyParametersRemainAccepted() throws {
        let ctx = try semaContextWithoutStdlib(for: "class C(val x: Int, var y: Int)")
        assertNoDiagnostic("KSWIFTK-SEMA-0444", in: ctx)
    }

    @Test(arguments: [
        "class Box<T> { fun plus(other: Box<T>): Box<T> where T : Int = this }",
        "fun plain(value: Int): Int where T : Int = value",
    ])
    func whereClausesRequireFunctionTypeParameters(source: String) throws {
        let ctx = try semaContextWithoutStdlib(for: source)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0445" }

        #expect(diagnostics.count == 1, "Expected one where-clause diagnostic, got: \(diagnostics)")
        #expect(
            diagnostics.first?.message == "Type constraints are not allowed when no type parameters declared."
        )
        let expectedOffset = source.range(of: "where").map { source[..<$0.lowerBound].utf8.count }
        #expect(diagnostics.first?.primaryRange?.start.offset == expectedOffset)
    }

    @Test
    func genericFunctionWhereClauseRemainsAccepted() throws {
        let ctx = try semaContextWithoutStdlib(for: "fun <T> id(value: T): T where T : Any = value")
        assertNoDiagnostic("KSWIFTK-SEMA-0445", in: ctx)
    }

    // MARK: - Declaration positions

    @Test func constValInsideClassIsRejected() throws {
        let ctx = try semaContext(for: """
            class C { const val x = 1 }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0403", in: ctx)
    }

    @Test func initBlockInsideInterfaceIsRejected() throws {
        let ctx = try semaContext(for: """
            interface I { init { } }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0408", in: ctx)
    }

    @Test func constructorInsideInterfaceIsRejected() throws {
        let ctx = try semaContext(for: """
            interface I { constructor(x: Int) }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0409", in: ctx)
    }

    @Test func multipleCompanionObjectsInClassAreRejected() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            class C {
                companion object { }
                companion object { }
            }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0435", in: ctx)
    }

    @Test func oneCompanionObjectInClassIsAccepted() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            class C { companion object { } }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0435", in: ctx)
    }

    @Test func duplicateCompanionMemberReferencesStillResolve() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            class C { companion object A; companion object B { val w = 1 } }
            val y = C.B.w
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0435", in: ctx)
        // kotlinc keeps the duplicate companion in scope — references to it
        // must not add unresolved-member noise on top of the SEMA-0435 error.
        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    @Test func secondCompanionInsideObjectReportsBothDiagnostics() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            object O { companion object A; companion object B }
            """)
        // kotlinc reports 'companion' not applicable for both, plus the
        // only-one-companion error for the second.
        assertHasDiagnostic("KSWIFTK-SEMA-0401", in: ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0435", in: ctx)
        let notApplicableCount = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-0401" && $0.message.contains("'companion'")
        }.count
        #expect(notApplicableCount == 2)
    }

    @Test func companionInsideObjectMemberStillResolves() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            object O { companion object C { val v = 1 } }
            val x = O.C.v
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0401", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    @Test func companionInsideEnumEntryIsRejected() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            enum class E { X { companion object C { val v = 1 } }, Y }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0401", in: ctx)
        // kotlinc reports only the modifier error — no companion-count error
        // for enum entries.
        assertNoDiagnostic("KSWIFTK-SEMA-0435", in: ctx)
    }

    @Test func namedNominalsInsideEnumEntryAreRejected() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            enum class E {
                X {
                    class C
                    interface I
                    object N
                },
                Y
            }
            """)
        // kotlinc: 'Class'/'Interface' is prohibited here, named object 'N'
        // cannot be local — per declaration.
        let prohibited = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0451" }
        #expect(prohibited.count == 2)
        let cannotBeLocal = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-0429" && $0.message.contains("named object 'N'")
        }
        #expect(cannotBeLocal.count == 1)
    }

    @Test func enumAndAnnotationClassesInsideEnumEntryAreRejected() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            enum class E {
                X {
                    enum class E2 { A }
                    annotation class A2
                },
                Y
            }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0451", in: ctx)
    }

    @Test func enumEntryBodyFunctionsAndPropertiesAreAccepted() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            enum class E { X { val p = 1; fun f() = p }, Y }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0451", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0429", in: ctx)
    }

    @Test(arguments: [
        "class C<T, T> { }",
        "class C<T, T, T> { }",
        "fun <T, T> f() = 1",
        "interface I<K, K> {}",
        "typealias M<T, T> = T",
        "enum class E<T, T> { A }",
    ])
    func duplicateTypeParameterNamesAreRejected(_ source: String) throws {
        let ctx = try semaContextWithoutStdlib(for: source)
        assertHasDiagnostic("KSWIFTK-SEMA-0436", in: ctx)
    }

    @Test(arguments: [
        "class C<T> { }",
        "class C<T, U> { }",
        "fun <T, U> f() = 1",
        "interface I<K, V> {}",
        "typealias M<T, U> = T",
        "class Outer<T> { class Inner<T> { } }",
    ])
    func distinctTypeParameterNamesAreAccepted(_ source: String) throws {
        let ctx = try semaContextWithoutStdlib(for: source)
        assertNoDiagnostic("KSWIFTK-SEMA-0436", in: ctx)
    }

    @Test(arguments: [
        "companion fun f() = 1",
        "private companion fun f() = 1",
        "companion val x = 1",
        "companion class C {}",
        "companion typealias T = Int",
    ])
    func companionModifierWithoutObjectIsRejected(_ source: String) throws {
        let ctx = try semaContextWithoutStdlib(for: source)
        assertHasDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func companionAsFunctionNameIsAccepted() throws {
        let ctx = try semaContextWithoutStdlib(for: "fun companion() = 1")
        assertNoDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func dataInnerClassIsRejected() throws {
        let ctx = try semaContext(for: """
            class Outer { data inner class D(val x: Int) }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0402", in: ctx)
    }

    @Test func topLevelInnerClassIsRejected() throws {
        let ctx = try semaContext(for: """
            inner class D(val x: Int)
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0401", in: ctx)
    }

    @Test func abstractFinalClassReportsBothDirections() throws {
        let ctx = try semaContext(for: """
            abstract final class A
            """)
        let conflicts = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0402" }
        #expect(conflicts.count == 2)
        #expect(conflicts.contains { $0.message == "modifier 'abstract' is incompatible with 'final'." })
        #expect(conflicts.contains { $0.message == "modifier 'final' is incompatible with 'abstract'." })
    }

    @Test func sealedFinalClassReportsBothDirections() throws {
        let ctx = try semaContext(for: """
            sealed final class S
            """)
        let conflicts = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0402" }
        #expect(conflicts.count == 2)
        #expect(conflicts.contains { $0.message == "modifier 'sealed' is incompatible with 'final'." })
        #expect(conflicts.contains { $0.message == "modifier 'final' is incompatible with 'sealed'." })
    }

    @Test func privateProtectedClassReportsBothDirections() throws {
        let ctx = try semaContext(for: """
            private protected class C
            """)
        let conflicts = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0402" }
        #expect(conflicts.count == 2)
        // A conflicted `protected` suppresses the top-level applicability error.
        assertNoDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func privateInternalProtectedClassReportsEachModifierOnce() throws {
        let ctx = try semaContext(for: """
            private internal protected class D
            """)
        let conflicts = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0402" }
        #expect(conflicts.count == 3)
        #expect(conflicts.contains { $0.message == "modifier 'protected' is incompatible with 'private'." })
    }

    @Test func abstractFinalTopLevelFunctionReportsApplicabilityAndConflict() throws {
        let ctx = try semaContext(for: """
            abstract final fun f() {}
            """)
        // kotlinc reports 'abstract' not applicable and 'final' incompatible
        // with 'abstract'; the conflict wins over 'final's applicability error.
        let notApplicable = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0400" }
        #expect(notApplicable.count == 1)
        #expect(notApplicable.contains { $0.message.contains("'abstract'") })
        let conflicts = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0402" }
        #expect(conflicts.count == 1)
        #expect(conflicts.contains { $0.message == "modifier 'final' is incompatible with 'abstract'." })
    }

    @Test func finalOpenTopLevelFunctionReportsApplicabilityAndConflict() throws {
        let ctx = try semaContext(for: """
            final open fun g() {}
            """)
        let notApplicable = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0400" }
        #expect(notApplicable.count == 1)
        #expect(notApplicable.contains { $0.message.contains("'final'") })
        let conflicts = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0402" }
        #expect(conflicts.count == 1)
        #expect(conflicts.contains { $0.message == "modifier 'open' is incompatible with 'final'." })
    }

    @Test func dataInnerClassReportsBothDirections() throws {
        let ctx = try semaContext(for: """
            data inner class D(val x: Int)
            """)
        let conflicts = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0402" }
        #expect(conflicts.count == 2)
        // A conflicted `inner` suppresses the inside-file diagnostic.
        assertNoDiagnostic("KSWIFTK-SEMA-0401", in: ctx)
    }

    @Test func abstractFinalMemberFunctionReportsBothDirections() throws {
        let ctx = try semaContext(for: """
            abstract class AC {
                abstract final fun af(): Int
            }
            """)
        let conflicts = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0402" }
        #expect(conflicts.count == 2)
    }

    @Test func privateLocalVariableIsRejected() throws {
        let ctx = try semaContext(for: """
            fun f() { private val x = 1 }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func internalLocalVariableIsRejected() throws {
        let ctx = try semaContext(for: """
            fun f() { internal var y = 2 }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func privateLocalFunctionIsRejected() throws {
        let ctx = try semaContext(for: """
            fun f() { private fun g() {} }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func localInterfaceIsRejected() throws {
        let ctx = try semaContext(for: """
            fun f() { interface J { fun g() } }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0429", in: ctx)
    }

    @Test func localFunInterfaceIsRejected() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            fun f() { fun interface Action { fun run(n: Int): Int }; }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0429", in: ctx)
    }

    @Test(arguments: ["; ", "\n", ";\n", ";\n;"])
    func topLevelFunInterfaceBeforeSeparatedFunctionsIsAccepted(separator: String) throws {
        let source = """
            fun interface Action { fun run(n: Int): Int }
            fun make(): (Int) -> Int = { it }\(separator)fun test(): Int = 1
            """
        let ctx = try semaContextWithoutStdlib(for: source)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let file = try #require(ast.files.first)
        #expect(file.scriptBody.isEmpty)
        let declarations = file.topLevelDecls.compactMap { ast.arena.decl($0) }
        let functions = declarations.compactMap { decl -> String? in
            guard case let .funDecl(function) = decl else { return nil }
            return ctx.interner.resolve(function.name)
        }
        #expect(functions == ["make", "test"])
        #expect(declarations.count { decl in
            guard case let .interfaceDecl(interface) = decl else { return false }
            return ctx.interner.resolve(interface.name) == "Action"
        } == 1)
    }

    @Test func localAnnotationClassIsRejected() throws {
        let ctx = try semaContext(for: """
            fun f() { annotation class A(val x: Int) }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0429", in: ctx)
    }

    @Test func orphanActualIsRejected() throws {
        let ctx = try semaContext(for: """
            actual fun f(): Int = 1
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0410", in: ctx)
    }

    @Test func illegalOperatorNameIsRejected() throws {
        let ctx = try semaContext(for: """
            class C { operator fun notARealOp(): Int = 0 }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0416", in: ctx)
    }

    @Test(arguments: [
        "class C { operator fun mod(a: Int) = 1 }",
        "class C { operator fun modAssign(a: Int) {} }",
        "class C { operator fun and(a: C) = 1 }",
        "class C { operator fun shl(a: Int) = 1 }",
        "class C { operator fun component() = 1 }",
        "class C { operator fun component1x() = 1 }",
    ])
    func nonConventionOperatorNamesAreRejected(source: String) throws {
        let ctx = try semaContextWithoutStdlib(for: source)
        assertHasDiagnostic("KSWIFTK-SEMA-0416", in: ctx)
    }

    // MARK: - operator modifier eligibility (KUU-3149)

    @Test(arguments: [
        // Arity: each convention name pins down a value-parameter count.
        "class C { operator fun plus(a: C, b: Int) = 1 }",
        "class C { operator fun minus() = 1 }",
        "class C { operator fun unaryPlus(a: Int) = 1 }",
        "class C { operator fun not(a: Int) = true }",
        "class C { operator fun inv(a: Int) = 1 }",
        "class C { operator fun component1(a: Int) = 1 }",
        "class C { operator fun iterator(a: Int): Iterator<Int> = TODO() }",
        "class C { operator fun next(a: Int) = 1 }",
        "class C { operator fun hasNext(a: Int) = true }",
        "class C { operator fun compareTo(a: C, b: C) = 0 }",
        "class C { operator fun contains() = true }",
        "class C { operator fun rangeTo(a: C, b: C) = 1 }",
        "class C { operator fun plusAssign(a: Int, b: Int) {} }",
        "class C { operator fun get() = 1 }",
        "class C { operator fun set(i: Int) {} }",
        "class C { operator fun getValue(a: Int) = 1 }",
        "class C { operator fun setValue(a: Int, b: Int) {} }",
        "class C { operator fun provideDelegate(a: Int) = 1 }",
        "class C { operator fun getValue(a: Int, b: Int, c: Int) = 1 }",
        "class C { operator fun setValue(a: Int, b: Int, c: Int, d: Int) {} }",
        // Parameter shape: defaults and varargs are rejected once arity fits.
        "class C { operator fun plus(a: Int = 0) = 1 }",
        "class C { operator fun plus(vararg a: Int) = a.size }",
        "class C { operator fun contains(a: Int = 0) = true }",
        "class C { operator fun getValue(a: Int, vararg b: Int) = 1 }",
        "class C { operator fun set(i: Int, v: Int = 0) {} }",
        "class C { operator fun set(i: Int, vararg v: Int) {} }",
        // Position: operator functions must be members or extensions.
        "operator fun plus(a: Int, b: Int) = 1",
        "operator fun invoke() {}",
        "operator fun unaryPlus() = 1",
        "operator fun get(i: Int) = i",
        "operator fun Int.equals(o: Any?): Boolean = true",
        // `equals` must be a member that can override `Any.equals`.
        "operator fun equals(o: Any?): Boolean = true",
        "class C { operator fun equals() = true }",
        "class C { operator fun equals(a: Int, b: Int) = true }",
        // Delegate accessors must not be suspend.
        "class C { suspend operator fun provideDelegate(a: Int, b: Int) = 1 }",
        // Members of local classes and anonymous objects are checked too.
        "fun f() { class L { operator fun unaryPlus(a: Int) = 1 } }",
        "fun make() = object { operator fun component1(a: Int) = 1 }",
    ])
    func operatorEligibilityViolationsAreRejected(source: String) throws {
        let ctx = try semaContextWithoutStdlib(for: source)
        assertHasDiagnostic("KSWIFTK-SEMA-0439", in: ctx)
    }

    @Test(arguments: [
        "class C { operator fun plus(a: Int) = a }",
        "class C { operator fun unaryPlus() = 1 }",
        "class C { operator fun inc(a: Int): C = this }",
        "class C { operator fun invoke(a: Int, b: Int, c: Int) = 0 }",
        "class C { operator fun invoke(vararg a: Int) {} }",
        "class C { operator fun get(i: Int, j: Int) = i }",
        "class C { operator fun get(vararg i: Int) = i.size }",
        "class C { operator fun get(i: Int = 0) = i }",
        "class C { operator fun set(i: Int, v: Int) {} }",
        "class C { operator fun component0() = 1 }",
        "class C { operator fun component01() = 1 }",
        "class C { operator fun component15() = 1 }",
        "class C { operator fun inv() = 1 }",
        "class C { operator fun equals(other: Any?): Boolean = true }",
        "operator fun Int.plus(a: Int) = a",
        "operator fun Int.invoke() = 1",
        "interface I { operator fun unaryPlus(): Int }",
        "object O { operator fun not(): Boolean = true }",
        "class C { companion object { operator fun invoke() = 1 } }",
        "fun f() { class L { operator fun unaryPlus() = 1 } }",
        "fun make() = object { operator fun component1() = 1 }",
    ])
    func legalOperatorFunctionsAreAccepted(source: String) throws {
        let ctx = try semaContextWithoutStdlib(for: source)
        assertNoDiagnostic("KSWIFTK-SEMA-0439", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0416", in: ctx)
    }

    // MARK: - infix function requirements (KUU-2996)

    @Test(arguments: [
        "infix fun f(a: Int) = a",
        "infix fun g() = 0",
        "infix fun Int.f(a: Int, b: Int) = a",
        "infix fun Int.j(vararg a: Int) = a.size",
        "class C { infix fun m(a: Int, b: Int) = a }",
        "class C { infix fun m() = 0 }",
        "class C { infix fun m(vararg a: Int) = a.size }",
        "interface I { infix fun m(a: Int, b: Int): Int }",
        "object O { infix fun m(a: Int, b: Int) = a }",
        "fun outer() { infix fun f(a: Int) = a }",
        "fun outer() { infix fun Int.f(a: Int, b: Int) = a }",
        "fun outer() { class L { infix fun m(a: Int, b: Int) = a } }",
        "fun make() = object { infix fun m(a: Int, b: Int) = a }",
    ])
    func infixRequirementViolationsAreRejected(source: String) throws {
        let ctx = try semaContextWithoutStdlib(for: source)
        assertHasDiagnostic("KSWIFTK-SEMA-0431", in: ctx)
    }

    @Test(arguments: [
        "infix fun Int.f(a: Int) = a",
        "infix fun Int.k(a: Int = 0) = a",
        "class C { infix fun m(a: Int) = a }",
        "class C { infix fun Int.m(a: Int) = a }",
        "interface I { infix fun m(a: Int): Int }",
        "abstract class A { abstract infix fun m(a: Int): Int }",
        "object O { infix fun m(a: Int) = a }",
        "fun outer() { infix fun Int.f(a: Int) = a }",
        "fun outer() { class L { infix fun m(a: Int) = a } }",
        "fun make() = object { infix fun m(a: Int) = a }",
    ])
    func infixFunctionsSatisfyingRequirementsAreAccepted(source: String) throws {
        let ctx = try semaContextWithoutStdlib(for: source)
        assertNoDiagnostic("KSWIFTK-SEMA-0431", in: ctx)
    }

    // MARK: - vararg parameter requirements (KUU-2998)

    @Test(arguments: [
        "fun f(vararg a: Int, vararg b: Int) = a",
        "fun outer() { fun f(vararg a: Int, vararg b: Int) = a }",
        "val f = fun(vararg a: Int, vararg b: Int): Int { return a.size }",
        "class C(vararg a: Int, vararg b: Int)",
        "class C { constructor(vararg a: Int, vararg b: Int) }",
    ])
    func multipleVarargParametersAreRejected(source: String) throws {
        let ctx = try semaContextWithoutStdlib(for: source)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0441" }
        #expect(diagnostics.count == 2, "Expected one diagnostic per vararg modifier, got: \(diagnostics)")

        let expectedOffsets = [source.range(of: "vararg")!, source.range(of: "vararg", options: .backwards)!]
            .map { source.distance(from: source.startIndex, to: $0.lowerBound) }
            .sorted()
        let actualOffsets = diagnostics.compactMap { $0.primaryRange?.start.offset }.sorted()
        #expect(actualOffsets == expectedOffsets)
    }

    // MARK: - Annotation classes

    @Test func annotationMemberWithInvalidTypeIsRejected() throws {
        let ctx = try semaContext(for: """
            class SB
            annotation class A(val x: SB)
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0411", in: ctx)
    }

    @Test func annotationClassMembersAreRejected() throws {
        let ctx = try semaContext(for: """
            annotation class A(val x: Int) { fun f() {} }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0419", in: ctx)
    }

    @Test func annotationNestedTypesAreAllowed() throws {
        let ctx = try semaContext(for: """
            annotation class Tag(val mode: Mode = Mode.FIRST) {
                enum class Mode { FIRST, SECOND }
                class Nested(val value: Int)
                interface Marker
                object Named { val value: Int = 2 }
                companion object { const val DEFAULT: Int = 3 }
            }
            """)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "val value: Int = 1", "init {}", "constructor(value: Int) : this()", "typealias Value = String",
    ])
    func annotationInstanceMembersRemainRejected(member: String) throws {
        let ctx = try semaContext(for: "annotation class A { \(member) }")
        assertHasDiagnostic("KSWIFTK-SEMA-0419", in: ctx)
    }

    @Test func annotationNestedInnerClassIsRejected() throws {
        let ctx = try semaContext(for: "annotation class A { inner class Inner }")
        assertHasDiagnostic("KSWIFTK-SEMA-0401", in: ctx)
    }

    @Test func annotationVarParameterIsRejected() throws {
        let ctx = try semaContext(for: """
            annotation class A(var x: Int)
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0427", in: ctx)
    }

    // MARK: - Functional interfaces

    @Test func funInterfaceWithTwoAbstractFunctionsIsRejected() throws {
        let ctx = try semaContext(for: """
            fun interface F { fun a(); fun b() }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0406", in: ctx)
    }

    @Test func funInterfaceWithZeroAbstractFunctionsIsRejected() throws {
        let ctx = try semaContext(for: """
            fun interface F { fun a() {} }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0406", in: ctx)
    }

    @Test func funInterfaceWithOneAbstractFunctionIsAccepted() throws {
        let ctx = try semaContext(for: """
            fun interface F { fun run(): Int; fun helper() = 1 }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0406", in: ctx)
    }

    // MARK: - Value classes

    @Test func valueClassVarParameterIsRejected() throws {
        let ctx = try semaContext(for: """
            @JvmInline value class V(var x: Int)
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0423", in: ctx)
    }

    @Test func dataValueClassIsRejected() throws {
        let ctx = try semaContext(for: """
            @JvmInline data value class V(val x: Int)
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0402", in: ctx)
    }

    @Test func sealedValueClassIsRejected() throws {
        let ctx = try semaContext(for: """
            @JvmInline sealed value class V(val x: Int)
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0420", in: ctx)
    }

    @Test func fullValueClassesAcceptAbstractEmptyConstructorHierarchy() throws {
        let ctx = try semaContext(
            for: """
                abstract value class Base {
                    abstract val first: String
                    fun fakeOverridden(): String = first
                }
                abstract value class Child() : Base()
                """,
            frontendFlags: ["full-value-classes"]
        )

        #expect(
            !ctx.diagnostics.diagnostics.contains {
                $0.code == "KSWIFTK-SEMA-0420" || $0.code == "KSWIFTK-SEMA-0070"
            },
            "FullValueClasses should accept abstract value classes without primary constructor properties"
        )
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test func fullValueClassesKeepJvmInlineValueClassRestrictions() throws {
        let ctx = try semaContext(
            for: "@JvmInline abstract value class Empty()",
            frontendFlags: ["full-value-classes"]
        )

        assertHasDiagnostic("KSWIFTK-SEMA-0420", in: ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0070", in: ctx)
    }

    @Test(arguments: ["public", "private", "internal", "protected"])
    func visibilityModifierOnValueParameterIsRejected(_ modifier: String) throws {
        let ctx = try semaContextWithoutStdlib(for: "class C(\(modifier) value: Int)")

        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0400" }
        #expect(diagnostics.map(\.message) == [
            "modifier '\(modifier)' is not applicable to 'value parameter'."
        ])
    }

    @Test
    func visibilityModifierOnConstructorPropertyParameterIsAccepted() throws {
        let ctx = try semaContextWithoutStdlib(for: "class C(private val value: Int, internal var count: Int)")

        assertNoDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    // MARK: - Modifier incompatibilities

    @Test func conflictingTopLevelFunctionVisibilityModifiersAreRejected() throws {
        let ctx = try semaContextWithoutStdlib(for: "private public fun f() = 1")
        let errors = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0402" }
        #expect(errors.map(\.message) == ["modifier 'private' is incompatible with 'public'."])
    }

    @Test(arguments: [
        "private public", "private internal", "private protected",
        "public internal", "public protected", "internal protected",
    ])
    func conflictingMemberVisibilityModifierPairsAreRejected(pair: String) throws {
        let ctx = try semaContextWithoutStdlib(for: "class C { \(pair) fun f() {} }")
        let errors = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0402" }
        let modifiers = pair.split(separator: " ")
        let expectedMessage = "modifier '\(modifiers[0])' is incompatible with '\(modifiers[1])'."
        #expect(errors.map(\.message) == [expectedMessage], "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "class C private public constructor()",
        "class C { private public constructor() }",
    ])
    func conflictingConstructorVisibilityModifiersAreRejected(source: String) throws {
        let ctx = try semaContextWithoutStdlib(for: source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0402" }
        #expect(errors.map(\.message) == ["modifier 'private' is incompatible with 'public'."])
    }

    @Test func finalOpenFunctionIsRejected() throws {
        let ctx = try semaContext(for: """
            open class C { final open fun f() {} }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0402", in: ctx)
    }

    @Test func openEnumClassIsRejected() throws {
        let ctx = try semaContext(for: """
            open enum class E { A }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func sealedTopLevelFunctionIsRejected() throws {
        let ctx = try semaContext(for: """
            sealed fun f() {}
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func protectedInsideObjectIsRejected() throws {
        let ctx = try semaContext(for: """
            object O { protected fun f() {} }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0401", in: ctx)
    }

    @Test func constructorInsideObjectIsRejected() throws {
        let ctx = try semaContext(for: """
            object O { constructor() }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0417", in: ctx)
    }

    @Test func companionInsideObjectIsRejected() throws {
        let ctx = try semaContext(for: """
            object O { companion object C }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0401", in: ctx)
    }

    @Test func internalInsideInterfaceIsRejected() throws {
        let ctx = try semaContext(for: """
            interface I { internal fun f() {} }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0401", in: ctx)
    }

    // MARK: - Enum / data / property constraints

    @Test func enumExtendingClassIsRejected() throws {
        let ctx = try semaContext(for: """
            open class B
            enum class E : B() { A }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0405", in: ctx)
    }

    // MARK: - Interface supertypes (KUU-3233)

    @Test func interfaceExtendingClassIsRejected() throws {
        let ctx = try semaContext(for: """
            open class Base
            interface J : Base
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0438", in: ctx)
    }

    @Test func interfaceExtendingEnumOrObjectIsRejected() throws {
        let enumCtx = try semaContext(for: """
            enum class E { A }
            interface J : E
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0438", in: enumCtx)

        let objectCtx = try semaContext(for: """
            object O
            interface J : O
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0438", in: objectCtx)
    }

    @Test func interfaceExtendingInterfaceIsAccepted() throws {
        let ctx = try semaContext(for: """
            interface I
            interface J : I
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0438", in: ctx)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test func emptyDataClassIsRejected() throws {
        let ctx = try semaContext(for: """
            data class D()
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0404", in: ctx)
    }

    @Test func uninitializedMemberPropertyIsRejected() throws {
        let ctx = try semaContext(for: """
            class C { val x: Int }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0424", in: ctx)
    }

    @Test func computedVarWithEmptySetterIsAccepted() throws {
        let ctx = try semaContext(for: """
            class C {
                var value: Int
                    get() = 42
                    set(value) {}
            }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0424", in: ctx)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test func computedVarWithDefaultSetterStillNeedsInitialization() throws {
        let ctx = try semaContext(for: """
            class C {
                var value: Int
                    get() = 42
            }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0424", in: ctx)
    }

    @Test func computedVarWithPrivateSetterStillNeedsInitialization() throws {
        let ctx = try semaContext(for: """
            class C {
                var value: Int
                    get() = 42
                    private set
            }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0424", in: ctx)
    }

    @Test func backingFieldInComputedGetterStillNeedsInitialization() throws {
        let ctx = try semaContext(for: """
            class C {
                var value: Int
                    get() = field
                    set(value) {}
            }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0424", in: ctx)
    }

    @Test func backingFieldInCustomSetterStillNeedsInitialization() throws {
        let ctx = try semaContext(for: """
            class C {
                var value: Int
                    get() = 42
                    set(value) { field = value }
            }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0424", in: ctx)
    }

    @Test func interfacePropertyWithBackingFieldReferenceIsRejected() throws {
        let ctx = try semaContext(for: """
            interface I {
                var value: Int
                    get() = field
                    set(value) {}
            }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0424", in: ctx)
    }

    @Test func interfaceComputedPropertyReportsBackingFieldMessage() throws {
        // kotlinc phrases interface storage failures as a backing-field
        // prohibition, not a missing initializer.
        let ctx = try semaContext(for: """
            interface I {
                var a: Int get() = 1
                var b: Int set(v) {}
                val c: Int get() = field
            }
            """)
        let diags = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0424" }
        #expect(diags.count == 3, "diagnostics: \(diags.map(\.message))")
        for diag in diags {
            #expect(diag.message == "property in interface cannot have a backing field.")
        }
    }

    @Test func concreteAccessorPropertyReportsInitializedMessage() throws {
        // Accessor-bearing properties are concrete, so kotlinc reports plain
        // "must be initialized" without the abstract hint.
        let ctx = try semaContext(for: """
            class C {
                var a: Int get() = 1
                val b: Int get() = field
            }
            object O { var c: Int get() = 2 }
            """)
        let diags = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0424" }
        #expect(diags.count == 3, "diagnostics: \(diags.map(\.message))")
        for diag in diags {
            #expect(diag.message == "property must be initialized.")
        }
    }

    @Test func bodilessMemberPropertyReportsAbstractHint() throws {
        let ctx = try semaContext(for: """
            class C { var x: Int }
            abstract class D { var y: Int }
            """)
        let diags = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0424" }
        #expect(diags.count == 2, "diagnostics: \(diags.map(\.message))")
        for diag in diags {
            #expect(diag.message == "property must be initialized or be abstract.")
        }
    }

    @Test func abstractMemberPropertyIsAccepted() throws {
        let ctx = try semaContext(for: """
            abstract class C { abstract val x: Int }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0424", in: ctx)
    }

    @Test func initBlockInitializedPropertyIsAccepted() throws {
        let ctx = try semaContext(for: """
            class C { val x: Int
                init { x = 1 } }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0424", in: ctx)
    }

    // MARK: - Expressions

    @Test func nonThrowableCatchIsRejected() throws {
        let ctx = try semaContext(for: """
            fun f() { try {} catch (e: String) {} }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0413", in: ctx)
    }

    @Test func throwableCatchIsAccepted() throws {
        let ctx = try semaContext(for: """
            fun f() { try {} catch (e: Exception) {} }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0413", in: ctx)
    }

    @Test func nonThrowableThrowIsRejected() throws {
        let ctx = try semaContext(for: """
            fun f() { throw "oops" }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0414", in: ctx)
    }

    /// The messages used to embed the internal `Class#<symbol id>` debug form,
    /// which is meaningless to users and shifts whenever any stdlib symbol is
    /// added.
    @Test func nonThrowableDiagnosticsNameTheOffendingClass() throws {
        let ctx = try semaContext(for: """
            class Handled
            fun thrower() { throw Handled() }
            fun catcher() { try {} catch (e: Handled) {} }
            """)
        let messages = ctx.diagnostics.diagnostics
            .filter { $0.code == "KSWIFTK-SEMA-0413" || $0.code == "KSWIFTK-SEMA-0414" }
            .map(\.message)
        #expect(messages.count == 2, "\(messages)")
        #expect(messages.allSatisfy { $0.contains("'Handled'") && !$0.contains("Class#") }, "\(messages)")
    }

    @Test func throwableThrowIsAccepted() throws {
        let ctx = try semaContext(for: """
            fun f() { throw Exception() }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0414", in: ctx)
    }

    @Test func disjointIsCheckIsRejected() throws {
        let ctx = try semaContext(for: """
            fun f(x: Int) = x is String
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0415", in: ctx)
    }

    @Test func genericStarIsCheckIsAccepted() throws {
        let ctx = try semaContext(for: """
            interface Flow<out T>
            class Impl<T>(val source: Flow<T>) : Flow<T>
            fun <T> f(source: Flow<T>) = source is Impl<*>
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0415", in: ctx)
    }

    @Test func constructorDelegationCycleIsRejected() throws {
        let ctx = try semaContext(for: """
            class C {
                constructor(x: Int) : this(x.toString())
                constructor(s: String) : this(s.length)
            }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0412", in: ctx)
    }

    // MARK: - Valid constructs stay silent

    @Test func validDeclarationsAreAccepted() throws {
        let ctx = try semaContext(for: """
            class Outer { inner class In(val x: Int) }
            object O { const val K = 1 }
            annotation class A(val x: Int, val s: String, val k: kotlin.reflect.KClass<*>)
            fun interface FI { fun run(): Int }
            @JvmInline value class V(val x: Int)
            data class D(val x: Int)
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0401", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0402", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0403", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0404", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0406", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0411", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0420", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0423", in: ctx)
    }

    @Test func inlineTopLevelGetterOnlyPropertiesAreAccepted() throws {
        let ctx = try semaContext(for: """
            public inline val Short.highByte: Byte get() = 0
            inline val answer: Int get() = 42
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func inlineTopLevelVarWithCustomAccessorsIsAccepted() throws {
        let ctx = try semaContext(for: """
            var backing = 1
            private inline var value: Int
                get() = backing + 10000
                set(v) { backing = v + 100 }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func inlineMemberVarWithCustomAccessorsIsAccepted() throws {
        let ctx = try semaContext(for: """
            class C {
                private var backing = 0
                private inline var value: Int
                    get() = backing
                    set(v) { backing = v }
            }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func inlineExtensionVarWithCustomAccessorsIsAccepted() throws {
        let ctx = try semaContext(for: """
            inline var Int.value: Int
                get() = this + 1
                set(v) {}
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func inlineOpenMemberPropertyIsRejected() throws {
        let ctx = try semaContext(for: """
            open class C {
                open inline val value: Int get() = 42
            }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func inlineTopLevelPropertyWithInitializerIsRejected() throws {
        let ctx = try semaContext(for: """
            inline val answer: Int = 42
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func privateMembersOfAnonymousObjectsAreAccepted() throws {
        // Regression: object-literal member prefixes share the local
        // declaration parser — `private` there is legal.
        let ctx = try semaContext(for: """
            fun f(): Iterator<Int> {
                val it = object : Iterator<Int> {
                    private var index = 0
                    override fun hasNext(): Boolean = index < 1
                    override fun next(): Int = index
                }
                return it
            }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
    }

    @Test func lateinitLocalVarIsAccepted() throws {
        let ctx = try semaContext(for: """
            fun f() { lateinit var s: String; s = "x" }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0400", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0418", in: ctx)
    }
}
#endif

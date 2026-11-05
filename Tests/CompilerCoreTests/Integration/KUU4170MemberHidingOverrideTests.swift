#if canImport(Testing)
import Foundation
import Testing
import TestStdlibCache
@testable import CompilerCore
@testable import CompilerTestSupport

/// KUU-4170: Open/Final/Override semantic-analysis fixes found while
/// implementing KUU-4161, all checked against kotlinc 2.4.20:
///
/// - inherited member lookup specializes generic supertype arguments
///   (`G<T>.m(t: T)` seen from `D : G<D>` is `m(t: D)`), so a same-signature
///   declaration hides the parent member instead of slipping through;
/// - hiding is signature-based only: final parents still hide, the return
///   type is irrelevant, and expression bodies still carry the `anyType`
///   placeholder at header time;
/// - classes, objects, interfaces, and enum classes (plus `kotlin.Any` and
///   `kotlin.Enum` members) all participate;
/// - a same-signature member without `override` satisfies abstract
///   completeness so only the member-level 'hides member' diagnostic fires,
///   while a wrong-signature member still reports the abstract error;
/// - enum-entry members reach the same override validation as named owners;
/// - the source-compiled `kotlin.Enum` synthetic shell counts as
///   source-backed so 'overrides nothing' is not suppressed;
/// - imported `.kklib` metadata restores `.finalMember` on final members.
///
/// Every case is compiled in its own context: the sources intentionally
/// reuse top-level names (`A`, `B`, `I`, `E`), which would collide as
/// redeclarations if they shared one module.
@Suite
struct KUU4170MemberHidingOverrideTests {

    /// Which stdlib a case compiles against. `.library` reuses the shared
    /// precompiled `.kklib` artifact so imported-symbol paths stay fast;
    /// `.source` compiles the bundled stdlib from source, which is the only
    /// mode where the synthetic `kotlin.Enum` shell exists (KUU-4170 §3).
    private enum StdlibMode {
        case none
        case source
        case library
    }

    private func semaDiagnostics(
        for source: String,
        stdlib: StdlibMode = .none
    ) throws -> [Diagnostic] {
        var libraryPath: String? = nil
        var includeStdlib = false
        switch stdlib {
        case .none:
            break
        case .source:
            includeStdlib = true
        case .library:
            includeStdlib = true
            TestStdlibCache.shared.prepare()
            guard let artifact = CompilerOptions.defaultStdlibLibraryPath else {
                Issue.record("shared stdlib artifact unavailable after prepare()")
                return []
            }
            libraryPath = artifact
        }
        var result: [Diagnostic] = []
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: includeStdlib,
                stdlibLibraryPath: libraryPath
            )
            try runSema(ctx)
            result = diagnosticsForPath(path, in: ctx)
        }
        return result
    }

    private func assertSingleHidesMember(
        _ source: String,
        stdlib: StdlibMode = .none,
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) throws {
        let diags = try semaDiagnostics(for: source, stdlib: stdlib)
        let hiding = diags.filter { $0.code == "KSWIFTK-SEMA-OVERRIDE" }
        #expect(hiding.count == 1, "Got: \(diags.map(\.code))", sourceLocation: sourceLocation)
        #expect(
            hiding.first?.message.contains("hides member of supertype") == true,
            "Got: \(diags.map(\.message))",
            sourceLocation: sourceLocation
        )
    }

    /// `open class G<T> { open fun m(t: T) }` inherited through `D : G<D>`
    /// exposes `m(t: D)`; raw `TypeID` comparison used to miss it (KUU-4170).
    @Test
    func testGenericSupertypeSignatureHiding() throws {
        let rejectingSources = [
            """
            open class G<T> { open fun m(t: T) = 1 }
            class D : G<D>() { fun m(t: D) = 1 }
            """,
            """
            open class A<T> { open fun m(t: T) = 1 }
            class E<T> : A<T>() { fun m(t: T) = 1 }
            """,
            """
            interface I<T> { fun m(t: T) }
            class C : I<C> { fun m(t: C) {} }
            """,
            """
            open class N<T> { open fun m(t: T): T? = null }
            class ND : N<ND>() { fun m(t: ND): ND? = null }
            """,
        ]
        let acceptingSources = [
            """
            open class G<T> { open fun m(t: T) = 1 }
            class OK : G<Int>() { override fun m(t: Int) = 1 }
            """,
            """
            open class G<T> { open fun m(t: T) = 1 }
            class Overload : G<Int>() { fun m(t: Long) = 1 }
            """,
        ]

        for source in rejectingSources {
            try assertSingleHidesMember(source)
        }
        for source in acceptingSources {
            let diags = try semaDiagnostics(for: source)
            assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: diags)
            #expect(!diags.hasError, "Got: \(diags.map(\.code))")
        }
    }

    /// Hiding does not consult overridability or the return type: a final
    /// parent still hides, an incompatible return still hides, and an
    /// expression body whose return is still the `anyType` placeholder at
    /// header time still hides (KUU-4170).
    @Test
    func testFinalParentAndInferredReturnHiding() throws {
        let rejectingSources = [
            // Final parent member: `fun f()` in `A` is final by default.
            """
            open class A { fun f() = 1 }
            open class B : A() { fun f() = 2 }
            """,
            // Both sides infer their return; the child return is a
            // placeholder when header analysis runs.
            """
            open class A2 { open fun f() = "" }
            class B2 : A2() { fun f() = 1 }
            """,
            // Incompatible return types still hide — the return type is
            // not part of the hiding check.
            """
            open class A3 { open fun f(): String = "" }
            class B3 : A3() { fun f(): Int = 1 }
            """,
        ]

        for source in rejectingSources {
            try assertSingleHidesMember(source)
        }
    }

    /// Classes, objects, interfaces, enum classes, enum entries, and the
    /// implicit `kotlin.Any`/`kotlin.Enum` members all participate in
    /// hides-member detection (KUU-4170). `.library` mode exercises the
    /// imported-metadata path for the stdlib members.
    @Test
    func testOwnerKindAndStdlibMemberHiding() throws {
        let sources = [
            // kotlin.Any namesakes with no explicit supertype.
            """
            class C3 { fun toString() = "" }
            """,
            """
            object O3 { fun toString() = "" }
            """,
            // kotlin.Enum members on the enum class and on an entry body.
            """
            enum class E1 { A; fun toString(): String = "" }
            """,
            """
            enum class E2 { A { fun toString() = "" } }
            """,
            // Interface implementations hide like class inheritance.
            """
            interface I { fun g() }
            class C : I { fun g() {} }
            """,
            """
            interface I { fun g() }
            object O : I { fun g() {} }
            """,
            """
            interface I { fun g() }
            enum class E : I { A; fun g() {} }
            """,
            // An entry member hides the enum class's own same-signature
            // member (the anonymous entry class subclasses the enum class).
            """
            enum class E {
                A { fun g() = 2 };
                fun g() = 1
            }
            """,
        ]

        for source in sources {
            try assertSingleHidesMember(source, stdlib: .library)
        }
    }

    /// kotlinc counts a same-signature member without `override` as
    /// implementing the abstract requirement and reports only the
    /// member-level 'hides member' diagnostic; a wrong-signature (or
    /// wrong-kind) member does not, so the abstract error remains
    /// (KUU-4170).
    @Test
    func testAbstractCompletenessVersusHiding() throws {
        // Same signature: hides-member only, no KSWIFTK-SEMA-ABSTRACT.
        let hidesOnlySources: [(String, StdlibMode)] = [
            ("""
            interface I { fun g() }
            class C : I { fun g() {} }
            """, .none),
            ("""
            interface I { fun g() }
            enum class E : I { A { fun g() {} } }
            """, .library),
            ("""
            interface I { fun g() }
            enum class E : I { A; fun g() {} }
            """, .library),
        ]
        // Wrong signature or wrong kind: the abstract requirement is unmet.
        let abstractOnlySources: [(String, StdlibMode)] = [
            ("""
            interface I { fun g() }
            class C : I { fun g(x: Int) {} }
            """, .none),
            ("""
            interface I { fun g() }
            class C : I { val g = 1 }
            """, .none),
            ("""
            interface I { fun g() }
            enum class E : I { A { fun g(x: Int) {} } }
            """, .library),
        ]

        for (source, stdlib) in hidesOnlySources {
            let diags = try semaDiagnostics(for: source, stdlib: stdlib)
            assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: diags)
            assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: diags)
        }
        for (source, stdlib) in abstractOnlySources {
            let diags = try semaDiagnostics(for: source, stdlib: stdlib)
            assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: diags)
            assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: diags)
        }
    }

    /// `override` on an enum-entry member with no signature-matching
    /// target reports 'overrides nothing' under the same completeness
    /// gates named owners use — the bundled `kotlin.Enum` source shell
    /// counts as source-backed so the check is not suppressed in
    /// source-stdlib mode (KUU-4170 §3).
    @Test(arguments: [false, true])
    func testEnumEntryOverrideNothing(useLibrary: Bool) throws {
        let rejectingSources = [
            """
            enum class E { B { override fun g() = 1 } }
            """,
            """
            enum class E { A, B; override fun g() = 1 }
            """,
        ]

        for source in rejectingSources {
            let diags = try semaDiagnostics(
                for: source,
                stdlib: useLibrary ? .library : .source
            )
            let overrideNothing = diags.filter {
                $0.code == "KSWIFTK-SEMA-OVERRIDE-NOTHING"
            }
            #expect(
                overrideNothing.count == 1,
                "Got: \(diags.map(\.code))"
            )
        }
    }

    /// Same-signature hiding must not fire for unrelated declarations:
    /// different parameter signatures, private parents, and the separate
    /// property/function namespaces (KUU-4170).
    @Test
    func testNoFalsePositiveHiding() throws {
        let acceptingSources = [
            // Overload with a different signature is a different member.
            """
            open class A { open fun f(x: Int) = 1 }
            class B : A() { fun f(x: Long) = 2 }
            """,
            // Private members are not inherited, so they cannot be hidden.
            """
            open class A { private fun f() = 1 }
            class B : A() { fun f() = 2 }
            """,
            // Properties and functions are separate override namespaces.
            """
            open class A { val x = 1 }
            class B : A() { fun x() = 2 }
            """,
            """
            open class A { fun x() = 1 }
            class B : A() { val x = 2 }
            """,
        ]

        for source in acceptingSources {
            let diags = try semaDiagnostics(for: source)
            assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: diags)
            #expect(!diags.hasError, "Got: \(diags.map(\.code))")
        }
    }

    /// Imported `.kklib` metadata encodes `final` as modality `.final`;
    /// the import path must restore `.finalMember` on member records or
    /// `final override` members (kotlin.Enum.compareTo/equals/hashCode)
    /// look overridable and `override` against them is silently accepted
    /// (KUU-4170).
    @Test(arguments: [false, true])
    func testImportedFinalOverrideMembersStayFinal(useLibrary: Bool) throws {
        let source = """
        enum class E { A; override fun equals(other: Any?): Boolean = true }
        enum class F { A; override fun compareTo(other: F): Int = 0 }
        enum class G { A; override fun hashCode(): Int = 1 }
        """
        let diags = try semaDiagnostics(
            for: source,
            stdlib: useLibrary ? .library : .source
        )
        let finalErrors = diags.filter { $0.code == "KSWIFTK-SEMA-FINAL" }
        #expect(finalErrors.count == 3, "Got: \(diags.map(\.code))")
    }
}
#endif

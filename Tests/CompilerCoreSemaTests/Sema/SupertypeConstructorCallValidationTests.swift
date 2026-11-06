#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

// KUU-4132: supertype `()` validation gaps — non-expect classes without a
// primary constructor, `()` on interface supertypes, and (already covered
// by KUU-3945) `by` delegation on expect declarations.

private func semaContextWithoutStdlib(for source: String) throws -> CompilationContext {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
    let ctx = makeCompilationContext(inputs: [path], includeStdlib: false, allowDefaultStdlibLibrary: false)
    _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
    try runSema(ctx)
    return ctx
}

@Suite
struct SupertypeConstructorCallValidationTests {

    // MARK: - non-expect class without a primary constructor (KUU-4132 case 1)

    @Test
    func classWithoutPrimaryConstructorRejectsSupertypeCall() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            open class Sup
            class NoPrimCall : Sup() {
                constructor(x: Int) : super()
            }
            """)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0474" }
        #expect(diagnostics.count == 1, "expected one impossible-initialization diagnostic: \(ctx.diagnostics.diagnostics)")
        #expect(
            diagnostics.first?.message
                == "supertype initialization is impossible without a primary constructor."
        )
    }

    @Test
    func localClassWithoutPrimaryConstructorRejectsSupertypeCall() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            open class Sup
            fun f() {
                class Local : Sup() {
                    constructor(x: Int) : super()
                }
            }
            """)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0474" }
        #expect(diagnostics.count == 1, "expected one impossible-initialization diagnostic: \(ctx.diagnostics.diagnostics)")
    }

    // The check is syntactic: kotlinc reports the diagnostic even when the
    // supertype name fails to resolve.
    @Test
    func unresolvedSupertypeStillRejectsCallWithoutPrimaryConstructor() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            class NoPrimCall : Bogus() {
                constructor(x: Int) : super()
            }
            """)
        #expect(
            ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0474" },
            "unresolved supertype still has no primary constructor: \(ctx.diagnostics.diagnostics)"
        )
    }

    // A class with secondary constructors loses its implicit primary
    // constructor, so `()` is impossible on every `()` supertype entry —
    // including interface supertypes (kotlinc reports both diagnostics).
    @Test
    func secondaryConstructorClassRejectsInterfaceSupertypeCall() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            interface IFoo
            class A : IFoo() {
                constructor(x: Int)
            }
            """)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0474" }, "\(errors)")
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0481" }, "\(errors)")
    }

    // MARK: - legal forms stay accepted

    @Test
    func legalSupertypeCallFormsAreAccepted() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            open class Sup
            interface IFoo
            class WithImplicitPrimary : Sup()
            class WithExplicitPrimary() : Sup()
            class NoPrim : Sup {
                constructor(x: Int) : super()
            }
            class ImplementsI : IFoo
            object Obj : Sup()
            fun f() {
                class LocalImplicit : Sup()
                class LocalNoPrim : Sup {
                    constructor(x: Int) : super()
                }
            }
            """)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            !errors.contains { $0.code == "KSWIFTK-SEMA-0474" || $0.code == "KSWIFTK-SEMA-0481" || $0.code == "KSWIFTK-SEMA-0482" },
            "legal supertype forms must not emit constructor-call diagnostics: \(errors)"
        )
    }

    // MARK: - interface supertypes with `()` (KUU-4132 case 2)

    @Test
    func classImplementingInterfaceWithCallIsRejected() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            interface IFoo
            class A : IFoo()
            """)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0481" }
        #expect(diagnostics.count == 1, "expected one no-constructor diagnostic: \(ctx.diagnostics.diagnostics)")
        #expect(diagnostics.first?.message == "this type does not have a constructor.")
        // A class with an implicit primary constructor does not earn the
        // impossible-initialization diagnostic for an interface `()` entry.
        #expect(
            !ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0474" },
            "\(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func interfaceExtendingInterfaceWithCallIsRejected() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            interface IFoo
            interface I : IFoo()
            """)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0482" }, "\(errors)")
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0481" }, "\(errors)")
        // Interfaces never have a primary constructor, but kotlinc reports
        // their `()` entries as "interfaces cannot initialize supertypes",
        // not "impossible without a primary constructor".
        #expect(
            !errors.contains { $0.code == "KSWIFTK-SEMA-0474" },
            "\(errors)"
        )
    }

    @Test
    func interfaceExtendingClassWithCallIsRejected() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            open class Sup
            interface J : Sup()
            """)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0438" }, "\(errors)")
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0482" }, "\(errors)")
        // `Sup` is a class, so the no-constructor diagnostic does not apply.
        #expect(
            !errors.contains { $0.code == "KSWIFTK-SEMA-0481" },
            "\(errors)"
        )
    }

    // The "interfaces cannot initialize supertypes" check is syntactic:
    // kotlinc reports it even when the supertype name fails to resolve.
    @Test
    func interfaceWithCallOnUnresolvedSupertypeIsRejected() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            interface I : Bogus()
            """)
        #expect(
            ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0482" },
            "unresolved supertype still cannot be initialized: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func objectLiteralImplementingInterfaceWithCallIsRejected() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            interface IFoo
            val o = object : IFoo() {}
            """)
        #expect(
            ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0481" },
            "\(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func namedObjectImplementingInterfaceWithCallIsRejected() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            interface IFoo
            object O : IFoo()
            """)
        #expect(
            ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0481" },
            "\(ctx.diagnostics.diagnostics)"
        )
    }

    // `expect interface I : IFoo()` earns the interface-initialization and
    // expect diagnostics plus the no-constructor one — but never the
    // impossible-initialization diagnostic (kotlinc parity).
    @Test
    func expectInterfaceWithCallMatchesKotlincDiagnostics() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            interface IFoo
            expect interface IE : IFoo()
            """)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0482" }, "\(errors)")
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0481" }, "\(errors)")
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0475" }, "\(errors)")
        #expect(
            !errors.contains { $0.code == "KSWIFTK-SEMA-0474" },
            "\(errors)"
        )
    }

    // MARK: - legal interface forms stay accepted

    @Test
    func legalInterfaceSupertypeFormsAreAccepted() throws {
        let ctx = try semaContextWithoutStdlib(for: """
            interface IFoo
            interface IBar
            interface I : IFoo, IBar
            class C : IFoo
            fun g(): IFoo = object : IFoo {}
            """)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            !errors.contains { $0.code == "KSWIFTK-SEMA-0481" || $0.code == "KSWIFTK-SEMA-0482" },
            "legal interface forms must not emit constructor-call diagnostics: \(errors)"
        )
    }
}
#endif

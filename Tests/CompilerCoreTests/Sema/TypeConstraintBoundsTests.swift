@testable import CompilerCore
import Testing

private struct MissingFunctionDeclaration: Error, CustomStringConvertible {
    let name: String

    var description: String {
        "Missing function declaration: \(name)"
    }
}

@Suite
struct TypeConstraintBoundsTests {

    @Test func testTypeConstraintBoundsSema() throws {
        let sources: [String] = [
            // upperBoundViolationEmitsBoundDiagnostic
            """
            package sample0
                    class Plain

                    fun <T : Comparable<T>> maxItem(a: T, b: T): T = if (a > b) a else b

                    fun usePlain(): Plain = maxItem(Plain(), Plain())

            """,

            // conflictingClassUpperBoundsEmitsDiagnostic
            """
            package sample1
                    fun <T> conflicting(a: T, b: T): T where T : Int, T : String = a

            """,

            // conflictingUserClassUpperBoundsEmitsDiagnostic
            """
            package sample2
                    class Foo
                    class Bar

                    fun <T> conflicting(x: T): T where T : Foo, T : Bar = x

            """,

            // conflictingUpperBoundsOnClassTypeParameterEmitsDiagnostic
            """
            package sample3
                    class Box<T> where T : Int, T : String

            """,

            // interfaceAndAnyUpperBoundsEmitNoDiagnostic
            """
            package sample4
                    fun <T> processItem(v: T): String where T : Comparable<T>, T : Any = v.toString()

            """,

            // subtypeRelatedClassUpperBoundsEmitNoDiagnostic
            """
            package sample5
                    open class Base
                    class Derived : Base()

                    fun <T> f(x: T): T where T : Base, T : Derived = x

            """,

            // subtypeRelatedClassUpperBoundsOnClassTypeParameterEmitNoDiagnostic
            """
            package sample6
                    open class Base
                    class Derived : Base()

                    class Box<T> where T : Base, T : Derived

            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // upperBoundViolationEmitsBoundDiagnostic
            do {
                let samplePath = paths[0]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-BOUND", in: sampleDiags)
            }
            // conflictingClassUpperBoundsEmitsDiagnostic
            do {
                let samplePath = paths[1]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0305", in: sampleDiags)
            }
            // conflictingUserClassUpperBoundsEmitsDiagnostic
            do {
                let samplePath = paths[2]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0305", in: sampleDiags)
            }
            // conflictingUpperBoundsOnClassTypeParameterEmitsDiagnostic
            do {
                let samplePath = paths[3]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0305", in: sampleDiags)
            }
            // interfaceAndAnyUpperBoundsEmitNoDiagnostic
            do {
                let samplePath = paths[4]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0305", in: sampleDiags)
            }
            // subtypeRelatedClassUpperBoundsEmitNoDiagnostic
            do {
                let samplePath = paths[5]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0305", in: sampleDiags)
            }
            // subtypeRelatedClassUpperBoundsOnClassTypeParameterEmitNoDiagnostic
            do {
                let samplePath = paths[6]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0305", in: sampleDiags)
            }

        }
    }

    @Test func whereClauseAndMultipleUpperBoundsArePreservedInAST() throws {
        let source = """
        class Animal

        fun <T : Comparable<T>> clamp(value: T, min: T, max: T): T = when {
            value < min -> min
            value > max -> max
            else -> value
        }

        fun <T> maxItem(a: T, b: T): T where T : Comparable<T> = if (a > b) a else b

        fun <T> processItem(v: T): String where T : Comparable<T>, T : Any = v.toString()
        """

        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try requireTestValue(ctx.ast, "Missing AST")
        let file = try requireTestValue(ast.files.first, "Missing file")

        func function(named targetName: String) throws -> FunDecl {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(fun) = decl,
                      ctx.interner.resolve(fun.name) == targetName
                else {
                    continue
                }
                return fun
            }
            throw MissingFunctionDeclaration(name: targetName)
        }

        let clamp = try function(named: "clamp")
        #expect(clamp.typeParams.first?.upperBounds.count == 1)

        let maxItem = try function(named: "maxItem")
        #expect(maxItem.typeParams.first?.upperBounds.count == 1)

        let processItem = try function(named: "processItem")
        #expect(processItem.typeParams.first?.upperBounds.count == 2)
    }



    // DEBT-SEMA-002 (migrated from Scripts/diff_cases/error_type_inference.kt / DEBT-DIFF-006):
    // `where T : Int, T : String` combines two mutually exclusive class bounds. kotlinc 2.4.0 rejects the
    // declaration itself:
    //   error: upper bounds of 'T' have an empty intersection.
    //   error: type parameter 'T' ... has inconsistent bounds: Int, String.
    //   error: only one of the upper bounds can be a class.
    // kswiftc validates bound satisfaction at call sites (see upperBoundViolationEmitsBoundDiagnostic
    // above) and, as of this fix, also rejects an unsatisfiable declaration-site combination via
    // KSWIFTK-SEMA-0305.




    // Same check, but for two unrelated user-declared classes rather than builtin primitives —
    // exercises the `.classType` (as opposed to `.primitive`/`.stringStruct`) branch.




    // The same check applies to a class's own type parameters (registerNominalTypeParameters),
    // not just function type parameters (collectFunctionTypeParameters).




    // Guard against false positives: an interface bound plus the trivial `Any` bound (as in
    // whereClauseAndMultipleUpperBoundsArePreservedInAST's `processItem`) must not be
    // flagged — `Any` is satisfied by every type, and `Comparable<T>` is an interface, so there
    // is at most one class-kind bound here.




    // Scope boundary, intentionally not flagged: DEBT-SEMA-002 targets bounds with an empty
    // intersection (no type can satisfy both). When one class-kind bound is a subtype of the
    // other, the combination is redundant but not unsatisfiable, so it is out of scope here —
    // unlike kswiftc, real kotlinc still rejects this via a separate, stricter rule ("only one
    // of the upper bounds can be a class") that this fix does not attempt to replicate.




    // Regression pin for a pass-ordering bug: header collection (which resolves a type
    // parameter's bounds and is where this check used to fire immediately) runs before
    // `bindInheritanceEdges` (which links `Derived`'s supertype to `Base`). Checking eagerly
    // saw the two classes as unrelated in either direction and misfired here. The check is
    // now deferred to run after inheritance edges are bound (see
    // HeaderHelpers+TypeParameterBoundValidation.swift). Same scenario as
    // subtypeRelatedClassUpperBoundsEmitNoDiagnostic above, but through a class's own type
    // parameters (registerNominalTypeParameters) rather than a function's.




}

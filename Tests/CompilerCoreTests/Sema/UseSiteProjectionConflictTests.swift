@testable import CompilerCore
import Testing

@Suite
struct UseSiteProjectionConflictTests {
    private let declarations = """
    class Source<out T>
    class Sink<in T>
    class Box<T>
    typealias O<T> = Source<T>
    typealias I<T> = Box<T>
    typealias F<T> = (T) -> Unit
    typealias R<T> = () -> T
    typealias Both<T> = (T) -> T
    typealias Nested<T> = Source<Sink<T>>
    typealias Double<T> = Sink<Sink<T>>
    typealias NestInv<T> = Box<Source<T>>
    typealias Projected<T> = Box<out T>
    typealias Contra<T> = Box<in T>
    typealias FList<T> = (Box<T>) -> Unit
    typealias NestedFunction<T> = ((T) -> Unit) -> Unit
    typealias RFunction<T> = () -> ((T) -> Unit)
    """

    @Test(arguments: [
        "Source<in Int>", "Source<in Nothing>", "Sink<out Int>",
        "O<in Int>", "F<out Int>", "R<in Int>",
        "Both<out Int>", "Both<in Int>", "Nested<out Int>",
        "Double<out Int>", "NestInv<in Int>", "Projected<in Int>",
        "Contra<out Int>", "NestedFunction<out Int>",
    ], [false, true])
    func rejectsConflictingProjection(type: String, local: Bool) throws {
        let use = local ? "fun use() { val value: \(type)? = null }" : "fun use(value: \(type)) {}"
        // Put the use first to exercise variance metadata for forward classes.
        let diagnostics = try check(use + "\n" + declarations)
        #expect(diagnostics.contains { $0.severity == .error && $0.code == "KSWIFTK-SEMA-PROJECTION-CONFLICT" }, "\(diagnostics)")
    }

    @Test(arguments: [
        "Source<out Int>", "Sink<in Int>", "Box<out Int>", "Box<in Int>",
        "Source<*>", "Sink<*>", "I<out Int>", "I<in Int>", "I<*>",
        "F<in Int>", "R<out Int>", "Double<in Int>", "Nested<in Int>",
        "NestInv<out Int>", "FList<out Int>", "FList<in Int>",
        "NestedFunction<in Int>", "RFunction<in Int>",
    ], [false, true])
    func preservesLegalProjection(type: String, local: Bool) throws {
        let use = local ? "fun use() { val value: \(type)? = null }" : "fun use(value: \(type)) {}"
        let diagnostics = try check(use + "\n" + declarations)
        #expect(!diagnostics.contains { $0.severity == .error }, "\(diagnostics)")
    }

    @Test(arguments: [
        "typealias Broken<T> = Source<in T>\nclass Source<out T>",
        "typealias Forward<T> = Consumer<out T>\ntypealias Consumer<T> = (T) -> Unit",
    ])
    func rejectsUnusedInvalidAliasBeforeNormalization(source: String) throws {
        let diagnostics = try check(source)
        #expect(diagnostics.contains { $0.code == "KSWIFTK-SEMA-PROJECTION-CONFLICT" }, "\(diagnostics)")
    }

    @Test(arguments: [("A", "out Int", true), ("out A", "in Int", false)])
    func distinguishesInnerOwnArguments(outer: String, argument: String, rejects: Bool) throws {
        let diagnostics = try check("""
        class Outer<\(outer)> {
            inner class Inner<in B>
            private fun use(value: Inner<\(argument)>) {}
        }
        """)
        #expect(diagnostics.contains { $0.severity == .error } == rejects, "\(diagnostics)")
    }

    @Test(.timeLimit(.minutes(1)))
    func sharedExpandedAliasDagIsBounded() throws {
        let (_, symbols, types, interner) = makeSemaModule()
        let name = interner.intern("Pair")
        let pair = symbols.define(kind: .class, name: name, fqName: [name],
                                  declSite: nil, visibility: .public, flags: [])
        types.setNominalTypeParameterVariances([.invariant, .invariant], for: pair)
        var type = types.intType
        for _ in 0..<28 {
            type = types.make(.classType(ClassType(classSymbol: pair,
                                                 args: [.invariant(type), .invariant(type)],
                                                 nullability: .nonNull)))
        }
        let diagnostics = DiagnosticEngine()
        TypeProjectionValidator(symbols: symbols, types: types, interner: interner,
                                diagnostics: diagnostics, range: nil).validate(type: type)
        #expect(!diagnostics.hasError)
    }

    @Test(arguments: [
        ("Carrier<Source<in Int>>", true),
        ("Carrier<Source<out Int>>", false),
        ("Projected<in Int>", true),
    ])
    func validatesSupertypesBeforeAliasProjectionMerging(supertype: String, rejects: Bool) throws {
        let diagnostics = try check("""
        interface Carrier<T>
        interface Source<out T>
        typealias Projected<T> = Carrier<out T>
        interface Subject : \(supertype)
        """)
        #expect(diagnostics.contains { $0.severity == .error } == rejects, "\(diagnostics)")
        if rejects {
            #expect(diagnostics.contains { $0.code == "KSWIFTK-SEMA-PROJECTION-CONFLICT" }, "\(diagnostics)")
        }
    }

    private func check(_ source: String) throws -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            diagnostics = context.diagnostics.diagnostics
        }
        return diagnostics
    }
}

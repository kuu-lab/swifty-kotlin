@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct NullableComparableSubtypeTests {
    @Test
    func builtinComparableSubtypingPreservesArgumentAndOuterNullability() {
        let types = TypeSystem()
        let comparable = SymbolID(rawValue: 0)
        types.comparableInterfaceSymbol = comparable
        let primitives: [PrimitiveType] = [
            .boolean, .char, .int, .long, .float, .double,
            .uint, .ulong, .ubyte, .ushort, .byte, .short,
        ]
        let builtins = primitives.map { types.make(.primitive($0, .nonNull)) } + [types.stringType]
        for builtin in builtins {
            let nullable = types.makeNullable(builtin)
            let wrongArgument = builtin == types.stringType ? types.intType : types.stringType
            let projections: [TypeArg] = [.invariant(builtin), .in(builtin), .star]
            for projection in projections {
                let nonNullComparable = types.make(.classType(ClassType(
                    classSymbol: comparable, args: [projection], nullability: .nonNull
                )))
                let nullableComparable = types.makeNullable(nonNullComparable)
                #expect(types.isSubtype(builtin, nonNullComparable))
                #expect(types.isSubtype(builtin, nullableComparable))
                #expect(types.isSubtype(nullable, nullableComparable))
                #expect(!types.isSubtype(nullable, nonNullComparable))
                #expect(types.isSubtype(types.nullableNothingType, nullableComparable))
            }
            for argument in [nullable, wrongArgument] {
                let projections: [TypeArg] = [.invariant(argument), .in(argument)]
                for projection in projections {
                    let target = types.make(.classType(ClassType(
                        classSymbol: comparable, args: [projection], nullability: .nullable
                    )))
                    #expect(!types.isSubtype(nullable, target))
                    #expect(!types.isSubtype(builtin, target))
                }
            }
        }
    }

    @Test
    func issueReproducerAndNullableBuiltinParametersAreAccepted() throws {
        let builtins = [
            "Boolean", "Char", "Int", "Long", "Float", "Double",
            "UInt", "ULong", "UByte", "UShort", "Byte", "Short", "String",
        ]
        let assignments = builtins.map { name in
            """
            fun accept\(name)(value: \(name)?) {
                val typed: Comparable<\(name)>? = value
                val projected: Comparable<in \(name)>? = value
                val star: Comparable<*>? = value
            }
            """
        }.joined(separator: "\n")
        let ctx = makeContextFromSource("""
        fun main() {
            val i: Int? = 3
            val c: Comparable<Int>? = i
            val s: String? = "x"
            val d: Comparable<in String>? = s
        }
        \(assignments)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun bad(value: Int?) { val result: Comparable<Int> = value }",
        "fun bad(value: String?) { val result: Comparable<in String> = value }",
        "fun bad(value: Int?) { val result: Comparable<Long>? = value }",
        "fun bad(value: String?) { val result: Comparable<in Int>? = value }",
        "fun bad(value: Int?) { val result: Comparable<Int?>? = value }",
        "fun bad(value: String?) { val result: Comparable<in String?>? = value }",
    ])
    func invalidComparableAssignmentsAreRejected(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "\(errors)")
        #expect(errors.first?.code == "KSWIFTK-SEMA-0468", "\(errors)")
    }
}

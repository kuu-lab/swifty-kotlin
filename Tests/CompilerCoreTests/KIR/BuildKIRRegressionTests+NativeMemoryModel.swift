#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func testNativeMemoryModelGeneratedEnumMembersKeepExactContract() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.MemoryModel

        fun main() {
            val entries = MemoryModel.entries
            val values = MemoryModel.values()
            val strict = MemoryModel.valueOf("STRICT")
            println(entries)
            println(values)
            println(strict)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let memoryModelFQName = [
                interner.intern("kotlin"),
                interner.intern("native"),
                interner.intern("MemoryModel"),
            ]
            let memoryModel = try #require(sema.symbols.lookup(fqName: memoryModelFQName))
            let memoryModelType = sema.types.make(.classType(ClassType(
                classSymbol: memoryModel,
                args: [],
                nullability: .nonNull
            )))

            let annotations = sema.symbols.annotations(for: memoryModel)
            #expect(annotations.contains {
                $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi"
            })
            #expect(annotations.contains {
                $0.annotationFQName == "kotlin.Deprecated"
                    && $0.arguments.contains {
                        $0.contains("MemoryModel.EXPERIMENTAL")
                    }
            })

            let values = try #require(
                sema.symbols.lookup(fqName: memoryModelFQName + [interner.intern("values")])
            )
            let valueOf = try #require(
                sema.symbols.lookup(fqName: memoryModelFQName + [interner.intern("valueOf")])
            )
            let entries = try #require(
                sema.symbols.lookup(fqName: memoryModelFQName + [interner.intern("entries")])
            )
            let valuesSignature = try #require(sema.symbols.functionSignature(for: values))
            let valueOfSignature = try #require(sema.symbols.functionSignature(for: valueOf))

            #expect(sema.symbols.symbol(values)?.flags.contains(.static) == true)
            #expect(sema.symbols.symbol(valueOf)?.flags.contains(.static) == true)
            #expect(sema.symbols.symbol(entries)?.flags.contains(.static) == true)
            #expect(valuesSignature.receiverType == nil)
            #expect(valuesSignature.parameterTypes.isEmpty)
            #expect(valueOfSignature.receiverType == nil)
            #expect(valueOfSignature.parameterTypes == [sema.types.stringType])
            #expect(valueOfSignature.returnType == memoryModelType)

            try LoweringPhase().run(ctx)
            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: interner)
            let mainCallees = extractCallees(from: mainBody, interner: interner)
            #expect(mainCallees.contains("entries$get"))
            #expect(mainCallees.contains("values"))
            #expect(mainCallees.contains("valueOf"))
            #expect(!mainCallees.contains(where: { $0.hasPrefix("$enumConstructorProperty$") }))

            let valuesBody = try findKIRFunctionBody(named: "values", in: module, interner: interner)
            #expect(extractCallees(from: valuesBody, interner: interner).contains("kk_enum_make_values_array"))

            let entriesBody = try findKIRFunctionBody(named: "entries$get", in: module, interner: interner)
            #expect(extractCallees(from: entriesBody, interner: interner).contains("kk_enum_make_entries_list"))

            let valueOfFunction = try findKIRFunction(named: "valueOf", in: module, interner: interner)
            #expect(valueOfFunction.params.count == 1)
            #expect(extractCallees(from: valueOfFunction.body, interner: interner).contains("kk_string_equals_flat"))
        }
    }
}
#endif

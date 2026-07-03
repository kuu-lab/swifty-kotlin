@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-003: Validates `append` on StringBuilder and Appendable.
@Suite
struct StringAppendFunctionTests {
    @Test func testStringBuilderTypedAppendOverloadsResolveAndLink() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val sb = StringBuilder()
            val anyValue: Any? = 42
            val nullableString: String? = null
            sb.append(anyValue)
            sb.append(nullableString)
            sb.append('x')
            sb.append(true)
            sb.append(1)
            sb.append(2L)
            sb.append(3.5f)
            sb.append(4.5)
        }
        """)

        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected append overloads to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let interner = ctx.interner
        let sema = try #require(ctx.sema)
        let appendSymbols = sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("StringBuilder"),
            interner.intern("append"),
        ])

        let objectLikeTypes = [
            sema.types.nullableAnyType,
            sema.types.makeNullable(sema.types.stringType),
        ]
        for parameterType in objectLikeTypes {
            let overload = appendSymbols.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return signature.parameterTypes == [parameterType]
            }
            #expect(overload != nil, "Expected StringBuilder.append overload for \(parameterType)")
            if let overload {
                #expect(sema.symbols.externalLinkName(for: overload) != nil)
            }
        }

        let expectedLinks: [TypeID: String] = [
            sema.types.charType: "kk_string_builder_append_char",
            sema.types.booleanType: "kk_string_builder_append_bool",
            sema.types.intType: "kk_string_builder_append_obj",
            sema.types.longType: "kk_string_builder_append_obj",
            sema.types.floatType: "kk_string_builder_append_float",
            sema.types.doubleType: "kk_string_builder_append_double",
        ]

        for (parameterType, expectedLink) in expectedLinks {
            let overload = appendSymbols.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return signature.parameterTypes == [parameterType]
            }
            #expect(overload != nil, "Expected StringBuilder.append overload for \(parameterType)")
            if let overload {
                #expect(sema.symbols.externalLinkName(for: overload) == expectedLink)
            }
        }
    }

    @Test func testAppendableAppendOverloadsResolveAndLink() throws {
        let ctx = makeContextFromSource("""
        import kotlin.text.Appendable

        fun appendPieces(target: Appendable): Appendable {
            target.append('a')
            target.append("bc")
            return target.append("def", 1, 3)
        }
        """)

        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Appendable.append overloads to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let interner = ctx.interner
        let sema = try #require(ctx.sema)
        let appendSymbols = sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("Appendable"),
            interner.intern("append"),
        ])

        #expect(
            appendSymbols.contains { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return signature.parameterTypes == [sema.types.charType]
                    && sema.symbols.externalLinkName(for: symbolID) == "kk_string_builder_append_char"
            },
            "Expected Appendable.append(Char) to link to kk_string_builder_append_char"
        )
        #expect(
            appendSymbols.contains { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return signature.parameterTypes.count == 1
                    && sema.symbols.externalLinkName(for: symbolID) == "kk_string_builder_append_obj"
            },
            "Expected Appendable.append(CharSequence?) to link to kk_string_builder_append_obj"
        )
        #expect(
            appendSymbols.contains { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return signature.parameterTypes.count == 3
                    && sema.symbols.externalLinkName(for: symbolID) == "kk_string_builder_appendRange_obj_flat"
            },
            "Expected Appendable.append(CharSequence?, Int, Int) to link to kk_string_builder_appendRange_obj_flat"
        )
    }
}

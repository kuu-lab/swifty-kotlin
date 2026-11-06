@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct JavaCharacterTests {
    @Test(arguments: ["", "import java.lang.Character", "import java.lang.Character as C"])
    func sourceBackedSignatures(importLine: String) throws {
        let name = importLine.hasSuffix(" as C") ? "C" : "Character"
        let source = """
        \(importLine)
        fun count(cp: Int): Int = \(name).charCount(cp)
        fun space(cp: Int): Boolean = \(name).isSpaceChar(cp)
        fun category(cp: Int): Int = \(name).getType(cp)
        fun mark(): Byte = \(name).NON_SPACING_MARK
        fun enclosing(): Byte = \(name).ENCLOSING_MARK
        fun format(): Byte = \(name).FORMAT
        fun bytes(): Int = \(name).BYTES
        fun size(): Int = \(name).SIZE
        fun minValue(): Char = \(name).MIN_VALUE
        fun maxValue(): Char = \(name).MAX_VALUE
        fun minSurrogate(): Char = \(name).MIN_SURROGATE
        fun maxCodePoint(): Int = \(name).MAX_CODE_POINT
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], allowDefaultStdlibLibrary: false)
            try runFrontend(context)
            try DataFlowSemaPhase().run(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let sema = try #require(context.sema)
            let ownerPath = ["java", "lang", "Character"].map(context.interner.intern)
            let owner = try #require(sema.symbols.lookup(fqName: ownerPath))
            #expect(sema.symbols.symbol(owner)?.kind == .object)
            #expect(sema.symbols.symbol(owner)?.flags.contains(.synthetic) == false)
            for (method, result) in [("charCount", sema.types.intType),
                                     ("isSpaceChar", sema.types.booleanType),
                                     ("getType", sema.types.intType)] {
                let symbol = try #require(sema.symbols.lookup(fqName: ownerPath + [context.interner.intern(method)]))
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                #expect(signature.parameterTypes == [sema.types.intType])
                #expect(signature.returnType == result)
            }
            for (constant, type) in [
                ("NON_SPACING_MARK", sema.types.byteType), ("ENCLOSING_MARK", sema.types.byteType),
                ("FORMAT", sema.types.byteType),
                ("BYTES", sema.types.intType), ("SIZE", sema.types.intType),
                ("MIN_VALUE", sema.types.charType), ("MAX_VALUE", sema.types.charType),
                ("MIN_HIGH_SURROGATE", sema.types.charType), ("MAX_HIGH_SURROGATE", sema.types.charType),
                ("MIN_LOW_SURROGATE", sema.types.charType), ("MAX_LOW_SURROGATE", sema.types.charType),
                ("MIN_SURROGATE", sema.types.charType), ("MAX_SURROGATE", sema.types.charType),
                ("MIN_RADIX", sema.types.intType), ("MAX_RADIX", sema.types.intType),
                ("MIN_SUPPLEMENTARY_CODE_POINT", sema.types.intType), ("MIN_CODE_POINT", sema.types.intType),
                ("MAX_CODE_POINT", sema.types.intType),
            ] {
                let symbol = try #require(sema.symbols.lookup(fqName: ownerPath + [context.interner.intern(constant)]))
                #expect(sema.symbols.propertyType(for: symbol) == type)
            }
        }
    }
}

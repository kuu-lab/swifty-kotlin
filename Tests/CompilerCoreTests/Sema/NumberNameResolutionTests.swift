@testable import CompilerCore
import Testing
import TestStdlibCache

@Suite
struct NumberNameResolutionTests {
    @Test(arguments: [false, true], ["", "package counters"])
    func operatorsReturnTheirOwnNumber(useArtifact: Bool, packageDecl: String) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        try withTemporaryFiles(contents: ["""
        \(packageDecl)
        class Number(val n: Int) {
            operator fun plus(x: Int): Number = Number(n + x)
            operator fun inc(): Number = Number(n + 1)
        }
        fun main() {
            var n = Number(10)
            n += 5
            n++
            println(n.n)
        }
        """]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: useArtifact ? .executable : .kirDump,
                allowDefaultStdlibLibrary: useArtifact
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let ownerPath = packageDecl.isEmpty ? ["Number"] : ["counters", "Number"]
            let owner = try #require(sema.symbols.lookup(fqName: ownerPath.map(ctx.interner.intern)))
            for name in ["plus", "inc"] {
                let method = try #require(sema.symbols.lookup(fqName: (ownerPath + [name]).map(ctx.interner.intern)))
                let signature = try #require(sema.symbols.functionSignature(for: method))
                #expect(signature.returnType == sema.types.make(.classType(ClassType(classSymbol: owner))))
            }
        }
    }

    @Test(arguments: [false, true], ["import models.Number", "import models.*", "import models.Number as Count"])
    func importedNumberResolvesInSignaturesAndExpressions(useArtifact: Bool, importDecl: String) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let name = importDecl.hasSuffix("Count") ? "Count" : "Number"
        try withTemporaryFiles(contents: [
            "package models; class Number(val n: Int)",
            """
            package use
            \(importDecl)
            fun make(): \(name) = \(name)(10)
            fun copy(value: \(name)?): \(name)? {
                val result: \(name)? = value
                return result
            }
            fun qualified(): models.Number = models.Number(20)
            fun <Number> identity(value: Number): Number = value
            fun narrowed(value: Any): Int {
                if (value is \(name)) return value.n
                return 0
            }
            """,
        ]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: useArtifact ? .executable : .kirDump,
                allowDefaultStdlibLibrary: useArtifact
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let owner = try #require(sema.symbols.lookup(fqName: ["models", "Number"].map(ctx.interner.intern)))
            for function in ["make", "qualified", "copy"] {
                let symbol = try #require(sema.symbols.lookup(fqName: ["use", function].map(ctx.interner.intern)))
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                let expected = sema.types.make(.classType(ClassType(
                    classSymbol: owner,
                    nullability: function == "copy" ? .nullable : .nonNull
                )))
                #expect(signature.returnType == expected)
            }
        }
    }

    @Test(arguments: [false, true])
    func defaultNumberRemainsKotlinNumberOutsideTheRootPackage(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        try withTemporaryFiles(contents: [
            "class Number(val n: Int)",
            """
            package numeric
            fun defaultNumber(value: Number?): Number? = value
            fun qualifiedNumber(value: kotlin.Number): kotlin.Number = value
            fun <T : Number> bounded(value: T): T = value
            fun narrowed(value: Any): Int {
                if (value is Number) return value.toInt()
                return 0
            }
            fun whenNumber(value: Any): Int = when (value) {
                is Number -> value.toInt()
                else -> 0
            }
            fun main() { println(qualifiedNumber(10).toInt()) }
            """,
        ]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: useArtifact ? .executable : .kirDump,
                allowDefaultStdlibLibrary: useArtifact
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let owner = try #require(sema.types.numberClassSymbol)
            for function in ["defaultNumber", "qualifiedNumber"] {
                let symbol = try #require(sema.symbols.lookup(fqName: ["numeric", function].map(ctx.interner.intern)))
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                #expect(signature.returnType == sema.types.make(.classType(ClassType(
                    classSymbol: owner,
                    nullability: function == "defaultNumber" ? .nullable : .nonNull
                ))))
            }
        }
    }
}

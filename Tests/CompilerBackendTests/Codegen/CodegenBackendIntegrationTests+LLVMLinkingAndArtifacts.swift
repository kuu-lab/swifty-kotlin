@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testLLVMBackendCanLinkAndRunExecutable() throws {
        let source = "fun main() = 0"
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let options = CompilerOptions(
                moduleName: "LLVMExe",
                inputs: [path],
                outputPath: outputPath,
                emit: .executable,
                target: defaultTargetTriple()
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )

            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            XCTAssertEqual(result.exitCode, 0)
        }
    }

    func testLLVMBackendLowersStringLengthToAggregateFieldExtract() throws {
        let source = """
        fun lengthOf(value: String): Int {
            return value.length
        }

        fun main() {
            println(lengthOf("hello"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let llvmBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let llvmCtx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringLengthIR",
                emit: .llvmIR,
                outputPath: llvmBase
            )
            let llvmPath = try XCTUnwrap(llvmCtx.generatedLLVMIRPath)
            let ir = try String(contentsOfFile: llvmPath, encoding: .utf8)

            XCTAssertTrue(ir.contains("extractvalue"), "String.length should read the aggregate length field")
            XCTAssertFalse(ir.contains("@kk_string_struct_get_length"))
            XCTAssertFalse(ir.contains("@__string_struct_get_length"))
        }
    }

    func testLLVMBackendLowersStringLengthInLambdasToAggregateFieldExtract() throws {
        let source = """
        fun main() {
            println(listOf("a", "bb").map { it.length })
            println("hello".run { length })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let llvmBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let llvmCtx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringLengthLambdaIR",
                emit: .llvmIR,
                outputPath: llvmBase
            )
            let llvmPath = try XCTUnwrap(llvmCtx.generatedLLVMIRPath)
            let ir = try String(contentsOfFile: llvmPath, encoding: .utf8)

            XCTAssertTrue(ir.contains("extractvalue"), "String.length in lambdas should read the aggregate length field")
            XCTAssertFalse(ir.contains("@kk_string_struct_get_length"))
            XCTAssertFalse(ir.contains("@__string_struct_get_length"))
        }
    }

    func testLLVMBackendLowersStringLengthRuntimePrimitiveToAggregateFieldExtract() throws {
        let source = """
        import kswiftk.internal.__string_struct_get_length

        fun lengthViaPrimitive(value: String): Int {
            return __string_struct_get_length(value)
        }

        fun main() {
            println(lengthViaPrimitive("hello"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let llvmBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let llvmCtx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringLengthPrimitiveIR",
                emit: .llvmIR,
                outputPath: llvmBase
            )
            let llvmPath = try XCTUnwrap(llvmCtx.generatedLLVMIRPath)
            let ir = try String(contentsOfFile: llvmPath, encoding: .utf8)

            XCTAssertTrue(ir.contains("extractvalue"), "String length primitive should read the aggregate length field")
            XCTAssertFalse(ir.contains("@kk_string_struct_get_length"))
            XCTAssertFalse(ir.contains("@__string_struct_get_length"))
        }
    }

    func testLLVMBackendOmitsStringLengthPrimitiveForLiteralNullSafeCall() throws {
        let source = """
        fun main() {
            val value: String? = null
            println(value?.length)
            println(value?.length ?: -1)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let llvmBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let llvmCtx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "NullSafeStringLengthIR",
                emit: .llvmIR,
                outputPath: llvmBase
            )
            let llvmPath = try XCTUnwrap(llvmCtx.generatedLLVMIRPath)
            let ir = try String(contentsOfFile: llvmPath, encoding: .utf8)

            XCTAssertFalse(ir.contains("@kk_string_struct_get_length"))
            XCTAssertFalse(ir.contains("@__string_struct_get_length"))
        }
    }

    func testLLVMBackendBridgesReflectedStringVirtualDispatchReturn() throws {
        let source = """
        interface Face {
            fun label(): String
        }

        class Impl : Face {
            override fun label(): String = "ok"
        }

        fun makeFace(): Face = Impl()

        fun main() {
            println(makeFace().label())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let llvmBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let llvmCtx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringVirtualDispatchIR",
                emit: .llvmIR,
                outputPath: llvmBase
            )
            let llvmPath = try XCTUnwrap(llvmCtx.generatedLLVMIRPath)
            let ir = try String(contentsOfFile: llvmPath, encoding: .utf8)

            XCTAssertTrue(
                ir.contains("call i64 %lookup_fptr_"),
                "String virtual dispatch should call reflected implementations with raw callback ABI"
            )
            XCTAssertTrue(
                ir.contains("virtual_callback_result"),
                "Raw String virtual dispatch results should be bridged back to flat String ABI"
            )
            XCTAssertFalse(
                ir.contains("call { ptr, i64, i64, i64 } %lookup_fptr_"),
                "Interface dispatch must not expect a flat String return from a raw callback implementation"
            )
        }
    }

    func testLLVMBackendBridgesRawAnyStringLengthAfterTypeCheck() throws {
        let source = """
        fun lengthIfString(value: Any): Int {
            if (value !is String) {
                return -1
            } else {
                return value.length
            }
        }

        fun main() {
            println(lengthIfString("abc"))
            println(lengthIfString(0))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let llvmBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let llvmCtx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "AnySmartCastStringLengthIR",
                emit: .llvmIR,
                outputPath: llvmBase
            )
            let llvmPath = try XCTUnwrap(llvmCtx.generatedLLVMIRPath)
            let ir = try String(contentsOfFile: llvmPath, encoding: .utf8)

            XCTAssertTrue(ir.contains("@kk_string_to_flat"))
            XCTAssertFalse(ir.contains("@kk_string_struct_get_length"))
            XCTAssertFalse(ir.contains("@__string_struct_get_length"))
        }
    }

    func testLLVMBackendEmitsFlatRemovePrefixSuffixRuntimeCallsForStringOverloads() throws {
        let source = """
        fun main() {
            val value = "foo-body-bar"
            println(value.removePrefix("foo-"))
            println(value.removeSuffix("-bar"))
            println(value.removeSurrounding("foo-"))
            println(value.removeSurrounding("foo-", "-bar"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let llvmBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let llvmCtx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringRemoveFlatIR",
                emit: .llvmIR,
                outputPath: llvmBase
            )
            let llvmPath = try XCTUnwrap(llvmCtx.generatedLLVMIRPath)
            let ir = try String(contentsOfFile: llvmPath, encoding: .utf8)

            let rawNames = [
                "kk_string_removePrefix",
                "kk_string_removeSuffix",
                "kk_string_removeSurrounding",
                "kk_string_removeSurrounding_pair",
            ]
            for rawName in rawNames {
                XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected raw String remove call: \(rawName)")
                XCTAssertTrue(ir.contains("@\(rawName)_flat"), "Missing flat String remove call: \(rawName)_flat")
            }
        }
    }

    func testLLVMBackendEmitsFlatReplaceFirstRangeRuntimeCallsForStringOverloads() throws {
        let source = """
        fun main() {
            val value = "abcabc"
            println(value.replaceFirst("ab", "XY"))
            println(value.replaceRange(1..3, "Q"))
            println(value.removeRange(1, 3))
            println(value.removeRange(1..2))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let llvmBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let llvmCtx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringReplaceRangeFlatIR",
                emit: .llvmIR,
                outputPath: llvmBase
            )
            let llvmPath = try XCTUnwrap(llvmCtx.generatedLLVMIRPath)
            let ir = try String(contentsOfFile: llvmPath, encoding: .utf8)

            let rawNames = [
                "kk_string_replaceFirst",
                "kk_string_replaceRange",
                "kk_string_removeRange",
                "kk_string_removeRange_range",
            ]
            for rawName in rawNames {
                XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected raw String range call: \(rawName)")
                XCTAssertTrue(ir.contains("@\(rawName)_flat"), "Missing flat String range call: \(rawName)_flat")
            }
        }
    }

    func testLLVMBackendEmitsFlatReplaceCharIgnoreCaseRuntimeCallsForStringOverloads() throws {
        let source = """
        fun main() {
            println("hello world".replace('l', 'r'))
            println("Hello World".replace("hello", "Hi", ignoreCase = true))
            println("Hello World".replace('h', 'J', ignoreCase = true))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let llvmBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let llvmCtx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringReplaceCharIgnoreCaseFlatIR",
                emit: .llvmIR,
                outputPath: llvmBase
            )
            let llvmPath = try XCTUnwrap(llvmCtx.generatedLLVMIRPath)
            let ir = try String(contentsOfFile: llvmPath, encoding: .utf8)

            let rawNames = [
                "kk_string_replace_char",
                "kk_string_replace_ignoreCase",
                "kk_string_replace_char_ignoreCase",
            ]
            for rawName in rawNames {
                XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected raw String replace call: \(rawName)")
                XCTAssertTrue(ir.contains("@\(rawName)_flat"), "Missing flat String replace call: \(rawName)_flat")
            }
        }
    }

    func testLLVMBackendEmitsFlatIfBlankEmptyRuntimeCallsForStringOverloads() throws {
        let source = """
        fun main() {
            val blank = "   "
            val empty = ""
            println(blank.ifBlank { "fallback" })
            println(empty.ifEmpty { "fallback" })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let llvmBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let llvmCtx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringIfBlankEmptyFlatIR",
                emit: .llvmIR,
                outputPath: llvmBase
            )
            let llvmPath = try XCTUnwrap(llvmCtx.generatedLLVMIRPath)
            let ir = try String(contentsOfFile: llvmPath, encoding: .utf8)

            XCTAssertFalse(ir.contains("@kk_string_ifBlank("), "Unexpected raw String ifBlank call")
            XCTAssertFalse(ir.contains("@kk_string_ifEmpty("), "Unexpected raw String ifEmpty call")
            XCTAssertTrue(ir.contains("@kk_string_ifBlank_flat"), "Missing flat String ifBlank call")
            XCTAssertTrue(ir.contains("@kk_string_ifEmpty_flat"), "Missing flat String ifEmpty call")
        }
    }

    func testLLVMBackendEmitsFlatReplaceFirstCharRuntimeCallForStringOverload() throws {
        let source = """
        fun main() {
            println("alpha".replaceFirstChar { 'A' })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let llvmBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let llvmCtx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringReplaceFirstCharFlatIR",
                emit: .llvmIR,
                outputPath: llvmBase
            )
            let llvmPath = try XCTUnwrap(llvmCtx.generatedLLVMIRPath)
            let ir = try String(contentsOfFile: llvmPath, encoding: .utf8)

            XCTAssertFalse(ir.contains("@kk_string_replaceFirstChar("), "Unexpected raw replaceFirstChar call")
            XCTAssertTrue(ir.contains("@kk_string_replaceFirstChar_flat"), "Missing flat replaceFirstChar call")
        }
    }

    func testLLVMBackendDoesNotEmitCommonPrefixSuffixRuntimeCallsForSourceBackedOverloads() throws {
        let source = """
        fun main() {
            println("alphabet".commonPrefixWith("alpine"))
            println("alphabet".commonSuffixWith("bet"))
            println("AbCd".commonPrefixWith("abzz", true))
            println("AbCd".commonSuffixWith("xxCD", true))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let llvmBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let llvmCtx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringCommonPrefixSuffixFlatIR",
                emit: .llvmIR,
                outputPath: llvmBase
            )
            let llvmPath = try XCTUnwrap(llvmCtx.generatedLLVMIRPath)
            let ir = try String(contentsOfFile: llvmPath, encoding: .utf8)

            XCTAssertFalse(ir.contains("@kk_string_commonPrefixWith("), "Unexpected raw commonPrefixWith call")
            XCTAssertFalse(ir.contains("@kk_string_commonSuffixWith("), "Unexpected raw commonSuffixWith call")
            XCTAssertFalse(
                ir.contains("@kk_string_commonPrefixWith_ignoreCase("),
                "Unexpected raw commonPrefixWith(ignoreCase) call"
            )
            XCTAssertFalse(
                ir.contains("@kk_string_commonSuffixWith_ignoreCase("),
                "Unexpected raw commonSuffixWith(ignoreCase) call"
            )
            XCTAssertFalse(ir.contains("@kk_string_commonPrefixWith_flat"), "Unexpected flat commonPrefixWith call")
            XCTAssertFalse(ir.contains("@kk_string_commonSuffixWith_flat"), "Unexpected flat commonSuffixWith call")
            XCTAssertFalse(
                ir.contains("@kk_string_commonPrefixWith_ignoreCase_flat"),
                "Unexpected flat commonPrefixWith(ignoreCase) call"
            )
            XCTAssertFalse(
                ir.contains("@kk_string_commonSuffixWith_ignoreCase_flat"),
                "Unexpected flat commonSuffixWith(ignoreCase) call"
            )
        }
    }

    func testLLVMBackendEmitsFlatFormatRuntimeCallsForStringOverloads() throws {
        let source = """
        import java.util.Locale

        fun main() {
            println("%s:%d".format("age", 7))
            println(String.format("%.1f", 3.5))
            println(String.format(Locale("de", "DE"), "%.1f", 3.5))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let llvmBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let llvmCtx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringFormatFlatIR",
                emit: .llvmIR,
                outputPath: llvmBase
            )
            let llvmPath = try XCTUnwrap(llvmCtx.generatedLLVMIRPath)
            let ir = try String(contentsOfFile: llvmPath, encoding: .utf8)

            XCTAssertFalse(ir.contains("@kk_string_format("), "Unexpected raw String format call")
            XCTAssertFalse(ir.contains("@kk_string_format_locale("), "Unexpected raw String format(locale) call")
            XCTAssertTrue(ir.contains("@kk_string_format_flat"), "Missing flat String format call")
            XCTAssertTrue(ir.contains("@kk_string_format_locale_flat"), "Missing flat String format(locale) call")
        }
    }

    func testLLVMBackendEmitsFlatIndentRuntimeCallsForStringOverloads() throws {
        let source = """
        fun main() {
            val value = "  alpha\\n  beta"
            val margin = "|alpha\\n|beta"
            println(value.trimIndent())
            println(margin.trimMargin())
            println(margin.trimMargin("|"))
            println(value.prependIndent())
            println(value.prependIndent(">>"))
            println(value.replaceIndent())
            println(value.replaceIndent("  "))
            println(margin.replaceIndentByMargin())
            println(margin.replaceIndentByMargin(">"))
            println(margin.replaceIndentByMargin(">", "|"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let llvmBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let llvmCtx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringIndentFlatIR",
                emit: .llvmIR,
                outputPath: llvmBase
            )
            let llvmPath = try XCTUnwrap(llvmCtx.generatedLLVMIRPath)
            let ir = try String(contentsOfFile: llvmPath, encoding: .utf8)

            let rawNames = [
                "kk_string_trimIndent",
                "kk_string_trimMargin_default",
                "kk_string_trimMargin",
                "kk_string_prependIndent_default",
                "kk_string_prependIndent",
                "kk_string_replaceIndent_default",
                "kk_string_replaceIndent",
                "kk_string_replaceIndentByMargin",
            ]
            for rawName in rawNames {
                XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected raw String indent call: \(rawName)")
            }

            let flatNames = [
                "kk_string_trimIndent_flat",
                "kk_string_trimMargin_default_flat",
                "kk_string_trimMargin_flat",
                "kk_string_prependIndent_default_flat",
                "kk_string_prependIndent_flat",
                "kk_string_replaceIndent_default_flat",
                "kk_string_replaceIndent_flat",
                "kk_string_replaceIndentByMargin_flat",
            ]
            for flatName in flatNames {
                XCTAssertTrue(ir.contains("@\(flatName)"), "Missing flat String indent call: \(flatName)")
            }
        }
    }

    func testLLVMBackendEmitsFlatTrimPredicateRuntimeCallsForStringOverloads() throws {
        let source = """
        fun main() {
            val value = "xxbodyxx"
            println(value.trim { it == 'x' })
            println(value.trimStart { it == 'x' })
            println(value.trimEnd { it == 'x' })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let llvmBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let llvmCtx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringTrimPredicateFlatIR",
                emit: .llvmIR,
                outputPath: llvmBase
            )
            let llvmPath = try XCTUnwrap(llvmCtx.generatedLLVMIRPath)
            let ir = try String(contentsOfFile: llvmPath, encoding: .utf8)

            let rawNames = [
                "kk_string_trim_predicate",
                "kk_string_trimStart_predicate",
                "kk_string_trimEnd_predicate",
            ]
            for rawName in rawNames {
                XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected raw String trim predicate call: \(rawName)")
                XCTAssertTrue(ir.contains("@\(rawName)_flat"), "Missing flat String trim predicate call: \(rawName)_flat")
            }
        }
    }

    func testLLVMBackendEmitsRuntimeStringAndCoroutineHelpersInLLVMIR() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()
        let nullableStringType = types.makeNullable(types.stringType)

        let left = interner.intern("left")
        let right = interner.intern("right")
        let padded = interner.intern("  padded  ")
        let needle = interner.intern("pad")

        let leftExpr = arena.appendExpr(.stringLiteral(left), type: types.stringType)
        let rightExpr = arena.appendExpr(.stringLiteral(right), type: types.stringType)
        let concatResult = arena.appendExpr(.temporary(0), type: types.stringType)
        let paddedExpr = arena.appendExpr(.stringLiteral(padded), type: types.stringType)
        let trimResult = arena.appendExpr(.temporary(12), type: types.stringType)
        let trimStartResult = arena.appendExpr(.temporary(28), type: types.stringType)
        let trimEndResult = arena.appendExpr(.temporary(29), type: types.stringType)
        let lowercaseResult = arena.appendExpr(.temporary(31), type: types.stringType)
        let uppercaseResult = arena.appendExpr(.temporary(32), type: types.stringType)
        let reversedResult = arena.appendExpr(.temporary(33), type: types.stringType)
        let repeatResult = arena.appendExpr(.temporary(43), type: types.stringType)
        let repeatThrown = arena.appendExpr(.temporary(44), type: types.intType)
        let substringStart = arena.appendExpr(.intLiteral(1), type: types.intType)
        let substringEnd = arena.appendExpr(.intLiteral(3), type: types.intType)
        let substringHasEnd = arena.appendExpr(.intLiteral(1), type: types.intType)
        let substringResult = arena.appendExpr(.temporary(34), type: types.stringType)
        let substringThrown = arena.appendExpr(.temporary(35), type: types.intType)
        let subSequenceResult = arena.appendExpr(.temporary(45), type: types.stringType)
        let subSequenceThrown = arena.appendExpr(.temporary(46), type: types.intType)
        let takeCount = arena.appendExpr(.intLiteral(3), type: types.intType)
        let takeResult = arena.appendExpr(.temporary(13), type: types.stringType)
        let takeThrown = arena.appendExpr(.temporary(14), type: types.intType)
        let takeLastResult = arena.appendExpr(.temporary(36), type: types.stringType)
        let takeLastThrown = arena.appendExpr(.temporary(37), type: types.intType)
        let dropResult = arena.appendExpr(.temporary(38), type: types.stringType)
        let dropThrown = arena.appendExpr(.temporary(39), type: types.intType)
        let dropLastResult = arena.appendExpr(.temporary(40), type: types.stringType)
        let dropLastThrown = arena.appendExpr(.temporary(41), type: types.intType)
        let hofFnPtr = arena.appendExpr(.intLiteral(0), type: types.intType)
        let hofClosureRaw = arena.appendExpr(.intLiteral(0), type: types.intType)
        let filterResult = arena.appendExpr(.temporary(47), type: types.stringType)
        let filterThrown = arena.appendExpr(.temporary(48), type: types.intType)
        let filterIndexedResult = arena.appendExpr(.temporary(49), type: types.stringType)
        let filterIndexedThrown = arena.appendExpr(.temporary(50), type: types.intType)
        let filterNotResult = arena.appendExpr(.temporary(51), type: types.stringType)
        let filterNotThrown = arena.appendExpr(.temporary(52), type: types.intType)
        let takeWhileResult = arena.appendExpr(.temporary(53), type: types.stringType)
        let takeWhileThrown = arena.appendExpr(.temporary(54), type: types.intType)
        let takeLastWhileResult = arena.appendExpr(.temporary(55), type: types.stringType)
        let takeLastWhileThrown = arena.appendExpr(.temporary(56), type: types.intType)
        let dropWhileResult = arena.appendExpr(.temporary(57), type: types.stringType)
        let dropWhileThrown = arena.appendExpr(.temporary(58), type: types.intType)
        let needleExpr = arena.appendExpr(.stringLiteral(needle), type: types.stringType)
        let startsWithResult = arena.appendExpr(.temporary(15), type: types.booleanType)
        let containsResult = arena.appendExpr(.temporary(16), type: types.booleanType)
        let indexOfResult = arena.appendExpr(.temporary(17), type: types.intType)
        let isBlankResult = arena.appendExpr(.temporary(18), type: types.booleanType)
        let ignoreCaseTrue = arena.appendExpr(.boolLiteral(true), type: types.booleanType)
        let charNeedle = arena.appendExpr(.charLiteral(UInt32(UnicodeScalar("d").value)), type: types.charType)
        let compareIgnoreCaseResult = arena.appendExpr(.temporary(19), type: types.intType)
        let compareLocaleResult = arena.appendExpr(.temporary(30), type: types.intType)
        let localeRaw = arena.appendExpr(.intLiteral(0), type: types.intType)
        let lastIndexIgnoreCaseResult = arena.appendExpr(.temporary(20), type: types.intType)
        let indexOfCharResult = arena.appendExpr(.temporary(21), type: types.intType)
        let lastIndexOfCharResult = arena.appendExpr(.temporary(22), type: types.intType)
        let nullStringExpr = arena.appendExpr(.null, type: nullableStringType)
        let isNullOrEmptyResult = arena.appendExpr(.temporary(23), type: types.booleanType)
        let isNullOrBlankResult = arena.appendExpr(.temporary(24), type: types.booleanType)
        let contentEqualsResult = arena.appendExpr(.temporary(25), type: types.booleanType)
        let contentEqualsIgnoreCaseResult = arena.appendExpr(.temporary(26), type: types.booleanType)
        let equalsIgnoreCaseResult = arena.appendExpr(.temporary(27), type: types.booleanType)
        let equalsResult = arena.appendExpr(.temporary(42), type: types.booleanType)
        let suspendedResult = arena.appendExpr(.temporary(1), type: types.anyType)
        let labelValue = arena.appendExpr(.intLiteral(7), type: types.intType)
        let labelResult = arena.appendExpr(.temporary(2), type: types.intType)
        let spillSlotValue = arena.appendExpr(.intLiteral(0), type: types.intType)
        let spillStored = arena.appendExpr(.temporary(3), type: types.intType)
        let spillLoaded = arena.appendExpr(.temporary(4), type: types.intType)
        let completionStored = arena.appendExpr(.temporary(5), type: types.intType)
        let completionLoaded = arena.appendExpr(.temporary(6), type: types.intType)
        let throwingResult = arena.appendExpr(.temporary(7), type: types.intType)
        let whenCondition = arena.appendExpr(.boolLiteral(true), type: types.booleanType)
        let whenResult = arena.appendExpr(.temporary(8), type: types.intType)
        let falseConst = arena.appendExpr(.boolLiteral(false), type: types.booleanType)
        let continuationResult = arena.appendExpr(.temporary(10), type: types.anyType)
        let stateExitResult = arena.appendExpr(.temporary(11), type: types.intType)

        let main = KIRFunction(
            symbol: SymbolID(rawValue: 1200),
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .constValue(result: leftExpr, value: .stringLiteral(left)),
                .constValue(result: rightExpr, value: .stringLiteral(right)),
                .call(symbol: nil, callee: interner.intern("kk_string_concat_flat"), arguments: [leftExpr, rightExpr], result: concatResult, canThrow: false, thrownResult: nil),
                .constValue(result: paddedExpr, value: .stringLiteral(padded)),
                .call(symbol: nil, callee: interner.intern("kk_string_trim_flat"), arguments: [paddedExpr], result: trimResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_trimStart_flat"), arguments: [paddedExpr], result: trimStartResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_trimEnd_flat"), arguments: [paddedExpr], result: trimEndResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_lowercase_flat"), arguments: [paddedExpr], result: lowercaseResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_uppercase_flat"), arguments: [paddedExpr], result: uppercaseResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_reversed_flat"), arguments: [paddedExpr], result: reversedResult, canThrow: false, thrownResult: nil),
                .constValue(result: substringStart, value: .intLiteral(1)),
                .constValue(result: substringEnd, value: .intLiteral(3)),
                .constValue(result: substringHasEnd, value: .intLiteral(1)),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_string_substring_flat"),
                    arguments: [trimResult, substringStart, substringEnd, substringHasEnd],
                    result: substringResult,
                    canThrow: true,
                    thrownResult: substringThrown
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_string_subSequence_flat"),
                    arguments: [trimResult, substringStart, substringEnd],
                    result: subSequenceResult,
                    canThrow: true,
                    thrownResult: subSequenceThrown
                ),
                .constValue(result: takeCount, value: .intLiteral(3)),
                .call(symbol: nil, callee: interner.intern("kk_string_take_flat"), arguments: [trimResult, takeCount], result: takeResult, canThrow: true, thrownResult: takeThrown),
                .call(symbol: nil, callee: interner.intern("kk_string_repeat_flat"), arguments: [trimResult, takeCount], result: repeatResult, canThrow: true, thrownResult: repeatThrown),
                .call(symbol: nil, callee: interner.intern("kk_string_takeLast_flat"), arguments: [trimResult, takeCount], result: takeLastResult, canThrow: true, thrownResult: takeLastThrown),
                .call(symbol: nil, callee: interner.intern("kk_string_drop_flat"), arguments: [trimResult, takeCount], result: dropResult, canThrow: true, thrownResult: dropThrown),
                .call(symbol: nil, callee: interner.intern("kk_string_dropLast_flat"), arguments: [trimResult, takeCount], result: dropLastResult, canThrow: true, thrownResult: dropLastThrown),
                .constValue(result: hofFnPtr, value: .intLiteral(0)),
                .constValue(result: hofClosureRaw, value: .intLiteral(0)),
                .call(symbol: nil, callee: interner.intern("kk_string_filter_flat"), arguments: [trimResult, hofFnPtr, hofClosureRaw], result: filterResult, canThrow: true, thrownResult: filterThrown),
                .call(symbol: nil, callee: interner.intern("kk_string_filterIndexed_flat"), arguments: [trimResult, hofFnPtr, hofClosureRaw], result: filterIndexedResult, canThrow: true, thrownResult: filterIndexedThrown),
                .call(symbol: nil, callee: interner.intern("kk_string_filterNot_flat"), arguments: [trimResult, hofFnPtr, hofClosureRaw], result: filterNotResult, canThrow: true, thrownResult: filterNotThrown),
                .call(symbol: nil, callee: interner.intern("kk_string_takeWhile_flat"), arguments: [trimResult, hofFnPtr, hofClosureRaw], result: takeWhileResult, canThrow: true, thrownResult: takeWhileThrown),
                .call(symbol: nil, callee: interner.intern("kk_string_takeLastWhile_flat"), arguments: [trimResult, hofFnPtr, hofClosureRaw], result: takeLastWhileResult, canThrow: true, thrownResult: takeLastWhileThrown),
                .call(symbol: nil, callee: interner.intern("kk_string_dropWhile_flat"), arguments: [trimResult, hofFnPtr, hofClosureRaw], result: dropWhileResult, canThrow: true, thrownResult: dropWhileThrown),
                .constValue(result: needleExpr, value: .stringLiteral(needle)),
                .call(symbol: nil, callee: interner.intern("kk_string_startsWith_flat"), arguments: [trimResult, needleExpr], result: startsWithResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_contains_str_flat"), arguments: [trimResult, needleExpr], result: containsResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_indexOf_flat"), arguments: [trimResult, needleExpr], result: indexOfResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_isBlank_flat"), arguments: [trimResult], result: isBlankResult, canThrow: false, thrownResult: nil),
                .constValue(result: ignoreCaseTrue, value: .boolLiteral(true)),
                .constValue(result: charNeedle, value: .charLiteral(UInt32(UnicodeScalar("d").value))),
                .call(symbol: nil, callee: interner.intern("kk_string_compareToIgnoreCase_flat"), arguments: [trimResult, needleExpr, ignoreCaseTrue], result: compareIgnoreCaseResult, canThrow: false, thrownResult: nil),
                .constValue(result: localeRaw, value: .intLiteral(0)),
                .call(symbol: nil, callee: interner.intern("kk_string_compareTo_locale_flat"), arguments: [trimResult, needleExpr, localeRaw], result: compareLocaleResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_lastIndexOf_ignoreCase_flat"), arguments: [trimResult, needleExpr, takeCount, ignoreCaseTrue], result: lastIndexIgnoreCaseResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_indexOf_char_flat"), arguments: [trimResult, charNeedle, takeCount, ignoreCaseTrue], result: indexOfCharResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_lastIndexOf_char_flat"), arguments: [trimResult, charNeedle, takeCount, ignoreCaseTrue], result: lastIndexOfCharResult, canThrow: false, thrownResult: nil),
                .constValue(result: nullStringExpr, value: .null),
                .call(symbol: nil, callee: interner.intern("kk_string_isNullOrEmpty_flat"), arguments: [nullStringExpr], result: isNullOrEmptyResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_isNullOrBlank_flat"), arguments: [nullStringExpr], result: isNullOrBlankResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_contentEquals_flat"), arguments: [trimResult, nullStringExpr], result: contentEqualsResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_contentEquals_ignoreCase_flat"), arguments: [trimResult, needleExpr, ignoreCaseTrue], result: contentEqualsIgnoreCaseResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_equals_flat"), arguments: [trimResult, nullStringExpr], result: equalsResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_equalsIgnoreCase_flat"), arguments: [trimResult, nullStringExpr, ignoreCaseTrue], result: equalsIgnoreCaseResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("println"), arguments: [concatResult], result: nil, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_coroutine_suspended"), arguments: [], result: suspendedResult, canThrow: false, thrownResult: nil),
                .constValue(result: labelValue, value: .intLiteral(7)),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_state_set_label"),
                    arguments: [suspendedResult, labelValue],
                    result: labelResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .constValue(result: spillSlotValue, value: .intLiteral(0)),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_state_set_spill"),
                    arguments: [suspendedResult, spillSlotValue, labelValue],
                    result: spillStored,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_state_get_spill"),
                    arguments: [suspendedResult, spillSlotValue],
                    result: spillLoaded,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_state_set_completion"),
                    arguments: [suspendedResult, spillLoaded],
                    result: completionStored,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_state_get_completion"),
                    arguments: [suspendedResult],
                    result: completionLoaded,
                    canThrow: false,
                    thrownResult: nil
                ),
                // Control flow for if/when: branch on condition == false
                .constValue(result: falseConst, value: .boolLiteral(false)),
                .jumpIfEqual(lhs: whenCondition, rhs: falseConst, target: 900),
                .copy(from: labelValue, to: whenResult),
                .jump(901),
                .label(900),
                .copy(from: completionLoaded, to: whenResult),
                .label(901),
                .call(symbol: nil, callee: interner.intern("println"), arguments: [whenResult], result: nil, canThrow: false, thrownResult: nil),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_continuation_new"),
                    arguments: [labelValue],
                    result: continuationResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_state_exit"),
                    arguments: [continuationResult, completionLoaded],
                    result: stateExitResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(symbol: nil, callee: interner.intern("external_throwing"), arguments: [], result: throwingResult, canThrow: true, thrownResult: nil),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(main))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let backend = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let irPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ll").path

        try backend.emitLLVMIR(module: module, outputIRPath: irPath, interner: interner, typeSystem: types)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)

        XCTAssertFalse(ir.contains("@kk_string_from_utf8"))
        XCTAssertFalse(ir.contains("@kk_string_concat("))
        XCTAssertFalse(ir.contains("@kk_string_trim("))
        XCTAssertFalse(ir.contains("@kk_string_trimStart("))
        XCTAssertFalse(ir.contains("@kk_string_trimEnd("))
        XCTAssertFalse(ir.contains("@kk_string_lowercase("))
        XCTAssertFalse(ir.contains("@kk_string_uppercase("))
        XCTAssertFalse(ir.contains("@kk_string_reversed("))
        XCTAssertFalse(ir.contains("@kk_string_substring("))
        XCTAssertFalse(ir.contains("@kk_string_subSequence("))
        XCTAssertFalse(ir.contains("@kk_string_take("))
        XCTAssertFalse(ir.contains("@kk_string_repeat("))
        XCTAssertFalse(ir.contains("@kk_string_takeLast("))
        XCTAssertFalse(ir.contains("@kk_string_drop("))
        XCTAssertFalse(ir.contains("@kk_string_dropLast("))
        XCTAssertFalse(ir.contains("@kk_string_filter("))
        XCTAssertFalse(ir.contains("@kk_string_filterIndexed("))
        XCTAssertFalse(ir.contains("@kk_string_filterNot("))
        XCTAssertFalse(ir.contains("@kk_string_takeWhile("))
        XCTAssertFalse(ir.contains("@kk_string_takeLastWhile("))
        XCTAssertFalse(ir.contains("@kk_string_dropWhile("))
        XCTAssertFalse(ir.contains("@kk_string_indexOf_char("))
        XCTAssertFalse(ir.contains("@kk_string_lastIndexOf_char("))
        XCTAssertTrue(ir.contains("@kk_string_concat_flat"))
        XCTAssertTrue(ir.contains("@kk_string_trim_flat"))
        XCTAssertTrue(ir.contains("@kk_string_trimStart_flat"))
        XCTAssertTrue(ir.contains("@kk_string_trimEnd_flat"))
        XCTAssertTrue(ir.contains("@kk_string_lowercase_flat"))
        XCTAssertTrue(ir.contains("@kk_string_uppercase_flat"))
        XCTAssertTrue(ir.contains("@kk_string_reversed_flat"))
        XCTAssertTrue(ir.contains("@kk_string_substring_flat"))
        XCTAssertTrue(ir.contains("@kk_string_subSequence_flat"))
        XCTAssertTrue(ir.contains("@kk_string_take_flat"))
        XCTAssertTrue(ir.contains("@kk_string_repeat_flat"))
        XCTAssertTrue(ir.contains("@kk_string_takeLast_flat"))
        XCTAssertTrue(ir.contains("@kk_string_drop_flat"))
        XCTAssertTrue(ir.contains("@kk_string_dropLast_flat"))
        XCTAssertTrue(ir.contains("@kk_string_filter_flat"))
        XCTAssertTrue(ir.contains("@kk_string_filterIndexed_flat"))
        XCTAssertTrue(ir.contains("@kk_string_filterNot_flat"))
        XCTAssertTrue(ir.contains("@kk_string_takeWhile_flat"))
        XCTAssertTrue(ir.contains("@kk_string_takeLastWhile_flat"))
        XCTAssertTrue(ir.contains("@kk_string_dropWhile_flat"))
        XCTAssertTrue(ir.contains("@kk_string_startsWith_flat"))
        XCTAssertTrue(ir.contains("@kk_string_contains_str_flat"))
        XCTAssertTrue(ir.contains("@kk_string_indexOf_flat"))
        XCTAssertTrue(ir.contains("@kk_string_isBlank_flat"))
        XCTAssertTrue(ir.contains("@kk_string_compareToIgnoreCase_flat"))
        XCTAssertTrue(ir.contains("@kk_string_compareTo_locale_flat"))
        XCTAssertTrue(ir.contains("@kk_string_lastIndexOf_ignoreCase_flat"))
        XCTAssertTrue(ir.contains("@kk_string_indexOf_char_flat"))
        XCTAssertTrue(ir.contains("@kk_string_lastIndexOf_char_flat"))
        XCTAssertTrue(ir.contains("@kk_string_isNullOrEmpty_flat"))
        XCTAssertTrue(ir.contains("@kk_string_isNullOrBlank_flat"))
        XCTAssertTrue(ir.contains("@kk_string_contentEquals_flat"))
        XCTAssertTrue(ir.contains("@kk_string_contentEquals_ignoreCase_flat"))
        XCTAssertTrue(ir.contains("@kk_string_equals_flat"))
        XCTAssertFalse(ir.contains("@kk_string_equals("))
        XCTAssertTrue(ir.contains("@kk_string_equalsIgnoreCase_flat"))
        XCTAssertTrue(ir.contains("@kk_println_string_flat"))
        XCTAssertTrue(ir.contains("{ ptr, i64, i64, i64 }"))
        XCTAssertTrue(ir.contains("@kk_coroutine_suspended"))
        XCTAssertTrue(ir.contains("@kk_coroutine_state_set_label"))
        XCTAssertTrue(ir.contains("@kk_coroutine_state_set_spill"))
        XCTAssertTrue(ir.contains("@kk_coroutine_state_get_spill"))
        XCTAssertTrue(ir.contains("@kk_coroutine_state_set_completion"))
        XCTAssertTrue(ir.contains("@kk_coroutine_state_get_completion"))
        XCTAssertTrue(ir.contains("@kk_println_any"))
        XCTAssertTrue(ir.contains("@kk_register_frame_map"))
        XCTAssertTrue(ir.contains("@kk_push_frame"))
        XCTAssertTrue(ir.contains("@kk_pop_frame"))
        XCTAssertTrue(ir.contains("@kk_register_coroutine_root"))
        XCTAssertTrue(ir.contains("@kk_unregister_coroutine_root"))
        XCTAssertTrue(ir.contains("coroutine_root_register"))
        XCTAssertTrue(ir.contains("coroutine_root_unregister"))
        // select i1 no longer emitted; control flow uses conditional branches instead
        let hasConditionalBranch = ir.contains("br i1") || ir.contains("icmp eq")
        XCTAssertTrue(hasConditionalBranch)
        XCTAssertTrue(ir.contains("thrown_slot_"))
        XCTAssertTrue(ir.contains("@external_throwing"))
    }

    func testLLVMBackendEmitsFlatStringParsingRuntimeCalls() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()
        let nullableStringType = types.makeNullable(types.stringType)
        let nullableBoolType = types.makeNullable(types.booleanType)
        let nullableIntType = types.makeNullable(types.intType)
        let nullableLongType = types.makeNullable(types.longType)
        let nullableFloatType = types.makeNullable(types.floatType)
        let nullableDoubleType = types.makeNullable(types.doubleType)
        let nullableUByteType = types.makeNullable(types.ubyteType)
        let nullableUShortType = types.makeNullable(types.ushortType)
        let nullableUIntType = types.makeNullable(types.uintType)
        let nullableULongType = types.makeNullable(types.ulongType)

        let text = interner.intern("ff")
        let textExpr = arena.appendExpr(.stringLiteral(text), type: types.stringType)
        let nullStringExpr = arena.appendExpr(.null, type: nullableStringType)
        let radixExpr = arena.appendExpr(.intLiteral(16), type: types.intType)
        let formatExpr = arena.appendExpr(.intLiteral(0), type: types.intType)

        var nextTemp: Int32 = 100
        func temporary(_ type: TypeID) -> KIRExprID {
            nextTemp += 1
            return arena.appendExpr(.temporary(nextTemp), type: type)
        }

        var body: [KIRInstruction] = [
            .constValue(result: textExpr, value: .stringLiteral(text)),
            .constValue(result: nullStringExpr, value: .null),
            .constValue(result: radixExpr, value: .intLiteral(16)),
            .constValue(result: formatExpr, value: .intLiteral(0)),
        ]

        func appendParsingCall(
            _ calleeName: String,
            arguments: [KIRExprID],
            resultType: TypeID,
            canThrow: Bool = false
        ) {
            let result = temporary(resultType)
            let thrownResult = canThrow ? temporary(types.intType) : nil
            body.append(.call(
                symbol: nil,
                callee: interner.intern(calleeName),
                arguments: arguments,
                result: result,
                canThrow: canThrow,
                thrownResult: thrownResult
            ))
        }

        appendParsingCall("kk_string_toBoolean_flat", arguments: [nullStringExpr], resultType: types.booleanType)
        appendParsingCall("kk_string_toBooleanStrict_flat", arguments: [textExpr], resultType: types.booleanType, canThrow: true)
        appendParsingCall("kk_string_toBooleanStrictOrNull_flat", arguments: [textExpr], resultType: nullableBoolType)
        appendParsingCall("kk_string_toInt_flat", arguments: [textExpr], resultType: types.intType, canThrow: true)
        appendParsingCall("kk_string_toInt_radix_flat", arguments: [textExpr, radixExpr], resultType: types.intType, canThrow: true)
        appendParsingCall("kk_string_toIntOrNull_flat", arguments: [textExpr], resultType: nullableIntType)
        appendParsingCall("kk_string_toIntOrNull_radix_flat", arguments: [textExpr, radixExpr], resultType: nullableIntType, canThrow: true)
        appendParsingCall("kk_string_toUByteOrNull_radix_flat", arguments: [textExpr, radixExpr], resultType: nullableUByteType, canThrow: true)
        appendParsingCall("kk_string_toUShortOrNull_radix_flat", arguments: [textExpr, radixExpr], resultType: nullableUShortType, canThrow: true)
        appendParsingCall("kk_string_toUIntOrNull_radix_flat", arguments: [textExpr, radixExpr], resultType: nullableUIntType, canThrow: true)
        appendParsingCall("kk_string_toULongOrNull_radix_flat", arguments: [textExpr, radixExpr], resultType: nullableULongType, canThrow: true)
        appendParsingCall("__kk_string_toDouble_flat", arguments: [textExpr], resultType: types.doubleType, canThrow: true)
        appendParsingCall("__kk_string_toDoubleOrNull_flat", arguments: [textExpr], resultType: nullableDoubleType)
        appendParsingCall("kk_string_toLong_flat", arguments: [textExpr], resultType: types.longType, canThrow: true)
        appendParsingCall("kk_string_toLongOrNull_flat", arguments: [textExpr], resultType: nullableLongType)
        appendParsingCall("__kk_string_toFloat_flat", arguments: [textExpr], resultType: types.floatType, canThrow: true)
        appendParsingCall("__kk_string_toFloatOrNull_flat", arguments: [textExpr], resultType: nullableFloatType)
        appendParsingCall("kk_string_toShort_flat", arguments: [textExpr], resultType: types.intType, canThrow: true)
        appendParsingCall("kk_string_toShortOrNull_flat", arguments: [textExpr], resultType: nullableIntType)
        appendParsingCall("kk_string_toByte_flat", arguments: [textExpr], resultType: types.intType, canThrow: true)
        appendParsingCall("kk_string_toByte_radix_flat", arguments: [textExpr, radixExpr], resultType: types.intType, canThrow: true)
        appendParsingCall("kk_string_toByteOrNull_flat", arguments: [textExpr], resultType: nullableIntType)
        appendParsingCall("__kk_string_toBigDecimal_flat", arguments: [textExpr], resultType: types.intType, canThrow: true)
        appendParsingCall("__kk_string_toBigInteger_flat", arguments: [textExpr], resultType: types.intType, canThrow: true)
        appendParsingCall("kk_string_hexToInt_flat", arguments: [textExpr, formatExpr], resultType: types.intType, canThrow: true)
        appendParsingCall("kk_string_hexToShort_flat", arguments: [textExpr, formatExpr], resultType: types.intType, canThrow: true)
        appendParsingCall("kk_string_hexToUByte_flat", arguments: [textExpr, formatExpr], resultType: types.ubyteType, canThrow: true)
        appendParsingCall("kk_string_hexToUShort_flat", arguments: [textExpr, formatExpr], resultType: types.ushortType, canThrow: true)
        appendParsingCall("kk_string_hexToUInt_flat", arguments: [textExpr, formatExpr], resultType: types.uintType, canThrow: true)
        appendParsingCall("kk_string_hexToULong_flat", arguments: [textExpr, formatExpr], resultType: types.ulongType, canThrow: true)
        appendParsingCall("kk_string_hexToLong_flat", arguments: [textExpr, formatExpr], resultType: types.longType, canThrow: true)
        appendParsingCall("kk_string_hexToByteArray_flat", arguments: [textExpr, formatExpr], resultType: types.intType)
        appendParsingCall("kk_string_hexToUByteArray_flat", arguments: [textExpr, formatExpr], resultType: types.intType)
        body.append(.returnUnit)

        let main = KIRFunction(
            symbol: SymbolID(rawValue: 1201),
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: body,
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(main))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let backend = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let irPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ll").path

        try backend.emitLLVMIR(module: module, outputIRPath: irPath, interner: interner, typeSystem: types)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)

        let rawNames = [
            "kk_string_toBoolean",
            "kk_string_toBooleanStrict",
            "kk_string_toBooleanStrictOrNull",
            "kk_string_toInt",
            "kk_string_toInt_radix",
            "kk_string_toIntOrNull",
            "kk_string_toIntOrNull_radix",
            "kk_string_toUByteOrNull_radix",
            "kk_string_toUShortOrNull_radix",
            "kk_string_toUIntOrNull_radix",
            "kk_string_toULongOrNull_radix",
            "__kk_string_toDouble",
            "__kk_string_toDoubleOrNull",
            "kk_string_toLong",
            "kk_string_toLongOrNull",
            "__kk_string_toFloat",
            "__kk_string_toFloatOrNull",
            "kk_string_toShort",
            "kk_string_toShortOrNull",
            "kk_string_toByte",
            "kk_string_toByte_radix",
            "kk_string_toByteOrNull",
            "__kk_string_toBigDecimal",
            "__kk_string_toBigInteger",
        ]
        for rawName in rawNames {
            XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected raw String parse call: \(rawName)")
            XCTAssertTrue(ir.contains("@\(rawName)_flat"), "Missing flat String parse call: \(rawName)_flat")
        }
        let removedRawHexNames = [
            "Int",
            "Short",
            "UByte",
            "UShort",
            "UInt",
            "ULong",
            "Long",
            "ByteArray",
            "UByteArray",
        ].map { "kk_string_hexTo\($0)" }
        for rawName in removedRawHexNames {
            XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected removed raw String hex call: \(rawName)")
            XCTAssertTrue(ir.contains("@\(rawName)_flat"), "Missing flat String hex call: \(rawName)_flat")
        }
    }

    func testLLVMBackendEmitsFlatRegexStringRuntimeCalls() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let pattern = interner.intern("[a-z]+")
        let input = interner.intern("abc")
        let patternExpr = arena.appendExpr(.stringLiteral(pattern), type: types.stringType)
        let inputExpr = arena.appendExpr(.stringLiteral(input), type: types.stringType)
        let regexExpr = arena.appendExpr(.intLiteral(42), type: types.intType)
        let optionExpr = arena.appendExpr(.intLiteral(0), type: types.intType)
        let optionsSetExpr = arena.appendExpr(.intLiteral(0), type: types.intType)
        let matchGroupCollectionExpr = arena.appendExpr(.intLiteral(43), type: types.intType)

        var nextTemp: Int32 = 200
        func temporary(_ type: TypeID) -> KIRExprID {
            nextTemp += 1
            return arena.appendExpr(.temporary(nextTemp), type: type)
        }

        var body: [KIRInstruction] = [
            .constValue(result: patternExpr, value: .stringLiteral(pattern)),
            .constValue(result: inputExpr, value: .stringLiteral(input)),
            .constValue(result: regexExpr, value: .intLiteral(42)),
            .constValue(result: optionExpr, value: .intLiteral(0)),
            .constValue(result: optionsSetExpr, value: .intLiteral(0)),
            .constValue(result: matchGroupCollectionExpr, value: .intLiteral(43)),
        ]

        func appendRegexCall(_ calleeName: String, arguments: [KIRExprID]) {
            body.append(.call(
                symbol: nil,
                callee: interner.intern(calleeName),
                arguments: arguments,
                result: temporary(types.intType),
                canThrow: false,
                thrownResult: nil
            ))
        }

        appendRegexCall("kk_regex_create_flat", arguments: [patternExpr])
        appendRegexCall("kk_regex_create_with_option_flat", arguments: [patternExpr, optionExpr])
        appendRegexCall("kk_regex_create_with_options_flat", arguments: [patternExpr, optionsSetExpr])
        appendRegexCall("kk_string_matches_regex_flat", arguments: [inputExpr, regexExpr])
        appendRegexCall("kk_string_contains_regex_flat", arguments: [inputExpr, regexExpr])
        appendRegexCall("kk_string_toRegex_flat", arguments: [patternExpr])
        appendRegexCall("kk_string_toRegex_with_option_flat", arguments: [patternExpr, optionExpr])
        appendRegexCall("kk_string_toRegex_with_options_flat", arguments: [patternExpr, optionsSetExpr])
        appendRegexCall("kk_regex_find_flat", arguments: [regexExpr, inputExpr])
        appendRegexCall("kk_regex_findAll_flat", arguments: [regexExpr, inputExpr])
        appendRegexCall("kk_string_split_regex_flat", arguments: [inputExpr, regexExpr])
        appendRegexCall("kk_regex_matchEntire_flat", arguments: [regexExpr, inputExpr])
        appendRegexCall("kk_regex_containsMatchIn_flat", arguments: [regexExpr, inputExpr])
        appendRegexCall("kk_regex_from_literal_flat", arguments: [optionExpr, patternExpr])
        appendRegexCall("kk_match_group_collection_get", arguments: [matchGroupCollectionExpr, patternExpr])
        appendRegexCall("kk_regex_matches_flat", arguments: [regexExpr, inputExpr])
        body.append(.returnUnit)

        let main = KIRFunction(
            symbol: SymbolID(rawValue: 1207),
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: body,
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(main))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let backend = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let irPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ll").path

        try backend.emitLLVMIR(module: module, outputIRPath: irPath, interner: interner, typeSystem: types)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)

        let rawNames = [
            "kk_regex_create",
            "kk_regex_create_with_option",
            "kk_regex_create_with_options",
            "kk_string_toRegex",
            "kk_string_toRegex_with_option",
            "kk_string_toRegex_with_options",
            "kk_regex_find",
            "kk_regex_findAll",
            "kk_regex_matchEntire",
            "kk_regex_containsMatchIn",
            "kk_regex_from_literal",
            "kk_match_group_collection_get",
            "kk_regex_matches",
        ]
        for rawName in rawNames {
            XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected raw Regex String call: \(rawName)")
            XCTAssertTrue(ir.contains("@\(rawName)_flat"), "Missing flat Regex String call: \(rawName)_flat")
        }

        XCTAssertFalse(ir.contains("@kk_string_split_regex("), "Unexpected raw Regex String call: kk_string_split_regex")
        XCTAssertTrue(ir.contains("@kk_string_split_regex_flat"), "Missing flat Regex String call: kk_string_split_regex_flat")

        let removedRawStringPredicateNames = ["matches", "contains"].map { "kk_string_\($0)_regex" }
        for rawName in removedRawStringPredicateNames {
            XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected removed raw Regex String call: \(rawName)")
            XCTAssertTrue(ir.contains("@\(rawName)_flat"), "Missing flat Regex String call: \(rawName)_flat")
        }
    }

    func testLLVMBackendEmitsFlatStringBuilderStringRuntimeCalls() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let text = interner.intern("abcd")
        let textExpr = arena.appendExpr(.stringLiteral(text), type: types.stringType)
        let builderExpr = arena.appendExpr(.intLiteral(44), type: types.intType)
        let startExpr = arena.appendExpr(.intLiteral(1), type: types.intType)
        let endExpr = arena.appendExpr(.intLiteral(3), type: types.intType)

        var nextTemp: Int32 = 300
        func temporary(_ type: TypeID) -> KIRExprID {
            nextTemp += 1
            return arena.appendExpr(.temporary(nextTemp), type: type)
        }

        var body: [KIRInstruction] = [
            .constValue(result: textExpr, value: .stringLiteral(text)),
            .constValue(result: builderExpr, value: .intLiteral(44)),
            .constValue(result: startExpr, value: .intLiteral(1)),
            .constValue(result: endExpr, value: .intLiteral(3)),
        ]

        func appendBuilderCall(_ calleeName: String, arguments: [KIRExprID]) {
            body.append(.call(
                symbol: nil,
                callee: interner.intern(calleeName),
                arguments: arguments,
                result: temporary(types.intType),
                canThrow: false,
                thrownResult: nil
            ))
        }

        appendBuilderCall("kk_string_builder_append_flat", arguments: [textExpr])
        appendBuilderCall("kk_string_builder_append_line_flat", arguments: [textExpr])
        appendBuilderCall("kk_string_builder_append_range_flat", arguments: [textExpr, startExpr, endExpr])
        appendBuilderCall("kk_string_builder_insert_flat", arguments: [startExpr, textExpr])
        appendBuilderCall("kk_string_builder_new_from_string_flat", arguments: [textExpr])
        appendBuilderCall("kk_string_builder_append_obj", arguments: [builderExpr, textExpr])
        appendBuilderCall("kk_string_builder_append_line_obj", arguments: [builderExpr, textExpr])
        appendBuilderCall("kk_string_builder_insert_obj", arguments: [builderExpr, startExpr, textExpr])
        appendBuilderCall("kk_string_builder_appendRange_obj_flat", arguments: [builderExpr, textExpr, startExpr, endExpr])
        appendBuilderCall("kk_string_builder_insertRange_obj_flat", arguments: [builderExpr, startExpr, textExpr, startExpr, endExpr])
        appendBuilderCall("kk_string_builder_setRange_flat", arguments: [builderExpr, startExpr, endExpr, textExpr])
        appendBuilderCall("kk_string_builder_replace_obj_flat", arguments: [builderExpr, startExpr, endExpr, textExpr])
        body.append(.returnUnit)

        let main = KIRFunction(
            symbol: SymbolID(rawValue: 1208),
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: body,
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(main))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let backend = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let irPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ll").path

        try backend.emitLLVMIR(module: module, outputIRPath: irPath, interner: interner, typeSystem: types)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)

        let rawNames = [
            "kk_string_builder_append",
            "kk_string_builder_append_line",
            "kk_string_builder_append_range",
            "kk_string_builder_insert",
            "kk_string_builder_new_from_string",
            "kk_string_builder_append_obj",
            "kk_string_builder_append_line_obj",
            "kk_string_builder_insert_obj",
            "kk_string_builder_appendRange_obj",
            "kk_string_builder_insertRange_obj",
            "kk_string_builder_setRange",
            "kk_string_builder_replace_obj",
        ]
        for rawName in rawNames {
            XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected raw StringBuilder String call: \(rawName)")
            XCTAssertTrue(ir.contains("@\(rawName)_flat"), "Missing flat StringBuilder String call: \(rawName)_flat")
        }
    }

    func testLLVMBackendEmitsFlatLocaleConstructorRuntimeCalls() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let identifier = interner.intern("en_US")
        let language = interner.intern("de")
        let country = interner.intern("DE")
        let identifierExpr = arena.appendExpr(.stringLiteral(identifier), type: types.stringType)
        let languageExpr = arena.appendExpr(.stringLiteral(language), type: types.stringType)
        let countryExpr = arena.appendExpr(.stringLiteral(country), type: types.stringType)

        var nextTemp: Int32 = 350
        func temporary(_ type: TypeID) -> KIRExprID {
            nextTemp += 1
            return arena.appendExpr(.temporary(nextTemp), type: type)
        }

        var body: [KIRInstruction] = [
            .constValue(result: identifierExpr, value: .stringLiteral(identifier)),
            .constValue(result: languageExpr, value: .stringLiteral(language)),
            .constValue(result: countryExpr, value: .stringLiteral(country)),
        ]

        func appendLocaleCall(_ calleeName: String, arguments: [KIRExprID]) {
            body.append(.call(
                symbol: nil,
                callee: interner.intern(calleeName),
                arguments: arguments,
                result: temporary(types.intType),
                canThrow: false,
                thrownResult: nil
            ))
        }

        appendLocaleCall("kk_locale_new_flat", arguments: [identifierExpr])
        appendLocaleCall("kk_locale_new_language_country_flat", arguments: [languageExpr, countryExpr])
        body.append(.returnUnit)

        let main = KIRFunction(
            symbol: SymbolID(rawValue: 1220),
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: body,
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(main))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let backend = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let irPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ll").path

        try backend.emitLLVMIR(module: module, outputIRPath: irPath, interner: interner, typeSystem: types)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)

        XCTAssertFalse(ir.contains("@kk_locale_new("), "Unexpected raw Locale constructor call")
        XCTAssertFalse(ir.contains("@kk_locale_new_language_country("), "Unexpected raw Locale language/country constructor call")
        XCTAssertTrue(ir.contains("@kk_locale_new_flat"), "Missing flat Locale constructor call")
        XCTAssertTrue(ir.contains("@kk_locale_new_language_country_flat"), "Missing flat Locale language/country constructor call")
    }

    func testLLVMBackendEmitsFlatStringCharSelectionRuntimeCalls() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()
        let nullableCharType = types.makeNullable(types.charType)

        let text = interner.intern("abc")
        let textExpr = arena.appendExpr(.stringLiteral(text), type: types.stringType)
        let indexExpr = arena.appendExpr(.intLiteral(1), type: types.intType)

        var nextTemp: Int32 = 200
        func temporary(_ type: TypeID) -> KIRExprID {
            nextTemp += 1
            return arena.appendExpr(.temporary(nextTemp), type: type)
        }

        var body: [KIRInstruction] = [
            .constValue(result: textExpr, value: .stringLiteral(text)),
            .constValue(result: indexExpr, value: .intLiteral(1)),
        ]

        func appendSelectionCall(
            _ calleeName: String,
            arguments: [KIRExprID],
            resultType: TypeID,
            canThrow: Bool = false
        ) {
            let result = temporary(resultType)
            let thrownResult = canThrow ? temporary(types.intType) : nil
            body.append(.call(
                symbol: nil,
                callee: interner.intern(calleeName),
                arguments: arguments,
                result: result,
                canThrow: canThrow,
                thrownResult: thrownResult
            ))
        }

        appendSelectionCall("kk_string_first_flat", arguments: [textExpr], resultType: types.charType, canThrow: true)
        appendSelectionCall("kk_string_last_flat", arguments: [textExpr], resultType: types.charType, canThrow: true)
        appendSelectionCall("kk_string_single_flat", arguments: [textExpr], resultType: types.charType, canThrow: true)
        appendSelectionCall("kk_string_firstOrNull_flat", arguments: [textExpr], resultType: nullableCharType)
        appendSelectionCall("kk_string_lastOrNull_flat", arguments: [textExpr], resultType: nullableCharType)
        appendSelectionCall("kk_string_singleOrNull_flat", arguments: [textExpr], resultType: nullableCharType)
        appendSelectionCall("kk_string_get_flat", arguments: [textExpr, indexExpr], resultType: types.charType, canThrow: true)
        appendSelectionCall("kk_string_getOrNull_flat", arguments: [textExpr, indexExpr], resultType: nullableCharType)
        body.append(.returnUnit)

        let main = KIRFunction(
            symbol: SymbolID(rawValue: 1202),
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: body,
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(main))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let backend = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let irPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ll").path

        try backend.emitLLVMIR(module: module, outputIRPath: irPath, interner: interner, typeSystem: types)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)

        let flatNames = [
            "kk_string_first_flat",
            "kk_string_last_flat",
            "kk_string_single_flat",
            "kk_string_firstOrNull_flat",
            "kk_string_lastOrNull_flat",
            "kk_string_singleOrNull_flat",
            "kk_string_getOrNull_flat",
        ]
        for flatName in flatNames {
            let rawName = String(flatName.dropLast("_flat".count))
            XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected raw String char-selection call: \(rawName)")
            XCTAssertTrue(ir.contains("@\(flatName)"), "Missing flat String char-selection call: \(flatName)")
        }
        XCTAssertTrue(ir.contains("@kk_string_get_flat"), "Missing flat String.get call")
    }

    func testLLVMBackendEmitsFlatStringPredicateRuntimeCalls() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let text = interner.intern("abcd")
        let textExpr = arena.appendExpr(.stringLiteral(text), type: types.stringType)
        let formTagExpr = arena.appendExpr(.intLiteral(0), type: types.intType)

        var nextTemp: Int32 = 300
        func temporary(_ type: TypeID) -> KIRExprID {
            nextTemp += 1
            return arena.appendExpr(.temporary(nextTemp), type: type)
        }

        var body: [KIRInstruction] = [
            .constValue(result: textExpr, value: .stringLiteral(text)),
        ]

        func appendPredicateCall(_ calleeName: String, arguments: [KIRExprID]? = nil) {
            body.append(.call(
                symbol: nil,
                callee: interner.intern(calleeName),
                arguments: arguments ?? [textExpr],
                result: temporary(types.booleanType),
                canThrow: false,
                thrownResult: nil
            ))
        }

        appendPredicateCall("kk_string_isNotEmpty_flat")
        appendPredicateCall("kk_string_isNotBlank_flat")
        appendPredicateCall("__kk_string_isNormalized_flat", arguments: [textExpr, formTagExpr])
        body.append(.returnUnit)

        let main = KIRFunction(
            symbol: SymbolID(rawValue: 1210),
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: body,
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(main))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let backend = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let irPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ll").path

        try backend.emitLLVMIR(module: module, outputIRPath: irPath, interner: interner, typeSystem: types)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)

        let flatNames = [
            "kk_string_isNotEmpty_flat",
            "kk_string_isNotBlank_flat",
            "__kk_string_isNormalized_flat",
        ]
        for flatName in flatNames {
            let rawName = String(flatName.dropLast("_flat".count))
            XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected raw String predicate call: \(rawName)")
            XCTAssertTrue(ir.contains("@\(flatName)"), "Missing flat String predicate call: \(flatName)")
        }
    }

    func testLLVMBackendEmitsFlatStringCallbackScalarRuntimeCalls() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let text = interner.intern("a1b2")
        let textExpr = arena.appendExpr(.stringLiteral(text), type: types.stringType)
        let fnPtrExpr = arena.appendExpr(.intLiteral(0), type: types.intType)
        let closureExpr = arena.appendExpr(.intLiteral(0), type: types.intType)

        var nextTemp: Int32 = 300
        func temporary(_ type: TypeID) -> KIRExprID {
            nextTemp += 1
            return arena.appendExpr(.temporary(nextTemp), type: type)
        }

        var body: [KIRInstruction] = [
            .constValue(result: textExpr, value: .stringLiteral(text)),
            .constValue(result: fnPtrExpr, value: .intLiteral(0)),
            .constValue(result: closureExpr, value: .intLiteral(0)),
        ]

        func appendCallbackCall(_ calleeName: String, resultType: TypeID) {
            let result = temporary(resultType)
            let thrownResult = temporary(types.intType)
            body.append(.call(
                symbol: nil,
                callee: interner.intern(calleeName),
                arguments: [textExpr, fnPtrExpr, closureExpr],
                result: result,
                canThrow: true,
                thrownResult: thrownResult
            ))
        }

        appendCallbackCall("kk_string_count_flat", resultType: types.intType)
        appendCallbackCall("kk_string_any_flat", resultType: types.booleanType)
        appendCallbackCall("kk_string_all_flat", resultType: types.booleanType)
        appendCallbackCall("kk_string_none_flat", resultType: types.booleanType)
        appendCallbackCall("kk_string_indexOfFirst_flat", resultType: types.intType)
        appendCallbackCall("kk_string_indexOfLast_flat", resultType: types.intType)
        appendCallbackCall("kk_string_find_flat", resultType: types.intType)
        appendCallbackCall("kk_string_findLast_flat", resultType: types.intType)
        appendCallbackCall("kk_string_partition_flat", resultType: types.anyType)
        appendCallbackCall("kk_string_map_flat", resultType: types.anyType)
        appendCallbackCall("kk_string_mapIndexed_flat", resultType: types.anyType)
        appendCallbackCall("kk_string_mapNotNull_flat", resultType: types.anyType)
        appendCallbackCall("kk_string_firstNotNullOf_flat", resultType: types.intType)
        appendCallbackCall("kk_string_firstNotNullOfOrNull_flat", resultType: types.intType)
        appendCallbackCall("kk_string_reduceOrNull_flat", resultType: types.intType)
        appendCallbackCall("kk_string_reduceRightIndexed_flat", resultType: types.intType)
        appendCallbackCall("kk_string_reduceRightIndexedOrNull_flat", resultType: types.intType)
        appendCallbackCall("kk_string_reduceRightOrNull_flat", resultType: types.intType)
        appendCallbackCall("kk_string_sumBy_flat", resultType: types.intType)
        appendCallbackCall("kk_string_sumByDouble_flat", resultType: types.doubleType)
        body.append(.returnUnit)

        let main = KIRFunction(
            symbol: SymbolID(rawValue: 1203),
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: body,
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(main))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let backend = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let irPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ll").path

        try backend.emitLLVMIR(module: module, outputIRPath: irPath, interner: interner, typeSystem: types)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)

        let flatNames = [
            "kk_string_count_flat",
            "kk_string_any_flat",
            "kk_string_all_flat",
            "kk_string_none_flat",
            "kk_string_indexOfFirst_flat",
            "kk_string_indexOfLast_flat",
            "kk_string_find_flat",
            "kk_string_findLast_flat",
            "kk_string_partition_flat",
            "kk_string_map_flat",
            "kk_string_mapIndexed_flat",
            "kk_string_mapNotNull_flat",
            "kk_string_firstNotNullOf_flat",
            "kk_string_firstNotNullOfOrNull_flat",
            "kk_string_reduceOrNull_flat",
            "kk_string_reduceRightIndexed_flat",
            "kk_string_reduceRightIndexedOrNull_flat",
            "kk_string_reduceRightOrNull_flat",
            "kk_string_sumBy_flat",
            "kk_string_sumByDouble_flat",
        ]
        for flatName in flatNames {
            let rawName = String(flatName.dropLast("_flat".count))
            XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected raw String callback scalar call: \(rawName)")
            XCTAssertTrue(ir.contains("@\(flatName)"), "Missing flat String callback scalar call: \(flatName)")
        }

    }

    func testLLVMBackendEmitsFlatStringIndexOfAnyRuntimeCalls() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let text = interner.intern("aBcabc")
        let textExpr = arena.appendExpr(.stringLiteral(text), type: types.stringType)
        let charsRawExpr = arena.appendExpr(.intLiteral(101), type: types.intType)
        let stringsRawExpr = arena.appendExpr(.intLiteral(102), type: types.intType)
        let startExpr = arena.appendExpr(.intLiteral(0), type: types.intType)
        let ignoreCaseExpr = arena.appendExpr(.boolLiteral(true), type: types.booleanType)

        var nextTemp: Int32 = 400
        func temporary(_ type: TypeID) -> KIRExprID {
            nextTemp += 1
            return arena.appendExpr(.temporary(nextTemp), type: type)
        }

        var body: [KIRInstruction] = [
            .constValue(result: textExpr, value: .stringLiteral(text)),
            .constValue(result: charsRawExpr, value: .intLiteral(101)),
            .constValue(result: stringsRawExpr, value: .intLiteral(102)),
            .constValue(result: startExpr, value: .intLiteral(0)),
            .constValue(result: ignoreCaseExpr, value: .boolLiteral(true)),
        ]

        func appendSearchCall(_ calleeName: String, targetRaw: KIRExprID) {
            body.append(.call(
                symbol: nil,
                callee: interner.intern(calleeName),
                arguments: [textExpr, targetRaw, startExpr, ignoreCaseExpr],
                result: temporary(types.intType),
                canThrow: false,
                thrownResult: nil
            ))
        }

        appendSearchCall("kk_string_indexOfAny_chars_flat", targetRaw: charsRawExpr)
        appendSearchCall("kk_string_indexOfAny_strings_flat", targetRaw: stringsRawExpr)
        appendSearchCall("kk_string_lastIndexOfAny_chars_flat", targetRaw: charsRawExpr)
        appendSearchCall("kk_string_lastIndexOfAny_strings_flat", targetRaw: stringsRawExpr)
        appendSearchCall("kk_string_findAnyOf_flat", targetRaw: stringsRawExpr)
        appendSearchCall("kk_string_findLastAnyOf_flat", targetRaw: stringsRawExpr)
        body.append(.returnUnit)

        let main = KIRFunction(
            symbol: SymbolID(rawValue: 1204),
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: body,
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(main))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let backend = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let irPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ll").path

        try backend.emitLLVMIR(module: module, outputIRPath: irPath, interner: interner, typeSystem: types)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)

        let flatNames = [
            "kk_string_indexOfAny_chars_flat",
            "kk_string_indexOfAny_strings_flat",
            "kk_string_lastIndexOfAny_chars_flat",
            "kk_string_lastIndexOfAny_strings_flat",
            "kk_string_findAnyOf_flat",
            "kk_string_findLastAnyOf_flat",
        ]
        for flatName in flatNames {
            let rawName = String(flatName.dropLast("_flat".count))
            XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected raw String indexOfAny call: \(rawName)")
            XCTAssertTrue(ir.contains("@\(flatName)"), "Missing flat String indexOfAny call: \(flatName)")
        }
    }

    func testLLVMBackendEmitsFlatStringMaterializationRuntimeCalls() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let text = interner.intern("abc")
        let textExpr = arena.appendExpr(.stringLiteral(text), type: types.stringType)
        let destinationExpr = arena.appendExpr(.intLiteral(0), type: types.intType)

        var nextTemp: Int32 = 500
        func temporary(_ type: TypeID) -> KIRExprID {
            nextTemp += 1
            return arena.appendExpr(.temporary(nextTemp), type: type)
        }

        var body: [KIRInstruction] = [
            .constValue(result: textExpr, value: .stringLiteral(text)),
            .constValue(result: destinationExpr, value: .intLiteral(0)),
        ]

        func appendMaterializationCall(_ calleeName: String, extraArguments: [KIRExprID] = []) {
            body.append(.call(
                symbol: nil,
                callee: interner.intern(calleeName),
                arguments: [textExpr] + extraArguments,
                result: temporary(types.intType),
                canThrow: false,
                thrownResult: nil
            ))
        }

        appendMaterializationCall("kk_string_toList_flat")
        appendMaterializationCall("kk_string_toCharArray_flat")
        appendMaterializationCall("kk_string_toTypedArray_flat")
        appendMaterializationCall("kk_string_toSortedSet_flat")
        appendMaterializationCall("kk_string_toCollection_flat", extraArguments: [destinationExpr])
        appendMaterializationCall("kk_string_withIndex_flat")
        appendMaterializationCall("kk_string_iterator_flat")
        body.append(.returnUnit)

        let main = KIRFunction(
            symbol: SymbolID(rawValue: 1205),
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: body,
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(main))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let backend = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let irPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ll").path

        try backend.emitLLVMIR(module: module, outputIRPath: irPath, interner: interner, typeSystem: types)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)

        let rawNames = [
            "kk_string_toList",
            "kk_string_toCharArray",
            "kk_string_toTypedArray",
            "kk_string_toSortedSet",
            "kk_string_toCollection",
            "kk_string_withIndex",
            "kk_string_iterator",
        ]
        for rawName in rawNames {
            XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected raw String materialization call: \(rawName)")
            XCTAssertTrue(ir.contains("@\(rawName)_flat"), "Missing flat String materialization call: \(rawName)_flat")
        }
    }

    func testLLVMBackendEmitsFlatStringListSequenceRuntimeCalls() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let text = interner.intern("a,b,c")
        let other = interner.intern("x,y,z")
        let delimiter = interner.intern(",")
        let textExpr = arena.appendExpr(.stringLiteral(text), type: types.stringType)
        let otherExpr = arena.appendExpr(.stringLiteral(other), type: types.stringType)
        let delimiterExpr = arena.appendExpr(.stringLiteral(delimiter), type: types.stringType)
        let ignoreCaseExpr = arena.appendExpr(.intLiteral(0), type: types.intType)
        let limitExpr = arena.appendExpr(.intLiteral(2), type: types.intType)
        let sizeExpr = arena.appendExpr(.intLiteral(2), type: types.intType)
        let stepExpr = arena.appendExpr(.intLiteral(1), type: types.intType)
        let partialExpr = arena.appendExpr(.intLiteral(1), type: types.intType)
        let fnPtrExpr = arena.appendExpr(.intLiteral(0), type: types.intType)
        let closureExpr = arena.appendExpr(.intLiteral(0), type: types.intType)

        var nextTemp: Int32 = 560
        func temporary(_ type: TypeID) -> KIRExprID {
            nextTemp += 1
            return arena.appendExpr(.temporary(nextTemp), type: type)
        }

        var body: [KIRInstruction] = [
            .constValue(result: textExpr, value: .stringLiteral(text)),
            .constValue(result: otherExpr, value: .stringLiteral(other)),
            .constValue(result: delimiterExpr, value: .stringLiteral(delimiter)),
            .constValue(result: ignoreCaseExpr, value: .intLiteral(0)),
            .constValue(result: limitExpr, value: .intLiteral(2)),
            .constValue(result: sizeExpr, value: .intLiteral(2)),
            .constValue(result: stepExpr, value: .intLiteral(1)),
            .constValue(result: partialExpr, value: .intLiteral(1)),
            .constValue(result: fnPtrExpr, value: .intLiteral(0)),
            .constValue(result: closureExpr, value: .intLiteral(0)),
        ]

        func appendScalarCall(_ calleeName: String, _ arguments: [KIRExprID]) {
            body.append(.call(
                symbol: nil,
                callee: interner.intern(calleeName),
                arguments: arguments,
                result: temporary(types.intType),
                canThrow: false,
                thrownResult: nil
            ))
        }

        func appendThrowingScalarCall(_ calleeName: String, _ arguments: [KIRExprID]) {
            body.append(.call(
                symbol: nil,
                callee: interner.intern(calleeName),
                arguments: arguments,
                result: temporary(types.intType),
                canThrow: true,
                thrownResult: temporary(types.intType)
            ))
        }

        appendScalarCall("kk_string_asIterable_flat", [textExpr])
        appendScalarCall("kk_string_asSequence_flat", [textExpr])
        appendScalarCall("kk_string_lines_flat", [textExpr])
        appendScalarCall("kk_string_lineSequence_flat", [textExpr])
        appendScalarCall("kk_string_split_flat", [textExpr, delimiterExpr])
        appendScalarCall("kk_string_split_limit_flat", [textExpr, delimiterExpr, ignoreCaseExpr, limitExpr])
        appendScalarCall("kk_string_splitToSequence_flat", [textExpr, delimiterExpr])
        appendScalarCall("kk_string_chunked_flat", [textExpr, sizeExpr])
        appendScalarCall("kk_string_chunked_sequence_flat", [textExpr, sizeExpr])
        appendThrowingScalarCall(
            "kk_string_chunked_sequence_transform_flat",
            [textExpr, sizeExpr, fnPtrExpr, closureExpr]
        )
        appendScalarCall("kk_string_windowed_default_flat", [textExpr, sizeExpr])
        appendScalarCall("kk_string_windowed_flat", [textExpr, sizeExpr, stepExpr])
        appendScalarCall("kk_string_windowed_partial_flat", [textExpr, sizeExpr, stepExpr, partialExpr])
        appendScalarCall("kk_string_windowedSequence_partial_flat", [textExpr, sizeExpr, stepExpr, partialExpr])
        appendThrowingScalarCall(
            "kk_string_windowedSequence_transform_flat",
            [textExpr, sizeExpr, stepExpr, partialExpr, fnPtrExpr, closureExpr]
        )
        appendScalarCall("kk_string_zipWithNext_flat", [textExpr])
        appendThrowingScalarCall("kk_string_zipWithNextTransform_flat", [textExpr, fnPtrExpr, closureExpr])
        appendScalarCall("kk_string_zip_flat", [textExpr, otherExpr])
        appendThrowingScalarCall("kk_string_zipTransform_flat", [textExpr, otherExpr, fnPtrExpr, closureExpr])
        body.append(.returnUnit)

        let main = KIRFunction(
            symbol: SymbolID(rawValue: 1207),
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: body,
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(main))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let backend = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let irPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ll").path

        try backend.emitLLVMIR(module: module, outputIRPath: irPath, interner: interner, typeSystem: types)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)

        let flatOnlyNames = [
            "kk_string_asIterable_flat",
            "kk_string_asSequence_flat",
            "kk_string_lines_flat",
            "kk_string_lineSequence_flat",
        ]
        for flatName in flatOnlyNames {
            XCTAssertTrue(ir.contains("@\(flatName)("), "Missing flat String list/sequence call: \(flatName)")
        }

        let rawNames = [
            "kk_string_split",
            "kk_string_split_limit",
            "kk_string_splitToSequence",
            "kk_string_chunked",
            "kk_string_chunked_sequence",
            "kk_string_chunked_sequence_transform",
            "kk_string_windowed_default",
            "kk_string_windowed",
            "kk_string_windowed_partial",
            "kk_string_windowedSequence_partial",
            "kk_string_windowedSequence_transform",
            "kk_string_zipWithNext",
            "kk_string_zipWithNextTransform",
            "kk_string_zip",
            "kk_string_zipTransform",
        ]
        for rawName in rawNames {
            XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected raw String list/sequence call: \(rawName)")
            XCTAssertTrue(ir.contains("@\(rawName)_flat"), "Missing flat String list/sequence call: \(rawName)_flat")
        }
    }

    func testLLVMBackendEmitsFlatStringByteArrayRuntimeCalls() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let text = interner.intern("abcdef")
        let textExpr = arena.appendExpr(.stringLiteral(text), type: types.stringType)
        let charsetExpr = arena.appendExpr(.intLiteral(0), type: types.intType)
        let startExpr = arena.appendExpr(.intLiteral(1), type: types.intType)
        let endExpr = arena.appendExpr(.intLiteral(4), type: types.intType)

        var nextTemp: Int32 = 600
        func temporary(_ type: TypeID) -> KIRExprID {
            nextTemp += 1
            return arena.appendExpr(.temporary(nextTemp), type: type)
        }

        var body: [KIRInstruction] = [
            .constValue(result: textExpr, value: .stringLiteral(text)),
            .constValue(result: charsetExpr, value: .intLiteral(0)),
            .constValue(result: startExpr, value: .intLiteral(1)),
            .constValue(result: endExpr, value: .intLiteral(4)),
        ]

        func appendByteArrayCall(_ calleeName: String, _ arguments: [KIRExprID]) {
            body.append(.call(
                symbol: nil,
                callee: interner.intern(calleeName),
                arguments: arguments,
                result: temporary(types.intType),
                canThrow: false,
                thrownResult: nil
            ))
        }

        appendByteArrayCall("kk_string_toByteArray_flat", [textExpr])
        appendByteArrayCall("kk_string_toByteArray_charset_flat", [textExpr, charsetExpr])
        appendByteArrayCall("kk_string_encodeToByteArray_flat", [textExpr])
        appendByteArrayCall("kk_string_encodeToByteArray_range_flat", [textExpr, startExpr, endExpr])
        appendByteArrayCall("kk_string_encodeToByteArray_charset_flat", [textExpr, charsetExpr])
        appendByteArrayCall("kk_string_byteInputStream_flat", [textExpr])
        appendByteArrayCall("kk_string_byteInputStream_charset_flat", [textExpr, charsetExpr])
        body.append(.returnUnit)

        let main = KIRFunction(
            symbol: SymbolID(rawValue: 1206),
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: body,
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(main))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let backend = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let irPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ll").path

        try backend.emitLLVMIR(module: module, outputIRPath: irPath, interner: interner, typeSystem: types)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)

        let rawNames = [
            "kk_string_toByteArray",
            "kk_string_toByteArray_charset",
            "kk_string_encodeToByteArray",
            "kk_string_encodeToByteArray_range",
            "kk_string_encodeToByteArray_charset",
        ]
        for rawName in rawNames {
            XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected raw String byte-array call: \(rawName)")
            XCTAssertTrue(ir.contains("@\(rawName)_flat"), "Missing flat String byte-array call: \(rawName)_flat")
        }
        let removedRawStringStreamNames = ["", "_charset"].map {
            ["kk", "string", "byteInputStream"].joined(separator: "_") + $0
        }
        for rawName in removedRawStringStreamNames {
            XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected removed raw String stream call: \(rawName)")
            XCTAssertTrue(ir.contains("@\(rawName)_flat"), "Missing flat String stream call: \(rawName)_flat")
        }
    }

    func testLlvmBindingsCandidatePathsHonorEnvironmentOverride() {
        // Create a temp file so the existence check passes.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".dylib")
        _ = FileManager.default.createFile(atPath: tempURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let overridePath = tempURL.path
        let resolvedPath = URL(fileURLWithPath: overridePath).standardized.path
        let paths = LLVMCAPIBindings.candidateLibraryPaths(environment: ["KSWIFTK_LLVM_DYLIB": overridePath])
        XCTAssertEqual(paths.first, resolvedPath)
        XCTAssertTrue(paths.contains("libLLVM.dylib"))

        // Non-existent paths are rejected and not added to candidates.
        let missing = "/tmp/does-not-exist-kswiftk-\(UUID().uuidString).dylib"
        let pathsWithMissing = LLVMCAPIBindings.candidateLibraryPaths(environment: ["KSWIFTK_LLVM_DYLIB": missing])
        XCTAssertFalse(pathsWithMissing.contains(missing))
    }

    func testLlvmBindingsCandidatePathsIncludeVersionedLibrariesFromLibraryPath() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let versionedLibrary = tempDirectory.appendingPathComponent("libLLVM-18.so")
        _ = FileManager.default.createFile(atPath: versionedLibrary.path, contents: Data())

        let paths = LLVMCAPIBindings.candidateLibraryPaths(environment: [
            "LIBRARY_PATH": tempDirectory.path,
        ])

        XCTAssertTrue(paths.contains(versionedLibrary.standardized.path))
    }

    func testCodegenFunctionSymbolSanitizesNames() {
        let interner = StringInterner()
        let fnName = CodegenSymbolSupport.cFunctionSymbol(
            for: KIRFunction(
                symbol: SymbolID(rawValue: 9),
                name: interner.intern("1 bad-name"),
                params: [],
                returnType: TypeSystem().unitType,
                body: [.returnUnit],
                isSuspend: false,
                isInline: false
            ),
            interner: interner
        )
        XCTAssertTrue(fnName.hasPrefix("kk_fn__1_bad_name_9"))
    }

    func testCodegenFunctionSymbolUsesJvmNameAnnotationForFunction() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let functionSymbol = symbols.define(
            kind: .function,
            name: interner.intern("originalName"),
            fqName: [interner.intern("originalName")],
            declSite: nil,
            visibility: .public
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: types.unitType),
            for: functionSymbol
        )
        symbols.setAnnotations(
            [MetadataAnnotationRecord(annotationFQName: "kotlin.jvm.JvmName", arguments: ["\"renamedForJava\""])],
            for: functionSymbol
        )

        let fnName = CodegenSymbolSupport.cFunctionSymbol(
            for: KIRFunction(
                symbol: functionSymbol,
                name: interner.intern("originalName"),
                params: [],
                returnType: types.unitType,
                body: [.returnUnit],
                isSuspend: false,
                isInline: false
            ),
            interner: interner,
            symbols: symbols
        )

        XCTAssertTrue(fnName.hasPrefix("kk_fn_renamedForJava_"))
    }
}

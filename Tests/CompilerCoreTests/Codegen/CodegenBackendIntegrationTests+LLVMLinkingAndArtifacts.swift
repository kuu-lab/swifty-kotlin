@testable import CompilerCore
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
        let takeCount = arena.appendExpr(.intLiteral(3), type: types.intType)
        let takeResult = arena.appendExpr(.temporary(13), type: types.stringType)
        let takeThrown = arena.appendExpr(.temporary(14), type: types.intType)
        let needleExpr = arena.appendExpr(.stringLiteral(needle), type: types.stringType)
        let startsWithResult = arena.appendExpr(.temporary(15), type: types.booleanType)
        let containsResult = arena.appendExpr(.temporary(16), type: types.booleanType)
        let indexOfResult = arena.appendExpr(.temporary(17), type: types.intType)
        let isBlankResult = arena.appendExpr(.temporary(18), type: types.booleanType)
        let ignoreCaseTrue = arena.appendExpr(.boolLiteral(true), type: types.booleanType)
        let charNeedle = arena.appendExpr(.charLiteral(UInt32(UnicodeScalar("d").value)), type: types.charType)
        let compareIgnoreCaseResult = arena.appendExpr(.temporary(19), type: types.intType)
        let lastIndexIgnoreCaseResult = arena.appendExpr(.temporary(20), type: types.intType)
        let indexOfCharResult = arena.appendExpr(.temporary(21), type: types.intType)
        let lastIndexOfCharResult = arena.appendExpr(.temporary(22), type: types.intType)
        let nullStringExpr = arena.appendExpr(.null, type: nullableStringType)
        let isNullOrEmptyResult = arena.appendExpr(.temporary(23), type: types.booleanType)
        let isNullOrBlankResult = arena.appendExpr(.temporary(24), type: types.booleanType)
        let contentEqualsResult = arena.appendExpr(.temporary(25), type: types.booleanType)
        let contentEqualsIgnoreCaseResult = arena.appendExpr(.temporary(26), type: types.booleanType)
        let equalsIgnoreCaseResult = arena.appendExpr(.temporary(27), type: types.booleanType)
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
                .call(symbol: nil, callee: interner.intern("kk_string_concat"), arguments: [leftExpr, rightExpr], result: concatResult, canThrow: false, thrownResult: nil),
                .constValue(result: paddedExpr, value: .stringLiteral(padded)),
                .call(symbol: nil, callee: interner.intern("kk_string_trim"), arguments: [paddedExpr], result: trimResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_trimStart"), arguments: [paddedExpr], result: trimStartResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_trimEnd"), arguments: [paddedExpr], result: trimEndResult, canThrow: false, thrownResult: nil),
                .constValue(result: takeCount, value: .intLiteral(3)),
                .call(symbol: nil, callee: interner.intern("kk_string_take"), arguments: [trimResult, takeCount], result: takeResult, canThrow: true, thrownResult: takeThrown),
                .constValue(result: needleExpr, value: .stringLiteral(needle)),
                .call(symbol: nil, callee: interner.intern("kk_string_startsWith"), arguments: [trimResult, needleExpr], result: startsWithResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_contains_str"), arguments: [trimResult, needleExpr], result: containsResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_indexOf"), arguments: [trimResult, needleExpr], result: indexOfResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_isBlank"), arguments: [trimResult], result: isBlankResult, canThrow: false, thrownResult: nil),
                .constValue(result: ignoreCaseTrue, value: .boolLiteral(true)),
                .constValue(result: charNeedle, value: .charLiteral(UInt32(UnicodeScalar("d").value))),
                .call(symbol: nil, callee: interner.intern("kk_string_compareToIgnoreCase"), arguments: [trimResult, needleExpr, ignoreCaseTrue], result: compareIgnoreCaseResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_lastIndexOf_ignoreCase"), arguments: [trimResult, needleExpr, takeCount, ignoreCaseTrue], result: lastIndexIgnoreCaseResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_indexOf_char"), arguments: [trimResult, charNeedle, takeCount, ignoreCaseTrue], result: indexOfCharResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_lastIndexOf_char"), arguments: [trimResult, charNeedle, takeCount, ignoreCaseTrue], result: lastIndexOfCharResult, canThrow: false, thrownResult: nil),
                .constValue(result: nullStringExpr, value: .null),
                .call(symbol: nil, callee: interner.intern("kk_string_isNullOrEmpty"), arguments: [nullStringExpr], result: isNullOrEmptyResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_isNullOrBlank"), arguments: [nullStringExpr], result: isNullOrBlankResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_contentEquals"), arguments: [trimResult, nullStringExpr], result: contentEqualsResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_contentEquals_ignoreCase"), arguments: [trimResult, needleExpr, ignoreCaseTrue], result: contentEqualsIgnoreCaseResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_string_equalsIgnoreCase"), arguments: [trimResult, nullStringExpr, ignoreCaseTrue], result: equalsIgnoreCaseResult, canThrow: false, thrownResult: nil),
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
        XCTAssertFalse(ir.contains("@kk_string_take("))
        XCTAssertFalse(ir.contains("@kk_string_startsWith("))
        XCTAssertFalse(ir.contains("@kk_string_contains_str("))
        XCTAssertFalse(ir.contains("@kk_string_indexOf("))
        XCTAssertFalse(ir.contains("@kk_string_isBlank("))
        XCTAssertFalse(ir.contains("@kk_string_compareToIgnoreCase("))
        XCTAssertFalse(ir.contains("@kk_string_lastIndexOf_ignoreCase("))
        XCTAssertFalse(ir.contains("@kk_string_indexOf_char("))
        XCTAssertFalse(ir.contains("@kk_string_lastIndexOf_char("))
        XCTAssertFalse(ir.contains("@kk_string_isNullOrEmpty("))
        XCTAssertFalse(ir.contains("@kk_string_isNullOrBlank("))
        XCTAssertFalse(ir.contains("@kk_string_contentEquals("))
        XCTAssertFalse(ir.contains("@kk_string_contentEquals_ignoreCase("))
        XCTAssertFalse(ir.contains("@kk_string_equalsIgnoreCase("))
        XCTAssertTrue(ir.contains("@kk_string_concat_flat"))
        XCTAssertTrue(ir.contains("@kk_string_trim_flat"))
        XCTAssertTrue(ir.contains("@kk_string_trimStart_flat"))
        XCTAssertTrue(ir.contains("@kk_string_trimEnd_flat"))
        XCTAssertTrue(ir.contains("@kk_string_take_flat"))
        XCTAssertTrue(ir.contains("@kk_string_startsWith_flat"))
        XCTAssertTrue(ir.contains("@kk_string_contains_str_flat"))
        XCTAssertTrue(ir.contains("@kk_string_indexOf_flat"))
        XCTAssertTrue(ir.contains("@kk_string_isBlank_flat"))
        XCTAssertTrue(ir.contains("@kk_string_compareToIgnoreCase_flat"))
        XCTAssertTrue(ir.contains("@kk_string_lastIndexOf_ignoreCase_flat"))
        XCTAssertTrue(ir.contains("@kk_string_indexOf_char_flat"))
        XCTAssertTrue(ir.contains("@kk_string_lastIndexOf_char_flat"))
        XCTAssertTrue(ir.contains("@kk_string_isNullOrEmpty_flat"))
        XCTAssertTrue(ir.contains("@kk_string_isNullOrBlank_flat"))
        XCTAssertTrue(ir.contains("@kk_string_contentEquals_flat"))
        XCTAssertTrue(ir.contains("@kk_string_contentEquals_ignoreCase_flat"))
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

        var nextTemp: Int32 = 100
        func temporary(_ type: TypeID) -> KIRExprID {
            nextTemp += 1
            return arena.appendExpr(.temporary(nextTemp), type: type)
        }

        var body: [KIRInstruction] = [
            .constValue(result: textExpr, value: .stringLiteral(text)),
            .constValue(result: nullStringExpr, value: .null),
            .constValue(result: radixExpr, value: .intLiteral(16)),
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

        appendParsingCall("kk_string_toBoolean", arguments: [nullStringExpr], resultType: types.booleanType)
        appendParsingCall("kk_string_toBooleanStrict", arguments: [textExpr], resultType: types.booleanType, canThrow: true)
        appendParsingCall("kk_string_toBooleanStrictOrNull", arguments: [textExpr], resultType: nullableBoolType)
        appendParsingCall("kk_string_toInt", arguments: [textExpr], resultType: types.intType, canThrow: true)
        appendParsingCall("kk_string_toInt_radix", arguments: [textExpr, radixExpr], resultType: types.intType, canThrow: true)
        appendParsingCall("kk_string_toIntOrNull", arguments: [textExpr], resultType: nullableIntType)
        appendParsingCall("kk_string_toIntOrNull_radix", arguments: [textExpr, radixExpr], resultType: nullableIntType, canThrow: true)
        appendParsingCall("kk_string_toUByteOrNull_radix", arguments: [textExpr, radixExpr], resultType: nullableUByteType, canThrow: true)
        appendParsingCall("kk_string_toUShortOrNull_radix", arguments: [textExpr, radixExpr], resultType: nullableUShortType, canThrow: true)
        appendParsingCall("kk_string_toUIntOrNull_radix", arguments: [textExpr, radixExpr], resultType: nullableUIntType, canThrow: true)
        appendParsingCall("kk_string_toULongOrNull_radix", arguments: [textExpr, radixExpr], resultType: nullableULongType, canThrow: true)
        appendParsingCall("kk_string_toDouble", arguments: [textExpr], resultType: types.doubleType, canThrow: true)
        appendParsingCall("kk_string_toDoubleOrNull", arguments: [textExpr], resultType: nullableDoubleType)
        appendParsingCall("kk_string_toLong", arguments: [textExpr], resultType: types.longType, canThrow: true)
        appendParsingCall("kk_string_toLongOrNull", arguments: [textExpr], resultType: nullableLongType)
        appendParsingCall("kk_string_toFloat", arguments: [textExpr], resultType: types.floatType, canThrow: true)
        appendParsingCall("kk_string_toFloatOrNull", arguments: [textExpr], resultType: nullableFloatType)
        appendParsingCall("kk_string_toShort", arguments: [textExpr], resultType: types.intType, canThrow: true)
        appendParsingCall("kk_string_toShortOrNull", arguments: [textExpr], resultType: nullableIntType)
        appendParsingCall("kk_string_toByte", arguments: [textExpr], resultType: types.intType, canThrow: true)
        appendParsingCall("kk_string_toByte_radix", arguments: [textExpr, radixExpr], resultType: types.intType, canThrow: true)
        appendParsingCall("kk_string_toByteOrNull", arguments: [textExpr], resultType: nullableIntType)
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
            "kk_string_toDouble",
            "kk_string_toDoubleOrNull",
            "kk_string_toLong",
            "kk_string_toLongOrNull",
            "kk_string_toFloat",
            "kk_string_toFloatOrNull",
            "kk_string_toShort",
            "kk_string_toShortOrNull",
            "kk_string_toByte",
            "kk_string_toByte_radix",
            "kk_string_toByteOrNull",
        ]
        for rawName in rawNames {
            XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected raw String parse call: \(rawName)")
            XCTAssertTrue(ir.contains("@\(rawName)_flat"), "Missing flat String parse call: \(rawName)_flat")
        }
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

        appendSelectionCall("kk_string_first", arguments: [textExpr], resultType: types.charType, canThrow: true)
        appendSelectionCall("kk_string_last", arguments: [textExpr], resultType: types.charType, canThrow: true)
        appendSelectionCall("kk_string_single", arguments: [textExpr], resultType: types.charType, canThrow: true)
        appendSelectionCall("kk_string_firstOrNull", arguments: [textExpr], resultType: nullableCharType)
        appendSelectionCall("kk_string_lastOrNull", arguments: [textExpr], resultType: nullableCharType)
        appendSelectionCall("kk_string_singleOrNull", arguments: [textExpr], resultType: nullableCharType)
        appendSelectionCall("kk_string_getOrNull", arguments: [textExpr, indexExpr], resultType: nullableCharType)
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

        let rawNames = [
            "kk_string_first",
            "kk_string_last",
            "kk_string_single",
            "kk_string_firstOrNull",
            "kk_string_lastOrNull",
            "kk_string_singleOrNull",
            "kk_string_getOrNull",
        ]
        for rawName in rawNames {
            XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected raw String char-selection call: \(rawName)")
            XCTAssertTrue(ir.contains("@\(rawName)_flat"), "Missing flat String char-selection call: \(rawName)_flat")
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

        appendCallbackCall("kk_string_count", resultType: types.intType)
        appendCallbackCall("kk_string_any", resultType: types.booleanType)
        appendCallbackCall("kk_string_all", resultType: types.booleanType)
        appendCallbackCall("kk_string_none", resultType: types.booleanType)
        appendCallbackCall("kk_string_indexOfFirst", resultType: types.intType)
        appendCallbackCall("kk_string_indexOfLast", resultType: types.intType)
        appendCallbackCall("kk_string_find", resultType: types.intType)
        appendCallbackCall("kk_string_findLast", resultType: types.intType)
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

        let rawNames = [
            "kk_string_count",
            "kk_string_any",
            "kk_string_all",
            "kk_string_none",
            "kk_string_indexOfFirst",
            "kk_string_indexOfLast",
            "kk_string_find",
            "kk_string_findLast",
        ]
        for rawName in rawNames {
            XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected raw String callback scalar call: \(rawName)")
            XCTAssertTrue(ir.contains("@\(rawName)_flat"), "Missing flat String callback scalar call: \(rawName)_flat")
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

        appendSearchCall("kk_string_indexOfAny_chars", targetRaw: charsRawExpr)
        appendSearchCall("kk_string_indexOfAny_strings", targetRaw: stringsRawExpr)
        appendSearchCall("kk_string_lastIndexOfAny_chars", targetRaw: charsRawExpr)
        appendSearchCall("kk_string_lastIndexOfAny_strings", targetRaw: stringsRawExpr)
        appendSearchCall("kk_string_findAnyOf", targetRaw: stringsRawExpr)
        appendSearchCall("kk_string_findLastAnyOf", targetRaw: stringsRawExpr)
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

        let rawNames = [
            "kk_string_indexOfAny_chars",
            "kk_string_indexOfAny_strings",
            "kk_string_lastIndexOfAny_chars",
            "kk_string_lastIndexOfAny_strings",
            "kk_string_findAnyOf",
            "kk_string_findLastAnyOf",
        ]
        for rawName in rawNames {
            XCTAssertFalse(ir.contains("@\(rawName)("), "Unexpected raw String indexOfAny call: \(rawName)")
            XCTAssertTrue(ir.contains("@\(rawName)_flat"), "Missing flat String indexOfAny call: \(rawName)_flat")
        }
    }

    func testLLVMBackendEmitsFlatStringMaterializationRuntimeCalls() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let text = interner.intern("abc")
        let textExpr = arena.appendExpr(.stringLiteral(text), type: types.stringType)

        var nextTemp: Int32 = 500
        func temporary(_ type: TypeID) -> KIRExprID {
            nextTemp += 1
            return arena.appendExpr(.temporary(nextTemp), type: type)
        }

        var body: [KIRInstruction] = [
            .constValue(result: textExpr, value: .stringLiteral(text)),
        ]

        func appendMaterializationCall(_ calleeName: String) {
            body.append(.call(
                symbol: nil,
                callee: interner.intern(calleeName),
                arguments: [textExpr],
                result: temporary(types.intType),
                canThrow: false,
                thrownResult: nil
            ))
        }

        appendMaterializationCall("kk_string_toList")
        appendMaterializationCall("kk_string_toCharArray")
        appendMaterializationCall("kk_string_toTypedArray")
        appendMaterializationCall("kk_string_toSortedSet")
        appendMaterializationCall("kk_string_withIndex")
        appendMaterializationCall("kk_string_iterator")
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

        appendScalarCall("kk_string_asIterable", [textExpr])
        appendScalarCall("kk_string_asSequence", [textExpr])
        appendScalarCall("kk_string_lines", [textExpr])
        appendScalarCall("kk_string_lineSequence", [textExpr])
        appendScalarCall("kk_string_split", [textExpr, delimiterExpr])
        appendScalarCall("kk_string_split_limit", [textExpr, delimiterExpr, ignoreCaseExpr, limitExpr])
        appendScalarCall("kk_string_splitToSequence", [textExpr, delimiterExpr])
        appendScalarCall("kk_string_chunked", [textExpr, sizeExpr])
        appendScalarCall("kk_string_chunked_sequence", [textExpr, sizeExpr])
        appendThrowingScalarCall("kk_string_chunked_sequence_transform", [textExpr, sizeExpr, fnPtrExpr, closureExpr])
        appendScalarCall("kk_string_windowed_default", [textExpr, sizeExpr])
        appendScalarCall("kk_string_windowed", [textExpr, sizeExpr, stepExpr])
        appendScalarCall("kk_string_windowed_partial", [textExpr, sizeExpr, stepExpr, partialExpr])
        appendScalarCall("kk_string_windowedSequence_partial", [textExpr, sizeExpr, stepExpr, partialExpr])
        appendThrowingScalarCall(
            "kk_string_windowedSequence_transform",
            [textExpr, sizeExpr, stepExpr, partialExpr, fnPtrExpr, closureExpr]
        )
        appendScalarCall("kk_string_zipWithNext", [textExpr])
        appendThrowingScalarCall("kk_string_zipWithNextTransform", [textExpr, fnPtrExpr, closureExpr])
        appendScalarCall("kk_string_zip", [textExpr, otherExpr])
        appendThrowingScalarCall("kk_string_zipTransform", [textExpr, otherExpr, fnPtrExpr, closureExpr])
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
            "kk_string_asIterable",
            "kk_string_asSequence",
            "kk_string_lines",
            "kk_string_lineSequence",
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

        appendByteArrayCall("kk_string_toByteArray", [textExpr])
        appendByteArrayCall("kk_string_toByteArray_charset", [textExpr, charsetExpr])
        appendByteArrayCall("kk_string_encodeToByteArray", [textExpr])
        appendByteArrayCall("kk_string_encodeToByteArray_range", [textExpr, startExpr, endExpr])
        appendByteArrayCall("kk_string_encodeToByteArray_charset", [textExpr, charsetExpr])
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

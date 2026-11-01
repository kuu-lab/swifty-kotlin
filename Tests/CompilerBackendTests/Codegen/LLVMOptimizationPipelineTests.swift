#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct LLVMOptimizationPipelineTests {
    @Test(arguments: [1, 2, 3])
    func optimizedIREliminatesTemporaryStackSlots(optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let source = """
        fun answer(): Int {
            var result = 20
            result = result + 22
            return result
        }
        """
        let unoptimized = try compileIR(source, level: .O0)
        let optimized = try compileIR(source, level: level)
        let hasUnoptimizedStackSlots = functionBody("answer", in: unoptimized).contains { $0.contains("alloca ") }
        // The per-frame stack-overflow guard's marker slot (KUU-1384, #7897)
        // escapes via ptrtoint by design, so it can never be promoted. Other
        // functions in the module (bundled stdlib) keep escaping GC root slots.
        let remainingStackSlots = functionBody("answer", in: optimized).filter { line in
            line.contains("alloca ") && !line.contains("%soe_marker")
        }
        let hasOptimizedStackSlots = !remainingStackSlots.isEmpty
        #expect(hasUnoptimizedStackSlots, "The probe must exercise stack-slot promotion.")
        #expect(!hasOptimizedStackSlots, "The new pass manager must eliminate temporary stack slots: \(remainingStackSlots)")
        // ABI lowering may retain an unbox call at the return boundary. LLVM
        // must still fold the arithmetic feeding that boundary to 42.
        // The guard's throw edge merges the return into a phi.
        let foldsArithmetic = optimized.contains("ret i64 42")
            || optimized.contains("@kk_unbox_int(i64 42)")
            || optimized.contains("phi i64 [ 42,")
        #expect(foldsArithmetic)
        let hasDataLayout = optimized.contains("target datalayout =")
        #expect(hasDataLayout)
    }

    private func functionBody(_ name: String, in ir: String) -> [Substring] {
        let lines = ir.split(separator: "\n")
        guard let start = lines.firstIndex(where: { $0.hasPrefix("define ") && $0.contains(name) }) else {
            return []
        }
        let end = lines[start...].firstIndex { $0 == "}" } ?? lines.endIndex
        return Array(lines[start ..< end])
    }

    @Test
    func optimizedIRRetainsFinalizedDebugMetadata() throws {
        let ir = try compileIR("fun answer(): Int = 42", level: .O2, debugInfo: true)
        #expect(ir.contains("!DICompileUnit("))
        #expect(ir.contains("isOptimized: true"))
        #expect(ir.contains("!DISubprogram("))
    }

    @Test
    func instructionsAfterRethrowAreSkippedUntilTheNextLabel() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()
        let condition = arena.appendExpr(.intLiteral(1), type: types.intType)
        let thrown = arena.appendExpr(.intLiteral(7), type: types.intType)
        let deadTail = arena.appendExpr(.temporary(0), type: types.intType)
        let function = KIRFunction(
            symbol: SymbolID(rawValue: 45_000),
            name: interner.intern("rethrowWithDeadTail"),
            params: [],
            returnType: types.unitType,
            body: [
                .constValue(result: condition, value: .intLiteral(1)),
                .constValue(result: thrown, value: .intLiteral(7)),
                .jumpIfEqual(lhs: condition, rhs: condition, target: 1),
                .rethrow(value: thrown),
                // Finally/catch lowering can leave expression work after a
                // rethrow. This arithmetic must not be emitted after the ret.
                .binary(op: .add, lhs: condition, rhs: thrown, result: deadTail),
                .label(1),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [arena.appendDecl(.function(function))])],
            arena: arena
        )
        let backend = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O2,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let irPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".ll").path
        defer { try? FileManager.default.removeItem(atPath: irPath) }

        try backend.emitLLVMIR(module: module, outputIRPath: irPath, interner: interner, typeSystem: types)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)
        #expect(!ir.isEmpty)
    }

    @Test
    func invalidIRIsRejectedBeforeRunningOptimization() throws {
        let bindings = try #require(LLVMCAPIBindings.loadUsable())
        let context = try #require(bindings.createContext())
        defer { bindings.disposeContext(context) }
        let module = try #require(bindings.createModule(name: "InvalidIR", context: context))
        defer { bindings.disposeModule(module) }
        let integerType = try #require(bindings.int64Type(context: context))
        let functionType = try #require(bindings.functionType(returnType: integerType, parameters: [], isVarArg: false))
        let function = try #require(bindings.addFunction(module: module, name: "missingTerminator", functionType: functionType))
        _ = try #require(bindings.appendBasicBlock(context: context, function: function, name: "entry"))
        try CodegenCriticalSection.withLinuxLLVMProcessLock(target: defaultTargetTriple()) {
            let triple = try #require(bindings.defaultTargetTriple())
            let machine = try #require(bindings.createTargetMachine(triple: triple, optLevel: .O2))
            defer { bindings.disposeTargetMachine(machine) }
            bindings.setTarget(module, triple: triple)
            #expect(bindings.applyTargetMachine(machine, to: module))
            let message = try #require(bindings.optimizeModule(module, targetMachine: machine, optLevel: .O2))
            #expect(message.contains("Invalid LLVM IR before optimization"))
            #expect(message.contains("terminator"))
            // Debug emission retains the existing O0 path.
            #expect(bindings.optimizeModule(module, targetMachine: machine, optLevel: .O0) == nil)
        }
    }

    @Test
    func invalidPipelineReportsLLVMErrorAndSubsequentOptimizationSucceeds() throws {
        let bindings = try #require(LLVMCAPIBindings.loadUsable())
        let context = try #require(bindings.createContext())
        defer { bindings.disposeContext(context) }
        let module = try #require(bindings.createModule(name: "PassErrors", context: context))
        defer { bindings.disposeModule(module) }
        try CodegenCriticalSection.withLinuxLLVMProcessLock(target: defaultTargetTriple()) {
            let triple = try #require(bindings.defaultTargetTriple())
            let machine = try #require(bindings.createTargetMachine(triple: triple, optLevel: .O2))
            defer { bindings.disposeTargetMachine(machine) }
            bindings.setTarget(module, triple: triple)
            #expect(bindings.applyTargetMachine(machine, to: module))

            let message = try #require(bindings.runPassPipeline(
                "kswiftk-invalid-pass", module: module, targetMachine: machine
            ))
            #expect(message.contains("kswiftk-invalid-pass"))
            #expect(bindings.optimizeModule(module, targetMachine: machine, optLevel: .O2) == nil)
        }
    }

    private func compileIR(_ source: String, level: OptimizationLevel, debugInfo: Bool = false) throws -> String {
        var ir = ""
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("optimization-\(UUID().uuidString).ll").path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }
            let options = CompilerOptions(
                moduleName: "OptimizationProbe", inputs: [path], outputPath: outputPath,
                emit: .llvmIR, target: defaultTargetTriple(), optLevel: level,
                debugInfo: debugInfo, includeStdlib: false
            )
            let context = CompilationContext(
                options: options, sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(), interner: StringInterner()
            )
            try runToKIR(context)
            try LoweringPhase().run(context)
            try CodegenPhase().run(context)
            let generatedPath = try #require(context.generatedLLVMIRPath)
            ir = try String(contentsOfFile: generatedPath, encoding: .utf8)
        }
        return ir
    }
}
#endif

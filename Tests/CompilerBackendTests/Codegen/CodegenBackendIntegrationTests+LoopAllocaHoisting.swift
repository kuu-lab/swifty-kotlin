@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    /// Slots requested while lowering a loop body (thrown slots, channel out
    /// values, string bridge scratch) must be allocated in the function entry
    /// block. Emitting them into the loop block makes the stack grow by one
    /// slot per iteration, which overflows on long-running loops.
    func testCodegenHoistsLoopBodyAllocasIntoEntryBlock() throws {
        let source = """
        class Counter {
            var value: Int = 0
            fun bump(): Int {
                value += 1
                return value
            }
        }

        fun main() {
            val counter = Counter()
            var total = 0
            for (i in 1..3) {
                total += counter.bump()
                total += "value=${counter.value}".length
            }
            println(total)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let llvmBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let llvmCtx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "LoopAllocaHoisting",
                emit: .llvmIR,
                outputPath: llvmBase
            )
            let llvmPath = try XCTUnwrap(llvmCtx.generatedLLVMIRPath)
            let ir = try String(contentsOfFile: llvmPath, encoding: .utf8)

            var blocksInCurrentFunction = 0
            var allocasOutsideEntry: [String] = []
            for line in ir.split(separator: "\n", omittingEmptySubsequences: false) {
                if line.hasPrefix("define ") {
                    blocksInCurrentFunction = 0
                } else if line.hasSuffix(":"), !line.hasPrefix(" ") {
                    blocksInCurrentFunction += 1
                } else if line.contains(" = alloca "), blocksInCurrentFunction > 1 {
                    allocasOutsideEntry.append(String(line))
                }
            }

            XCTAssertTrue(
                allocasOutsideEntry.isEmpty,
                "allocas must stay in the entry block, found: \(allocasOutsideEntry)"
            )
        }
    }
}

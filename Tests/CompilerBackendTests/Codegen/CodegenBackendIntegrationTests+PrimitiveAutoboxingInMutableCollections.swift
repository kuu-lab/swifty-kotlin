@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    /// A primitive argument passed to a mutable-collection element-insertion helper
    /// (`MutableList.add` / `add(index, _)` / `set` / `MutableSet.add`) must be
    /// boxed before storage. The element parameter is the erased type parameter `E`,
    /// so a raw primitive renders incorrectly via `toString()`:
    ///   - `Char` prints its numeric code point (the reported bug: `'d'` -> `100`),
    ///   - `Boolean` prints `0`/`1` and `false` collides with the null sentinel,
    ///   - `Double`/`Float` print the bit pattern misread as an `Int`.
    /// Elements created by `mutableListOf(...)` are already boxed, so the un-boxed
    /// `add` path produced a list with mixed element representations.
    ///
    /// `Int` elements are also verified: a boxed `Int` still prints as its decimal
    /// value, so the change does not regress the one primitive that happened to look
    /// correct when stored raw.
    func testPrimitiveArgumentBoxedWhenAddedToMutableCollections() throws {
        let source = """
        fun main() {
            // Reported bug: literal-built list seeds boxed Chars, add('d') must match.
            val chars = mutableListOf('a', 'b', 'c')
            chars.add('d')
            println(chars)

            // Generalization: an empty MutableList<Char>.
            val fresh = mutableListOf<Char>()
            fresh.add('x')
            fresh.add('y')
            println(fresh)

            // add(index, element) insertion.
            val ins = mutableListOf('a', 'c')
            ins.add(1, 'b')
            println(ins)

            // set(index, element) via indexed assignment.
            val seq = mutableListOf('a', 'b', 'c')
            seq[1] = 'z'
            println(seq)

            // MutableSet.add(Char).
            val set = mutableSetOf<Char>()
            set.add('m')
            println(set)

            // Boolean elements must render as true/false, not 0/1.
            val flags = mutableListOf<Boolean>()
            flags.add(true)
            flags.add(false)
            println(flags)

            // Double elements must render as their value, not the raw bit pattern.
            val reals = mutableListOf<Double>()
            reals.add(1.5)
            println(reals)

            // Regression: Int elements still render as their decimal value.
            val nums = mutableListOf<Int>()
            nums.add(100)
            println(nums)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "PrimitiveAutoboxingInMutableCollections",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [a, b, c, d]
                [x, y]
                [a, b, c]
                [a, z, c]
                [m]
                [true, false]
                [1.5]
                [100]
                """
                + "\n"
            )
        }
    }
}

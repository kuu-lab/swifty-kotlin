#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension LoweringABIAndPropertyRegressionTests {
    @Test
    func testSourceBackedDurationParsingDoesNotUseExternalBridges() throws {
        let source = """
        import kotlin.time.Duration

        fun parseDuration(value: String): Duration = Duration.parse(value)

        fun parseDurationOrNull(value: String): Duration? = Duration.parseOrNull(value)

        fun parseDurationIso(value: String): Duration = Duration.parseIsoString(value)

        fun parseDurationIsoOrNull(value: String): Duration? = Duration.parseIsoStringOrNull(value)
        """
        try withTemporaryFile(contents: source) { path in
            // Executable KIR includes bundled source bodies, which is necessary
            // to inspect the parser implementation reached through Duration.kt.
            let context = makeCompilationContext(inputs: [path], emit: .executable)
            try runToLowering(context)
            let module = try #require(context.kir)
            let sema = try #require(context.sema)
            let removedBridgeNames: Set<String> = [
                "kk_duration_parse",
                "kk_duration_parseOrNull",
                "kk_duration_parseIsoString",
                "kk_duration_parseIsoStringOrNull",
            ]
            var parserCallees: Set<String> = []
            var durationCallees: Set<String> = []
            var externalDurationCalls: [String] = []

            for function in findAllKIRFunctions(in: module) {
                for instruction in function.body {
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                        continue
                    }
                    let calleeName = context.interner.resolve(callee)
                    if calleeName.localizedCaseInsensitiveContains("duration") ||
                        calleeName.localizedCaseInsensitiveContains("parse")
                    {
                        durationCallees.insert(calleeName)
                    }
                    if calleeName.contains("durationParseRawOrNull") {
                        parserCallees.insert(calleeName)
                    }
                    if removedBridgeNames.contains(where: { calleeName.contains($0) }) {
                        externalDurationCalls.append(calleeName)
                    } else if let symbol = instructionCallSymbol(instruction),
                              let linkName = sema.symbols.externalLinkName(for: symbol),
                              removedBridgeNames.contains(linkName)
                    {
                        externalDurationCalls.append(linkName)
                    }
                }
            }

            #expect(
                !parserCallees.isEmpty,
                "Expected durationParseRawOrNull in lowered duration parsing; duration-related callees: \(durationCallees.sorted())"
            )
            #expect(
                externalDurationCalls.isEmpty,
                "Duration parsing must not use removed runtime bridges: \(externalDurationCalls)"
            )
        }
    }

    private func instructionCallSymbol(_ instruction: KIRInstruction) -> SymbolID? {
        guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return nil }
        return symbol
    }
}
#endif

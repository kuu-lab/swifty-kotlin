import Foundation

final class InlinePerfStats {
    var expandRounds = 0
    var expandRoundInstructions = 0

    var callExpansions = 0
    var callExpansionInput = 0
    var lambdaExpansions = 0

    var resolveLambdaCalls = 0
    var resolveLambdaScans = 0

    var definedQueries = 0
    var definedScans = 0

    var indexNanos: UInt64 = 0
    var nestedBodylessNanos: UInt64 = 0
    var transformNanos: UInt64 = 0
    var residueNanos: UInt64 = 0

    static var enabled: Bool {
        ProcessInfo.processInfo.environment["KSWIFTK_INLINE_STATS"] != nil
    }

    func takeSplit() -> UInt64 {
        let now = DispatchTime.now().uptimeNanoseconds
        defer { splitMark = now }
        return now - splitMark
    }

    private var splitMark = DispatchTime.now().uptimeNanoseconds

    func printIfEnabled() {
        guard Self.enabled else { return }
        FileHandle.standardError.write(Data(report().utf8))
    }

    private func report() -> String {
        func ms(_ nanos: UInt64) -> String {
            String(format: "%.1f", Double(nanos) / 1_000_000)
        }
        return """
        InlineLowering stats:
          sections: index=\(ms(indexNanos))ms nestedBodyless=\(ms(nestedBodylessNanos))ms transform=\(ms(transformNanos))ms residue=\(ms(residueNanos))ms
          expandInlineCalls: rounds=\(expandRounds) inputInstructions=\(expandRoundInstructions)
          expandInlineCall=\(callExpansions) inputInstructions=\(callExpansionInput) expandLambdaBody=\(lambdaExpansions)
          resolveLambdaFunction: calls=\(resolveLambdaCalls) scannedInstructions=\(resolveLambdaScans)
          exprIsDefined: queries=\(definedQueries) scannedInstructions=\(definedScans)
        """
    }
}

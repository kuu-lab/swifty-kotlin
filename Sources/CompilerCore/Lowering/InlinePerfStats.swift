import Foundation

/// Opt-in attribution for `InlineLoweringPass` (`KSWIFTK_INLINE_STATS=1`).
/// The pass is the largest single lowering on real files (KUU-3777), so each
/// repeated scan reports how many instructions it visited and the three
/// `run` sections report wall time. Counters are plain integer increments
/// collected unconditionally — cheap next to the scans they measure — and
/// the report prints once at the end of `run` when the environment variable
/// is set.
final class InlinePerfStats {
    /// Whole-body rescans of `expandInlineCalls` and the total input size
    /// they walked (one round rewrites the entire caller body).
    var expandRounds = 0
    var expandRoundInstructions = 0

    /// `expandInlineCall` / `expandLambdaBody` invocations and the callee
    /// instructions they processed/emitted.
    var callExpansions = 0
    var callExpansionInput = 0
    var lambdaExpansions = 0

    /// `resolveLambdaFunction` queries and the caller-body instructions they
    /// visited (producer count, `symbolRef` lookup, factory scan).
    var resolveLambdaCalls = 0
    var resolveLambdaScans = 0

    /// `exprIsDefined` queries and the emitted-body instructions they visited.
    var definedQueries = 0
    var definedScans = 0

    var indexNanos: UInt64 = 0
    var nestedBodylessNanos: UInt64 = 0
    var transformNanos: UInt64 = 0
    var residueNanos: UInt64 = 0

    static var enabled: Bool {
        ProcessInfo.processInfo.environment["KSWIFTK_INLINE_STATS"] != nil
    }

    /// Nanoseconds since the previous `takeSplit` (or since init on the first
    /// call). Cheap enough to run unconditionally — one `DispatchTime` read.
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

/// Numbered Kotlin function classifiers encode their parameters and return
/// type as type arguments, rather than as an ordinary nominal class.
package struct KlibFunctionTypeShape {
    package let arity: Int
    package let isSuspend: Bool

    package init?(classifierName: String) {
        let prefixes = [("kotlin.Function", false), ("kotlin.coroutines.SuspendFunction", true)]
        guard let (prefix, isSuspend) = prefixes.first(where: { classifierName.hasPrefix($0.0) }) else { return nil }
        let suffix = String(classifierName.dropFirst(prefix.count))
        guard !suffix.isEmpty, suffix.allSatisfy({ $0.isASCII && $0.isNumber }),
              let arity = Int(suffix), arity <= 255, String(arity) == suffix else { return nil }
        self.arity = arity
        self.isSuspend = isSuspend
    }
}

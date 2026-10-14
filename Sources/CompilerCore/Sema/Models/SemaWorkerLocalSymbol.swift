/// A closed allocation delta: ordinary scalar locals have no callable,
/// nominal, delegate, capture or synthetic-parameter metadata. Lambda and
/// object allocations require a separate contract before they can be joined.
struct SemaWorkerLocalSymbol: Sendable {
    let symbol: SemanticSymbol
    let type: TypeID
}

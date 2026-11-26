private let abi = RuntimeABISectionBuilder("Random")

public extension RuntimeABISpec {
    static let randomFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_random_seed_entropy"),
        abi.th("__kk_random_nextInt_rangeObject", "receiver range outThrown"),
        abi.th("__kk_random_nextLong_rangeObject", "receiver range outThrown"),
        abi.th("__kk_random_nextULong_ulongRange", "receiver range outThrown"),
        abi.th("__kk_random_nextUInt_uintRange", "receiver range outThrown"),
        abi.nt("__kk_secure_random_get_instance"),
        abi.nt("__kk_secure_random_set_seed", "receiver seed"),
        abi.nt("__kk_secure_random_generate_seed", "receiver size"),
        abi.nt("__kk_secure_random_next_bytes", "receiver array"),
    ]
}

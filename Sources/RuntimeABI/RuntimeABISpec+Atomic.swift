private let abi = RuntimeABISectionBuilder("Atomic")

public extension RuntimeABISpec {
    static let atomicFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("kk_atomic_int_create", "initial"),
        abi.nt("__kk_atomic_int_load", "receiver"),
        abi.nt("__kk_atomic_int_store", "receiver value"),
        abi.nt("__kk_atomic_int_exchange", "receiver new"),
        abi.nt("kk_atomic_int_compareAndSet", "receiver expect update"),
        abi.nt("__kk_atomic_int_compareAndExchange", "receiver expect update"),

        abi.nt("__kk_atomic_int_fetchAndAdd", "receiver delta"),
        abi.nt("__kk_atomic_int_addAndFetch", "receiver delta"),
        abi.nt("__kk_atomic_int_fetchAndIncrement", "receiver"),
        abi.nt("__kk_atomic_int_fetchAndDecrement", "receiver"),
        abi.nt("__kk_atomic_int_incrementAndFetch", "receiver"),
        abi.nt("__kk_atomic_int_decrementAndFetch", "receiver"),
        abi.nt("kk_atomic_long_create", "initial"),
        abi.nt("__kk_atomic_long_load", "receiver"),
        abi.nt("__kk_atomic_long_store", "receiver value"),
        abi.nt("__kk_atomic_long_exchange", "receiver new"),
        abi.nt("kk_atomic_long_compareAndSet", "receiver expect update"),
        abi.nt("__kk_atomic_long_compareAndExchange", "receiver expect update"),

        abi.nt("__kk_atomic_long_fetchAndAdd", "receiver delta"),
        abi.nt("__kk_atomic_long_addAndFetch", "receiver delta"),
        abi.nt("__kk_atomic_long_fetchAndIncrement", "receiver"),
        abi.nt("__kk_atomic_long_fetchAndDecrement", "receiver"),
        abi.nt("__kk_atomic_long_incrementAndFetch", "receiver"),
        abi.nt("__kk_atomic_long_decrementAndFetch", "receiver"),
        abi.th("kk_atomic_int_array_create", "size"),
        abi.th("kk_atomic_int_array_size", "receiver"),
        // KSP-672: raw synchronized-core bridges (bounds checks live in Kotlin).
        abi.nt("__kk_atomic_int_array_load", "receiver index"),
        abi.nt("__kk_atomic_int_array_store", "receiver index value"),
        abi.nt("__kk_atomic_int_array_exchange", "receiver index newValue"),
        abi.nt("__kk_atomic_int_array_compareAndExchange", "receiver index expect update"),

        abi.nt("__kk_atomic_int_array_fetchAndAdd", "receiver index delta"),
        abi.nt("__kk_atomic_int_array_addAndFetch", "receiver index delta"),
        abi.th("kk_atomic_long_array_create", "size"),
        abi.th("kk_atomic_long_array_size", "receiver"),
        // KSP-672: raw synchronized-core bridges (bounds checks live in Kotlin).
        abi.nt("__kk_atomic_long_array_load", "receiver index"),
        abi.nt("__kk_atomic_long_array_store", "receiver index value"),
        abi.nt("__kk_atomic_long_array_exchange", "receiver index newValue"),
        abi.nt("__kk_atomic_long_array_compareAndExchange", "receiver index expect update"),

        abi.nt("__kk_atomic_long_array_fetchAndAdd", "receiver index delta"),
        abi.nt("__kk_atomic_long_array_addAndFetch", "receiver index delta"),
        abi.nt("kk_atomic_ref_array_exchangeAt", "receiver index newValue"),

        abi.nt("kk_atomic_bool_create", "initial"),
        abi.nt("__kk_atomic_bool_load", "receiver"),
        abi.nt("__kk_atomic_bool_store", "receiver value"),
        abi.nt("__kk_atomic_bool_exchange", "receiver new"),
        abi.nt("__kk_atomic_bool_compareAndExchange", "receiver expect update"),

        abi.nt("kk_atomic_ref_array_of", "elements"),
        abi.nt("kk_atomic_ref_create", "initial"),
        abi.nt("__kk_atomic_ref_load", "receiver"),
        abi.nt("__kk_atomic_ref_store", "receiver value"),
        abi.nt("__kk_atomic_ref_exchange", "receiver new"),
        abi.nt("__kk_atomic_ref_compareAndExchange", "receiver expect update"),

        abi.th("kk_atomic_ref_array_compareAndSetAt", "receiver index expect update"),
    ]
}

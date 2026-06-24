package kotlin.properties

// MIGRATION-PROP-001
// Delegates object: observable, vetoable, notNull factory functions.
// Migration source: Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticPropertyDelegateStubs.swift
//   registerSyntheticPropertyInterfaceStubs — Delegates synthetic object, observable/vetoable/notNull stubs
// Runtime backing: Sources/Runtime/RuntimeDelegates.swift
//   kk_observable_create/get_value/set_value
//   kk_vetoable_create/get_value/set_value
//   kk_notNull_create/get_value/set_value
//
// NOTE: Not yet wired into the compiler pipeline.
// StdlibDelegateLoweringPass still intercepts Delegates.observable, Delegates.vetoable, and
// Delegates.notNull call sites and rewrites them to kk_*_create ABI calls; delegate accessors
// use kk_*_get_value / kk_*_set_value. This file is the migration target; wiring (and removal
// of corresponding entries in StdlibDelegateLoweringPass.swift and the Delegates synthetic stubs
// in HeaderHelpers+SyntheticPropertyDelegateStubs.swift) happens in a follow-up task.

import kotlin.reflect.KProperty

private class NotNullVar<T : Any> : ReadWriteProperty<Any?, T> {
    private var value: T? = null

    public override fun getValue(thisRef: Any?, property: KProperty<*>): T {
        return value ?: throw IllegalStateException(
            "Property ${property.name} should be initialized before get."
        )
    }

    public override fun setValue(thisRef: Any?, property: KProperty<*>, value: T) {
        this.value = value
    }
}

/**
 * Standard property delegates.
 */
public object Delegates {
    /**
     * Returns a property delegate for a read/write property that calls a specified callback function
     * when changed, allowing the callback to veto the modification.
     *
     * @param initialValue the initial value of the property.
     * @param onChange the callback which is called before a change to the property value is attempted.
     *  The value of the property hasn't been changed yet, when this callback is invoked.
     *  If the callback returns `true` the value of the property is being set to the new value,
     *  and if the callback returns `false` the new value is discarded and the property remains its old value.
     */
    public inline fun <T> vetoable(
        initialValue: T,
        crossinline onChange: (property: KProperty<*>, oldValue: T, newValue: T) -> Boolean
    ): ReadWriteProperty<Any?, T> =
        object : ObservableProperty<T>(initialValue) {
            override fun beforeChange(property: KProperty<*>, oldValue: T, newValue: T): Boolean =
                onChange(property, oldValue, newValue)
        }

    /**
     * Returns a property delegate for a read/write property that calls a specified callback function
     * when changed.
     *
     * @param initialValue the initial value of the property.
     * @param onChange the callback which is called after the change of the property is made.
     *  The value of the property has already been changed when this callback is invoked.
     */
    public inline fun <T> observable(
        initialValue: T,
        crossinline onChange: (property: KProperty<*>, oldValue: T, newValue: T) -> Unit
    ): ReadWriteProperty<Any?, T> =
        object : ObservableProperty<T>(initialValue) {
            override fun afterChange(property: KProperty<*>, oldValue: T, newValue: T) =
                onChange(property, oldValue, newValue)
        }

    /**
     * Returns a property delegate for a read/write property with a non-`null` value that is not defined
     * until after the first assignment. Trying to read the property before the initial value has been
     * assigned results in an exception.
     */
    public fun <T : Any> notNull(): ReadWriteProperty<Any?, T> = NotNullVar()
}

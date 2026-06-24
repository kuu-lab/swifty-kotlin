package kotlin.properties

// MIGRATION-PROP-001
// Abstract base class for observable/vetoable delegate properties.
// Migration source: Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticPropertyDelegateStubs.swift
//   registerObservablePropertyStub (ObservableProperty synthetic stub with beforeChange/afterChange/getValue/setValue)
// Runtime backing: Sources/Runtime/RuntimeDelegates.swift
//   kk_observable_create, kk_observable_get_value, kk_observable_set_value
//   kk_vetoable_create, kk_vetoable_get_value, kk_vetoable_set_value
//
// NOTE: Not yet wired into the compiler pipeline.
// StdlibDelegateLoweringPass still intercepts observable/vetoable factory calls and rewrites them
// to kk_observable_create / kk_vetoable_create ABI calls; delegate get/set use kk_*_get_value /
// kk_*_set_value. This file is the migration target; wiring (and removal of the corresponding
// entries in StdlibDelegateLoweringPass.swift and the synthetic ObservableProperty stub) happens
// in a follow-up task.

import kotlin.reflect.KProperty

/**
 * Implements the core logic of a property delegate for a read/write property that calls callback
 * functions when changed.
 * @param initialValue the initial value of the property.
 */
public abstract class ObservableProperty<V>(initialValue: V) : ReadWriteProperty<Any?, V> {
    private var value = initialValue

    /**
     * The callback which is called before a change to the property value is attempted.
     * The value of the property hasn't been changed yet, when this callback is invoked.
     * If the callback returns `true` the value of the property is being set to the new value,
     * and if the callback returns `false` the new value is discarded and the property remains its old value.
     */
    protected open fun beforeChange(property: KProperty<*>, oldValue: V, newValue: V): Boolean = true

    /**
     * The callback which is called after the change of the property is made. The value of the property
     * has already been changed when this callback is invoked.
     */
    protected open fun afterChange(property: KProperty<*>, oldValue: V, newValue: V): Unit {}

    public override fun getValue(thisRef: Any?, property: KProperty<*>): V {
        return value
    }

    public override fun setValue(thisRef: Any?, property: KProperty<*>, value: V) {
        val oldValue = this.value
        if (!beforeChange(property, oldValue, value)) {
            return
        }
        this.value = value
        afterChange(property, oldValue, value)
    }
}

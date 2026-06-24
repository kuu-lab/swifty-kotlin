package kotlin.properties

// MIGRATION-PROP-001
// Property delegate interfaces: ReadOnlyProperty, ReadWriteProperty.
// Migration source: Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticPropertyDelegateStubs.swift
//   registerSyntheticPropertyInterfaceStubs (ReadOnlyProperty, ReadWriteProperty synthetic stubs)
//
// NOTE: Not yet wired into the compiler pipeline.
// Synthetic stubs in HeaderHelpers+SyntheticPropertyDelegateStubs.swift still supply these
// types to the type system. This file is the migration target; wiring (and removal of the
// corresponding synthetic stub registrations) happens in a follow-up task.

import kotlin.reflect.KProperty

/**
 * Base interface that can be used for implementing property delegates of read-only properties.
 *
 * This is provided only for convenience; you don't have to extend this interface
 * as long as your property delegate has methods with the same signatures.
 *
 * @param T the type of object which owns the delegated property.
 * @param V the type of the property value.
 */
public fun interface ReadOnlyProperty<in T, out V> {
    /**
     * Returns the value of the property for the given object.
     * @param thisRef the object for which the value is requested.
     * @param property the metadata for the property.
     * @return the property value.
     */
    public operator fun getValue(thisRef: T, property: KProperty<*>): V
}

/**
 * Base interface that can be used for implementing property delegates of read-write properties.
 *
 * This is provided only for convenience; you don't have to extend this interface
 * as long as your property delegate has methods with the same signatures.
 *
 * @param T the type of object which owns the delegated property.
 * @param V the type of the property value.
 */
public interface ReadWriteProperty<in T, V> : ReadOnlyProperty<T, V> {
    /**
     * Returns the value of the property for the given object.
     * @param thisRef the object for which the value is requested.
     * @param property the metadata for the property.
     * @return the property value.
     */
    public override operator fun getValue(thisRef: T, property: KProperty<*>): V

    /**
     * Sets the value of the property for the given object.
     * @param thisRef the object for which the value is requested.
     * @param property the metadata for the property.
     * @param value the value to set.
     */
    public operator fun setValue(thisRef: T, property: KProperty<*>, value: V)
}

/**
 * What a person typed into a program survives a refine of it.
 *
 * A refined program is a new program with a new state class, so its state starts from its own init(). carryState takes
 * that fresh state and fills in, field by field, what the old program's state held: a field of the same name whose value
 * is of the same kind keeps the old value, every other field keeps the fresh one. A field the refine added starts at its
 * init value; one it removed is dropped; one whose kind changed (a number that became a string) starts fresh.
 *
 * The result is only a candidate: the caller runs the new program's view on it once and falls back to init() when that
 * fails, because an array element of an old class can lack a field the new code reads (see VeraPreview.load).
 */

import { RuntimeValue, VeraNumberValue, VeraStringValue, VeraBooleanValue, VeraArrayValue, VeraObjectValue } from './VeraInterpreter'

export function carryState(fresh: RuntimeValue, old: RuntimeValue): RuntimeValue {
  if (fresh instanceof VeraObjectValue && old instanceof VeraObjectValue) {
    let fields: Map<string, RuntimeValue> = new Map<string, RuntimeValue>()
    fresh.fields.forEach((value: RuntimeValue, name: string) => {
      let before = old.fields.get(name)
      fields.set(name, before === undefined ? value : carryState(value, before))
    })
    return new VeraObjectValue(fresh.classIdentity, fields)
  }
  if (fresh instanceof VeraArrayValue && old instanceof VeraArrayValue) {
    // An array's elements are kept whole when they are what the fresh array holds, or when there is nothing to compare with.
    if (fresh.elements.length === 0 || old.elements.length === 0) { return old.elements.length === 0 ? fresh : old }
    return sameKind(fresh.elements[0], old.elements[0]) ? old : fresh
  }
  return sameKind(fresh, old) ? old : fresh
}

/** Whether two values are of one kind: both numbers, both strings, both booleans, both arrays, or objects of one class. */
function sameKind(a: RuntimeValue, b: RuntimeValue): boolean {
  if (a instanceof VeraNumberValue) { return b instanceof VeraNumberValue }
  if (a instanceof VeraStringValue) { return b instanceof VeraStringValue }
  if (a instanceof VeraBooleanValue) { return b instanceof VeraBooleanValue }
  if (a instanceof VeraArrayValue) { return b instanceof VeraArrayValue }
  if (a instanceof VeraObjectValue) { return b instanceof VeraObjectValue && a.classIdentity === b.classIdentity }
  return false
}

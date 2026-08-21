/**
 * Dynamic-ArkTS port of the static VERA runtime in vera-static-hello.
 *
 * Same algorithm, same control flow; only the type system differs. The static
 * original could not be built for this device, so this measures the VERA
 * pipeline on the ArkTS runtime that will actually run -- see README for what
 * that does and does not establish.
 *
 * Conversions applied, all mechanical:
 *   parseConstant       rewritten on JSON.parse; the JsonElement API it used
 *                       does not exist in dynamic ArkTS
 *   'use static'        removed
 *   final class         -> class
 *   int / double        -> number
 *   Any                 -> BytecodeValue union
 *   x instanceof number -> typeof x === 'number'   (and string / boolean)
 *   Int.toDouble(a & b) -> a & b        JS bitwise already yields a number
 *   x.toInt()           -> Math.trunc(x) where an index is needed
 */


/**
 * Static ArkTS port of src/bytecode.ts and src/bytecodeAssembly.ts.
 *
 * VERA values cross a dynamic language boundary, so they are carried as a
 * nullable Object. Dynamic ArkTS has no Any; every use already funnels through
 * numberValue / truthy / scalar / sameValue, which narrow with typeof before
 * casting, so the union costs nothing at the call sites.
 */
export type BytecodeValue = Object | null | undefined

export class BytecodeArray {
  values: BytecodeValue[]

  constructor(values: BytecodeValue[]) {
    this.values = values
  }
}

export class BytecodeObject {
  fields: Map<string, BytecodeValue> = new Map<string, BytecodeValue>()
}

export class BytecodeFunction {
  kind: string = 'BytecodeFunction'
  address: number
  arity: number
  name: string | undefined
  params: string[]

  constructor(address: number, arity: number, name: string | undefined, params: string[]) {
    this.address = address
    this.arity = arity
    this.name = name
    this.params = params
  }
}

/**
 * A nominal instruction replaces TypeScript's structural discriminated union.
 * Only the fields used by op are read by the VM.
 */
export class Instruction {
  op: string
  index: number = 0
  name: string = ''
  operator: string = ''
  target: number = 0
  arity: number = 0
  count: number = 0
  keys: string[] = []

  constructor(op: string) {
    this.op = op
  }
}

export class BytecodeProgram {
  constants: BytecodeValue[]
  instructions: Instruction[]

  constructor(constants: BytecodeValue[], instructions: Instruction[]) {
    this.constants = constants
    this.instructions = instructions
  }
}

export class RuntimeResult {
  globals: Map<string, BytecodeValue>
  stack: BytecodeValue[]

  constructor(globals: Map<string, BytecodeValue>, stack: BytecodeValue[]) {
    this.globals = globals
    this.stack = stack
  }
}

export class VeraRuntimeError extends Error {
  errorCode: string
  fix: string

  constructor(errorCode: string, message: string, fix: string) {
    super(message)
    this.errorCode = errorCode
    this.fix = fix
  }
}

export class BytecodeAssemblyError extends Error {
  errorCode: string = 'VBC_ASM_PARSE'
  fix: string = 'Regenerate the .vbc file or fix the malformed short assembly line.'
  line: number

  constructor(message: string, line: number) {
    super(message)
    this.line = line
  }
}

class CallFrame {
  ip: number
  globals: Map<string, BytecodeValue>

  constructor(ip: number, globals: Map<string, BytecodeValue>) {
    this.ip = ip
    this.globals = globals
  }
}

export function runBytecode(program: BytecodeProgram): RuntimeResult {
  let vm = new VeraVM(program)
  return vm.run()
}

export function runBytecodeAssembly(source: string): RuntimeResult {
  return runBytecode(parseBytecodeAssembly(source))
}

export function formatBytecodeValue(value: BytecodeValue): string {
  if (value == null) {
    return 'null'
  }
  if (typeof value === 'string') {
    return value as string
  }
  if (typeof value === 'number') {
    return (value as number).toString()
  }
  if (typeof value === 'boolean') {
    return (value as boolean).toString()
  }
  if (value instanceof BytecodeFunction) {
    let fn = value as BytecodeFunction
    let name = fn.name == undefined ? '<anonymous>' : fn.name
    return `<function ${name}>`
  }
  if (value instanceof BytecodeArray) {
    let array = value as BytecodeArray
    let items: string[] = []
    for (let item of array.values) {
      items.push(formatBytecodeValue(item))
    }
    return '[' + items.join(', ') + ']'
  }
  if (value instanceof BytecodeObject) {
    let record = value as BytecodeObject
    let fields: string[] = []
    for (let entry of record.fields) {
      fields.push(entry[0] + ': ' + formatBytecodeValue(entry[1]))
    }
    return '{' + fields.join(', ') + '}'
  }
  return '<value>'
}

export function formatRuntimeResult(runtime: RuntimeResult): string {
  let lines: string[] = []
  for (let entry of runtime.globals) {
    if (entry[0] != 'ui' && !(entry[1] instanceof BytecodeFunction)) {
      lines.push(entry[0] + ' = ' + formatBytecodeValue(entry[1]))
    }
  }
  if (lines.length == 0) {
    if (runtime.stack.length == 0) {
      return 'Program completed with no output values.'
    }
    return 'stack = ' + formatBytecodeValue(new BytecodeArray(runtime.stack))
  }
  return lines.join('\n')
}

export class VeraVM {
  private ip: number = 0
  private stack: BytecodeValue[] = []
  private globals: Map<string, BytecodeValue> = new Map<string, BytecodeValue>()
  private callStack: CallFrame[] = []
  private program: BytecodeProgram
  private steps: number = 0
  private maxSteps: number
  private externalGlobals: Map<string, BytecodeValue> | undefined = undefined

  constructor(program: BytecodeProgram, maxSteps: number = 100000) {
    this.program = program
    this.maxSteps = maxSteps
  }

  hasFunction(name: string): boolean {
    let value = this.globals.get(name)
    return value instanceof BytecodeFunction
  }

  invokeFunction(name: string, args: BytecodeValue[], maxSteps: number = 20000): RuntimeResult {
    let value = this.globals.get(name)
    if (!(value instanceof BytecodeFunction)) {
      throw new VeraRuntimeError('R_CALL_UNSUPPORTED', `Undefined handler '${name}'`, 'Use the name of a declared VERA function.')
    }
    let callee = value as BytecodeFunction
    if (args.length != callee.arity) {
      throw new VeraRuntimeError('R_CALL_UNSUPPORTED', `Function '${name}' expects ${callee.arity} arguments`, 'Pass the expected event payload.')
    }
    if (this.callStack.length != 0 || this.externalGlobals != undefined) {
      throw new VeraRuntimeError('R_CALL_UNSUPPORTED', 'The VM is already executing a function', 'Wait for the current handler to complete.')
    }
    this.externalGlobals = new Map<string, BytecodeValue>(this.globals)
    this.stack = []
    for (let index: number = 0; index < callee.params.length; index += 1) {
      let parameter = callee.params[index]
      let argument = args[index]
      if (parameter != undefined) {
        this.globals.set(parameter, argument == undefined ? null : argument)
      }
    }
    this.ip = callee.address
    this.steps = 0
    this.maxSteps = maxSteps
    try {
      return this.run()
    } catch (error) {
      let retained = this.externalGlobals
      if (retained != undefined) {
        this.globals.clear()
        for (let entry of retained) {
          this.globals.set(entry[0], entry[1])
        }
      }
      this.externalGlobals = undefined
      this.callStack = []
      this.stack = []
      this.ip = this.program.instructions.length
      // ArkTS only permits throwing Error subtypes, and a catch binding is
      // Object; the rethrow has to be narrowed. Every throw in this VM is a
      // VeraRuntimeError or BytecodeAssemblyError, both Error subclasses.
      throw error as Error
    }
  }

  run(): RuntimeResult {
    while (this.ip < this.program.instructions.length) {
      this.steps += 1
      if (this.steps > this.maxSteps) {
        throw new VeraRuntimeError(
          'R_EXECUTION_LIMIT',
          `Execution exceeded ${this.maxSteps} instructions`,
          'Use a terminating loop or a smaller computation.'
        )
      }
      let instruction = this.program.instructions[this.ip]
      if (instruction == undefined) {
        break
      }
      this.ip += 1
      switch (instruction.op) {
        case 'HALT':
          if (this.externalGlobals != undefined) {
            return this.completeExternalCall(null)
          }
          return new RuntimeResult(this.globals, this.stack)
        case 'PUSH_CONST': {
          let constant = this.program.constants[instruction.index]
          this.stack.push(constant == undefined ? null : constant)
          break
        }
        case 'PUSH_NULL':
          this.stack.push(null)
          break
        case 'LOAD':
          this.stack.push(this.load(instruction.name))
          break
        case 'STORE': {
          let value = this.pop()
          this.globals.set(instruction.name, value)
          this.stack.push(value)
          break
        }
        case 'DETACH':
          this.globals.delete(instruction.name)
          break
        case 'POP':
          this.pop()
          break
        case 'DUP':
          this.stack.push(this.peek())
          break
        case 'UNARY':
          this.stack.push(this.applyUnary(instruction.operator, this.pop()))
          break
        case 'BINARY': {
          let right = this.pop()
          let left = this.pop()
          this.stack.push(this.applyBinary(instruction.operator, left, right))
          break
        }
        case 'JUMP':
          this.ip = instruction.target
          break
        case 'JUMP_IF_TRUE': {
          let value = this.pop()
          if (this.truthy(value)) {
            this.ip = instruction.target
          }
          break
        }
        case 'JUMP_IF_FALSE': {
          let value = this.pop()
          if (!this.truthy(value)) {
            this.ip = instruction.target
          }
          break
        }
        case 'CALL':
          this.call(instruction.arity)
          break
        case 'RETURN':
          if (this.callStack.length == 0) {
            if (this.externalGlobals != undefined) {
              return this.completeExternalCall(this.pop())
            }
            return new RuntimeResult(this.globals, this.stack)
          }
          this.returnFromCall()
          break
        case 'MAKE_ARRAY': {
          let values = this.popMany(instruction.count)
          this.stack.push(new BytecodeArray(values))
          break
        }
        case 'MAKE_OBJECT': {
          let values = this.popMany(instruction.keys.length)
          let record = new BytecodeObject()
          for (let index: number = 0; index < instruction.keys.length; index += 1) {
            let key = instruction.keys[index]
            let value = values[index]
            if (key != undefined && value != undefined) {
              record.fields.set(key, value)
            }
          }
          this.stack.push(record)
          break
        }
        case 'GET_FIELD': {
          let record = this.pop()
          this.stack.push(this.getField(record, instruction.name))
          break
        }
        case 'SET_FIELD': {
          let value = this.pop()
          let record = this.pop()
          this.setField(record, instruction.name, value)
          this.stack.push(value)
          break
        }
        case 'GET_INDEX': {
          let index = this.pop()
          let target = this.pop()
          this.stack.push(this.getIndex(target, index))
          break
        }
        case 'SET_INDEX': {
          let value = this.pop()
          let index = this.pop()
          let target = this.pop()
          this.setIndex(target, index, value)
          this.stack.push(value)
          break
        }
        default:
          throw new VeraRuntimeError('R_UNKNOWN_OPCODE', `Unknown opcode '${instruction.op}'`, 'Validate the bytecode program before running it.')
      }
    }
    return new RuntimeResult(this.globals, this.stack)
  }

  reset(): void {
    this.ip = 0
    this.steps = 0
    this.stack = []
    this.globals.clear()
    this.callStack = []
    this.externalGlobals = undefined
  }

  private completeExternalCall(returnValue: BytecodeValue): RuntimeResult {
    let retained = this.externalGlobals
    if (retained == undefined) {
      throw new VeraRuntimeError('R_CALL_UNSUPPORTED', 'Missing external call state', 'Reset the VM and retry the handler.')
    }
    let retainedMap = retained as Map<string, BytecodeValue>
    for (let name of retainedMap.keys()) {
      if (this.globals.has(name)) {
        let current = this.globals.get(name)
        retainedMap.set(name, current == undefined ? null : current)
      }
    }
    this.globals.clear()
    for (let entry of retainedMap) {
      this.globals.set(entry[0], entry[1])
    }
    this.externalGlobals = undefined
    this.stack = [returnValue]
    this.ip = this.program.instructions.length
    return new RuntimeResult(this.globals, this.stack)
  }

  private call(arity: number): void {
    let args = this.popMany(arity)
    let value = this.pop()
    if (!(value instanceof BytecodeFunction)) {
      throw new VeraRuntimeError('R_CALL_UNSUPPORTED', 'Only bytecode function calls are supported', 'Call a declared VERA function.')
    }
    let callee = value as BytecodeFunction
    if (arity != callee.arity) {
      let functionName = callee.name == undefined ? '<anonymous>' : callee.name
      throw new VeraRuntimeError('R_CALL_UNSUPPORTED', `Function '${functionName}' expects ${callee.arity} arguments`, 'Pass the expected number of arguments.')
    }
    this.callStack.push(new CallFrame(this.ip, new Map<string, BytecodeValue>(this.globals)))
    this.globals.clear()
    let frame = this.callStack[this.callStack.length - 1]
    if (frame != undefined) {
      for (let entry of frame.globals) {
        this.globals.set(entry[0], entry[1])
      }
    }
    for (let index: number = 0; index < callee.params.length; index += 1) {
      let name = callee.params[index]
      let argument = args[index]
      if (name != undefined && argument != undefined) {
        this.globals.set(name, argument)
      }
    }
    this.ip = callee.address
  }

  private returnFromCall(): void {
    let value = this.pop()
    let frame = this.callStack.pop()
    if (frame == undefined) {
      throw new VeraRuntimeError('R_STACK_UNDERFLOW', 'Missing call frame', 'Fix bytecode generation for function calls.')
    }
    this.globals.clear()
    for (let entry of frame.globals) {
      this.globals.set(entry[0], entry[1])
    }
    this.stack.push(value)
    this.ip = frame.ip
  }

  private load(name: string): BytecodeValue {
    if (!this.globals.has(name)) {
      throw new VeraRuntimeError('R_UNDEFINED_VARIABLE', `Undefined variable '${name}'`, 'Emit STORE for the variable before LOAD, or fix the variable name.')
    }
    let value = this.globals.get(name)
    return value == undefined ? null : value
  }

  private pop(): BytecodeValue {
    let value = this.stack.pop()
    if (value == undefined) {
      throw new VeraRuntimeError('R_STACK_UNDERFLOW', 'Stack underflow', 'Fix bytecode generation so every consuming opcode has enough produced stack values.')
    }
    return value
  }

  private peek(): BytecodeValue {
    let value = this.stack[this.stack.length - 1]
    if (value == undefined) {
      throw new VeraRuntimeError('R_STACK_UNDERFLOW', 'Stack underflow', 'Fix bytecode generation so every consuming opcode has enough produced stack values.')
    }
    return value
  }

  private popMany(count: number): BytecodeValue[] {
    let values: BytecodeValue[] = []
    for (let index: number = 0; index < count; index += 1) {
      values.unshift(this.pop())
    }
    return values
  }

  private applyUnary(operator: string, value: BytecodeValue): BytecodeValue {
    switch (operator) {
      case '+':
        return this.numberValue(value)
      case '-':
        return -this.numberValue(value)
      case '~':
        return ~this.numberValue(value)
      case '!':
        return !this.truthy(value)
      default:
        throw new VeraRuntimeError('R_UNKNOWN_OPERATOR', `Unknown unary operator '${operator}'`, 'Validate the bytecode program before running it.')
    }
  }

  private applyBinary(operator: string, left: BytecodeValue, right: BytecodeValue): BytecodeValue {
    switch (operator) {
      case '+':
        if (typeof left === 'string' || typeof right === 'string') {
          return this.scalar(left) + this.scalar(right)
        }
        return this.numberValue(left) + this.numberValue(right)
      case '-':
        return this.numberValue(left) - this.numberValue(right)
      case '*':
        return this.numberValue(left) * this.numberValue(right)
      case '/':
        return this.numberValue(left) / this.numberValue(right)
      case '%':
        return this.numberValue(left) % this.numberValue(right)
      case '**':
        return this.numberValue(left) ** this.numberValue(right)
      case '==':
      case '===':
        return this.sameValue(left, right)
      case '!=':
      case '!==':
        return !this.sameValue(left, right)
      case '<':
        return this.numberValue(left) < this.numberValue(right)
      case '<=':
        return this.numberValue(left) <= this.numberValue(right)
      case '>':
        return this.numberValue(left) > this.numberValue(right)
      case '>=':
        return this.numberValue(left) >= this.numberValue(right)
      case '&':
        return this.numberValue(left) & this.numberValue(right)
      case '|':
        return this.numberValue(left) | this.numberValue(right)
      case '^':
        return this.numberValue(left) ^ this.numberValue(right)
      case '<<':
        return this.numberValue(left) << this.numberValue(right)
      case '>>':
        return this.numberValue(left) >> this.numberValue(right)
      case '>>>':
        return this.numberValue(left) >>> this.numberValue(right)
      case '&&':
        return this.truthy(left) && this.truthy(right)
      case '||':
        return this.truthy(left) || this.truthy(right)
      default:
        throw new VeraRuntimeError('R_UNKNOWN_OPERATOR', `Unknown binary operator '${operator}'`, 'Validate the bytecode program before running it.')
    }
  }

  private getField(value: BytecodeValue, name: string): BytecodeValue {
    if (!(value instanceof BytecodeObject)) {
      throw new VeraRuntimeError('R_FIELD_READ_INVALID', `Cannot read field '${name}'`, 'Ensure the field-read target is an object value.')
    }
    let record = value as BytecodeObject
    let field = record.fields.get(name)
    return field == undefined ? null : field
  }

  private setField(value: BytecodeValue, name: string, field: BytecodeValue): void {
    if (!(value instanceof BytecodeObject)) {
      throw new VeraRuntimeError('R_FIELD_WRITE_INVALID', `Cannot set field '${name}'`, 'Ensure the field-write target is an object value.')
    }
    let record = value as BytecodeObject
    record.fields.set(name, field)
  }

  private getIndex(value: BytecodeValue, index: BytecodeValue): BytecodeValue {
    let position = this.numberValue(index)
    if (value instanceof BytecodeArray) {
      let array = value as BytecodeArray
      let item = array.values[position]
      return item == undefined ? null : item
    }
    if (typeof value === 'string') {
      let text = value as string
      let character = text[position]
      return character == undefined ? null : character
    }
    throw new VeraRuntimeError('R_INDEX_READ_INVALID', 'Cannot index value', 'Ensure the indexed target is an array or string.')
  }

  private setIndex(value: BytecodeValue, index: BytecodeValue, item: BytecodeValue): void {
    if (!(value instanceof BytecodeArray)) {
      throw new VeraRuntimeError('R_INDEX_WRITE_INVALID', 'Cannot assign indexed value', 'Ensure the indexed assignment target is an array.')
    }
    let array = value as BytecodeArray
    array.values[this.numberValue(index)] = item
  }

  private numberValue(value: BytecodeValue): number {
    if (!(typeof value === 'number')) {
      throw new VeraRuntimeError('R_EXPECTED_NUMBER', 'Expected number', 'Change the expression to produce a number before using a numeric operator.')
    }
    return value as number
  }

  private truthy(value: BytecodeValue): boolean {
    if (value == null) {
      return false
    }
    if (typeof value === 'boolean') {
      return value as boolean
    }
    if (typeof value === 'number') {
      return (value as number) != 0.0
    }
    if (typeof value === 'string') {
      return (value as string).length != 0
    }
    return true
  }

  private scalar(value: BytecodeValue): string {
    if (value == null) {
      return 'null'
    }
    if (typeof value === 'string') {
      return value as string
    }
    if (typeof value === 'number') {
      return (value as number).toString()
    }
    if (typeof value === 'boolean') {
      return (value as boolean).toString()
    }
    return '[object]'
  }

  private sameValue(left: BytecodeValue, right: BytecodeValue): boolean {
    if (left == null || right == null) {
      return left == null && right == null
    }
    if (typeof left === 'number' && typeof right === 'number') {
      return (left as number) == (right as number)
    }
    if (typeof left === 'string' && typeof right === 'string') {
      return (left as string) == (right as string)
    }
    if (typeof left === 'boolean' && typeof right === 'boolean') {
      return (left as boolean) == (right as boolean)
    }
    return left === right
  }
}

export function parseBytecodeAssembly(source: string): BytecodeProgram {
  let lines = source.replaceAll('\r\n', '\n').split('\n')
  let header = lines.length == 0 ? '' : lines[0].trim()
  if (header != 'vbc1') {
    throw new BytecodeAssemblyError('Missing vbc1 header', 1)
  }

  let constants: BytecodeValue[] = []
  let instructions: Instruction[] = []

  for (let index: number = 1; index < lines.length; index += 1) {
    let lineNumber: number = index + 1
    let line = lines[index].trim()
    if (line.length == 0 || line.startsWith(';')) {
      continue
    }
    let parts = splitLine(line)
    let mnemonic = parts[0]
    let argument = parts[1]
    if (mnemonic == 'c') {
      constants.push(parseConstant(argument, lineNumber))
      continue
    }
    instructions.push(parseInstruction(mnemonic, argument, lineNumber))
  }

  return new BytecodeProgram(constants, instructions)
}

function parseConstant(source: string, line: number): BytecodeValue {
  let parsed: BytecodeValue
  try {
    parsed = JSON.parse(source) as BytecodeValue
  } catch (error) {
    throw new BytecodeAssemblyError('Invalid constant', line)
  }
  return reviveConstant(parsed, line)
}

/**
 * Rebuilds VERA container values from parsed JSON.
 *
 * The static original recognised only null, string, boolean, number and
 * BytecodeFunction, so an array or plain-object constant reached the end and
 * threw 'Unsupported constant value'. Both containers are handled here.
 *
 * Note this is NOT known to be the cause of the pairs program failing on the
 * real runtime: that artifact contains no array or object constants at all
 * (16 numbers, 43 strings, 1 boolean, 8 functions). This closes a genuine gap
 * in constant coverage; the pairs failure is still unexplained.
 */
function reviveConstant(value: BytecodeValue, line: number): BytecodeValue {
  if (value === null || value === undefined) {
    return null
  }
  if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
    return value
  }
  if (Array.isArray(value)) {
    let items: BytecodeValue[] = []
    for (let item of value as BytecodeValue[]) {
      items.push(reviveConstant(item, line))
    }
    return new BytecodeArray(items)
  }
  let record = value as Record<string, BytecodeValue>
  if (record['kind'] === 'BytecodeFunction') {
    let rawName = record['name']
    let name: string | undefined = typeof rawName === 'string' ? rawName as string : undefined
    let params: string[] = []
    let rawParams = record['params']
    if (Array.isArray(rawParams)) {
      for (let param of rawParams as BytecodeValue[]) {
        params.push(param as string)
      }
    }
    return new BytecodeFunction(record['address'] as number, record['arity'] as number, name, params)
  }
  let object = new BytecodeObject()
  for (let key of Object.keys(record)) {
    object.fields.set(key, reviveConstant(record[key], line))
  }
  return object
}

function parseInstruction(mnemonic: string, argument: string, line: number): Instruction {
  let instruction: Instruction
  switch (mnemonic) {
    case 'hlt':
      return new Instruction('HALT')
    case 'pc':
      instruction = new Instruction('PUSH_CONST')
      instruction.index = numberArg(argument, line)
      return instruction
    case 'pn':
      return new Instruction('PUSH_NULL')
    case 'ld':
      instruction = new Instruction('LOAD')
      instruction.name = stringArg(argument, line)
      return instruction
    case 'st':
      instruction = new Instruction('STORE')
      instruction.name = stringArg(argument, line)
      return instruction
    case 'det':
      instruction = new Instruction('DETACH')
      instruction.name = stringArg(argument, line)
      return instruction
    case 'pop':
      return new Instruction('POP')
    case 'dup':
      return new Instruction('DUP')
    case 'un':
      instruction = new Instruction('UNARY')
      instruction.operator = stringArg(argument, line)
      return instruction
    case 'bin':
      instruction = new Instruction('BINARY')
      instruction.operator = stringArg(argument, line)
      return instruction
    case 'jmp':
      instruction = new Instruction('JUMP')
      instruction.target = numberArg(argument, line)
      return instruction
    case 'jt':
      instruction = new Instruction('JUMP_IF_TRUE')
      instruction.target = numberArg(argument, line)
      return instruction
    case 'jf':
      instruction = new Instruction('JUMP_IF_FALSE')
      instruction.target = numberArg(argument, line)
      return instruction
    case 'call':
      instruction = new Instruction('CALL')
      instruction.arity = numberArg(argument, line)
      return instruction
    case 'ret':
      return new Instruction('RETURN')
    case 'arr':
      instruction = new Instruction('MAKE_ARRAY')
      instruction.count = numberArg(argument, line)
      return instruction
    case 'obj':
      instruction = new Instruction('MAKE_OBJECT')
      instruction.keys = stringArrayArg(argument, line)
      return instruction
    case 'gf':
      instruction = new Instruction('GET_FIELD')
      instruction.name = stringArg(argument, line)
      return instruction
    case 'sf':
      instruction = new Instruction('SET_FIELD')
      instruction.name = stringArg(argument, line)
      return instruction
    case 'gi':
      return new Instruction('GET_INDEX')
    case 'si':
      return new Instruction('SET_INDEX')
    default:
      throw new BytecodeAssemblyError(`Unknown opcode '${mnemonic}'`, line)
  }
}

function splitLine(line: string): string[] {
  let firstSpace: number = line.indexOf(' ')
  if (firstSpace < 0) {
    return [line, '']
  }
  return [line.slice(0, firstSpace), line.slice(firstSpace + 1)]
}

function numberArg(value: string, line: number): number {
  try {
    return JSON.parse(value) as number
  } catch (error) {
    throw new BytecodeAssemblyError('Expected integer argument', line)
  }
}

function stringArg(value: string, line: number): string {
  try {
    return JSON.parse(value) as string
  } catch (error) {
    throw new BytecodeAssemblyError('Expected string argument', line)
  }
}

function stringArrayArg(value: string, line: number): string[] {
  try {
    let parsed = JSON.parse(value) as BytecodeValue
    let result: string[] = []
    if (Array.isArray(parsed)) {
      for (let element of parsed as BytecodeValue[]) {
        result.push(element as string)
      }
    }
    return result
  } catch (error) {
    throw new BytecodeAssemblyError('Expected string array argument', line)
  }
}

export abstract class RuntimeValue {
}
export class VeraIntValue extends RuntimeValue {
    value: number;
    constructor(r105: number) { super(); this.value = r105; }
}
export class VeraNumberValue extends RuntimeValue {
    value: number;
    constructor(q105: number) { super(); this.value = q105; }
}
export class VeraStringValue extends RuntimeValue {
    value: string;
    constructor(p105: string) { super(); this.value = p105; }
}
export class VeraBooleanValue extends RuntimeValue {
    value: boolean;
    constructor(o105: boolean) { super(); this.value = o105; }
}
export class VeraNullValue extends RuntimeValue {
}
export class VeraArrayValue extends RuntimeValue {
    elements: RuntimeValue[];
    constructor(n105: RuntimeValue[]) { super(); this.elements = n105; }
}
export class VeraObjectValue extends RuntimeValue {
    classIdentity: string;
    fields: Map<string, RuntimeValue> = new Map<string, RuntimeValue>();
    constructor(l105: string, m105: Map<string, RuntimeValue>) {
        super();
        this.classIdentity = l105;
        this.fields = m105;
    }
}
export class Cell {
    value: RuntimeValue;
    constructor(k105: RuntimeValue) { this.value = k105; }
}
export class FunctionValue extends RuntimeValue {
    name: string;
    captures: Cell[];
    constructor(i105: string, j105: Cell[]) { super(); this.name = i105; this.captures = j105; }
}
export class ExternalFunctionValue extends RuntimeValue {
    module: string;
    funcName: string;
    constructor(g105: string, h105: string) { super(); this.module = g105; this.funcName = h105; }
}
export const NULL_VALUE: VeraNullValue = new VeraNullValue();
export class RuntimeTrap extends Error {
    trapCode: string;
    constructor(e105: string, f105: string) { super(f105); this.trapCode = e105; }
}
export abstract class HostEnvironment {
    abstract invoke(a105: string, b105: string, c105: RuntimeValue[], d105: boolean): RuntimeValue;
}
export class EmptyHostEnvironment extends HostEnvironment {
    invoke(w104: string, x104: string, y104: RuntimeValue[], z104: boolean): RuntimeValue {
        throw new RuntimeTrap('R0015', `external function unavailable: ${w104}.${x104}`);
    }
}
export class Instruction {
    op: string;
    value: string = '';
    numValue: number = 0;
    boolValue: boolean = false;
    slot: number = 0;
    name: string = '';
    module: string = '';
    operator: string = '';
    integer: boolean = false;
    target: number = 0;
    count: number = 0;
    awaited: boolean = false;
    classIdentity: string = '';
    fields: string[] = [];
    functionName: string = '';
    captures: number[] = [];
    constructor(v104: string) { this.op = v104; }
}
export class BytecodeFunction {
    name: string;
    parameterCount: number;
    localCount: number;
    isAsync: boolean;
    instructions: Instruction[];
    constructor(q104: string, r104: number, s104: number, t104: boolean, u104: Instruction[]) {
        this.name = q104;
        this.parameterCount = r104;
        this.localCount = s104;
        this.isAsync = t104;
        this.instructions = u104;
    }
}
export class BytecodeModule {
    functions: BytecodeFunction[];
    entryCandidates: string[];
    constructor(o104: BytecodeFunction[], p104: string[]) {
        this.functions = o104;
        this.entryCandidates = p104;
    }
}
class Frame {
    stack: RuntimeValue[] = [];
    locals: Cell[];
    pc: number = 0;
    fn: BytecodeFunction;
    captures: Cell[];
    constructor(k104: BytecodeFunction, l104: Cell[], m104: RuntimeValue[]) {
        this.fn = k104;
        this.captures = l104;
        this.locals = [];
        for (let n104: number = 0; n104 < k104.localCount; n104++) {
            this.locals.push(new Cell(n104 < m104.length ? m104[n104] : NULL_VALUE));
        }
    }
}
const MIN_INT: number = -2147483648;
const MAX_INT: number = 2147483647;
export class VirtualMachine {
    private functions: Map<string, BytecodeFunction> = new Map<string, BytecodeFunction>();
    private functionValues: Map<string, FunctionValue> = new Map<string, FunctionValue>();
    private externalValues: Map<string, ExternalFunctionValue> = new Map<string, ExternalFunctionValue>();
    private host: HostEnvironment;
    private maxSteps: number;
    private steps: number = 0;
    constructor(g104: BytecodeModule, h104: HostEnvironment = new EmptyHostEnvironment(), i104: number = 5000000) {
        this.host = h104;
        this.maxSteps = i104;
        for (let j104 of g104.functions) {
            this.functions.set(j104.name, j104);
        }
    }
    stepsExecuted(): number { return this.steps; }
    execute(d104: string, e104: RuntimeValue[] = []): RuntimeValue {
        let f104 = this.functions.get(d104);
        if (f104 == undefined) {
            throw new RuntimeTrap('R0001', `entry function not found: ${d104}`);
        }
        this.steps = 0;
        return this.run(new Frame(f104, [], e104));
    }
    private run(a103: Frame): RuntimeValue {
        while (a103.pc < a103.fn.instructions.length) {
            this.steps += 1;
            if (this.steps > this.maxSteps) {
                throw new RuntimeTrap('R0017', `execution exceeded ${this.maxSteps} steps`);
            }
            let b103 = a103.fn.instructions[a103.pc];
            a103.pc += 1;
            switch (b103.op) {
                case 'push-int':
                    a103.stack.push(new VeraIntValue(this.checked(parseInt(b103.value))));
                    break;
                case 'push-number':
                    a103.stack.push(new VeraNumberValue(b103.numValue));
                    break;
                case 'push-string':
                    a103.stack.push(new VeraStringValue(b103.value));
                    break;
                case 'push-boolean':
                    a103.stack.push(new VeraBooleanValue(b103.boolValue));
                    break;
                case 'push-null':
                    a103.stack.push(NULL_VALUE);
                    break;
                case 'load-local':
                    a103.stack.push(this.cell(a103.locals, b103.slot).value);
                    break;
                case 'store-local':
                    this.cell(a103.locals, b103.slot).value = this.pop(a103);
                    break;
                case 'load-capture':
                    a103.stack.push(this.cell(a103.captures, b103.slot).value);
                    break;
                case 'store-capture':
                    this.cell(a103.captures, b103.slot).value = this.pop(a103);
                    break;
                case 'load-function': {
                    let c104 = this.functionValues.get(b103.name);
                    if (c104 == undefined) {
                        c104 = new FunctionValue(b103.name, []);
                        this.functionValues.set(b103.name, c104);
                    }
                    a103.stack.push(c104);
                    break;
                }
                case 'load-external': {
                    let a104 = `${b103.module}::${b103.name}`;
                    let b104 = this.externalValues.get(a104);
                    if (b104 == undefined) {
                        b104 = new ExternalFunctionValue(b103.module, b103.name);
                        this.externalValues.set(a104, b104);
                    }
                    a103.stack.push(b104);
                    break;
                }
                case 'pop':
                    this.pop(a103);
                    break;
                case 'duplicate':
                    a103.stack.push(a103.stack[a103.stack.length - 1]);
                    break;
                case 'unary':
                    a103.stack.push(this.unary(b103.operator, this.pop(a103)));
                    break;
                case 'binary': {
                    let y103 = this.pop(a103);
                    let z103 = this.pop(a103);
                    a103.stack.push(this.binary(b103.operator, b103.integer, z103, y103));
                    break;
                }
                case 'jump':
                    a103.pc = b103.target;
                    break;
                case 'jump-if-false':
                    if (!this.asBoolean(this.pop(a103))) {
                        a103.pc = b103.target;
                    }
                    break;
                case 'call':
                    this.callInst(a103, b103);
                    break;
                case 'return':
                    return this.pop(a103);
                case 'make-array':
                    a103.stack.push(new VeraArrayValue(this.take(a103, b103.count)));
                    break;
                case 'array-push': {
                    let w103 = this.pop(a103);
                    let x103 = this.asArray(this.pop(a103));
                    if (x103.elements.length >= 4096) {
                        throw new RuntimeTrap('R0022', 'array length limit reached (4096)');
                    }
                    x103.elements.push(w103);
                    a103.stack.push(new VeraIntValue(x103.elements.length));
                    break;
                }
                case 'array-pop': {
                    let v103 = this.asArray(this.pop(a103));
                    if (v103.elements.length === 0) {
                        throw new RuntimeTrap('R0023', 'pop from an empty array');
                    }
                    a103.stack.push(v103.elements.pop() as RuntimeValue);
                    break;
                }
                case 'length': {
                    let u103 = this.pop(a103);
                    if (u103 instanceof VeraArrayValue) {
                        a103.stack.push(new VeraIntValue(u103.elements.length));
                    }
                    else if (u103 instanceof VeraStringValue) {
                        a103.stack.push(new VeraIntValue(u103.value.length));
                    }
                    else {
                        throw new RuntimeTrap('R0008', 'expected array or string');
                    }
                    break;
                }
                case 'string-symbols': {
                    let r103 = this.pop(a103);
                    if (!(r103 instanceof VeraStringValue)) {
                        throw new RuntimeTrap('R0008', 'expected string');
                    }
                    let s103: RuntimeValue[] = [];
                    for (let t103 of Array.from(r103.value)) {
                        s103.push(new VeraStringValue(t103));
                    }
                    a103.stack.push(new VeraArrayValue(s103));
                    break;
                }
                case 'ensure-not-null': {
                    let q103 = this.pop(a103);
                    if (q103 instanceof VeraNullValue) {
                        throw new RuntimeTrap('R0018', 'ensure-not-null failed');
                    }
                    a103.stack.push(q103);
                    break;
                }
                case 'load-index': {
                    let o103 = this.index(this.pop(a103));
                    let p103 = this.asArray(this.pop(a103));
                    a103.stack.push(this.indexValue(p103, o103));
                    break;
                }
                case 'store-index': {
                    let l103 = this.pop(a103);
                    let m103 = this.index(this.pop(a103));
                    let n103 = this.asArray(this.pop(a103));
                    this.indexValue(n103, m103);
                    n103.elements[m103] = l103;
                    break;
                }
                case 'make-object': {
                    let i103 = this.take(a103, b103.fields.length);
                    let j103 = new Map<string, RuntimeValue>();
                    for (let k103: number = 0; k103 < b103.fields.length; k103++) {
                        j103.set(b103.fields[k103], i103[k103]);
                    }
                    a103.stack.push(new VeraObjectValue(b103.classIdentity, j103));
                    break;
                }
                case 'load-field': {
                    let g103 = this.asObject(this.pop(a103));
                    let h103 = g103.fields.get(b103.name);
                    if (h103 == undefined) {
                        throw new RuntimeTrap('R0010', `missing field ${b103.name}`);
                    }
                    a103.stack.push(h103);
                    break;
                }
                case 'store-field': {
                    let e103 = this.pop(a103);
                    let f103 = this.asObject(this.pop(a103));
                    if (!f103.fields.has(b103.name)) {
                        throw new RuntimeTrap('R0010', `missing field ${b103.name}`);
                    }
                    f103.fields.set(b103.name, e103);
                    break;
                }
                case 'make-closure': {
                    let c103: Cell[] = [];
                    for (let d103 of b103.captures) {
                        if (d103 >= 0) {
                            c103.push(this.cell(a103.locals, d103));
                        }
                        else {
                            c103.push(this.cell(a103.captures, -d103 - 1));
                        }
                    }
                    a103.stack.push(new FunctionValue(b103.functionName, c103));
                    break;
                }
            }
        }
        throw new RuntimeTrap('R0012', 'function ended without return');
    }
    private callInst(v102: Frame, w102: Instruction): void {
        let x102 = this.take(v102, w102.count);
        let y102 = this.pop(v102);
        if (y102 instanceof FunctionValue) {
            let z102 = this.functions.get(y102.name);
            if (z102 == undefined) {
                throw new RuntimeTrap('R0001', `function not found: ${y102.name}`);
            }
            if (z102.isAsync !== w102.awaited) {
                throw new RuntimeTrap('R0013', 'async call invariant');
            }
            v102.stack.push(this.run(new Frame(z102, y102.captures, x102)));
        }
        else if (y102 instanceof ExternalFunctionValue) {
            v102.stack.push(this.host.invoke(y102.module, y102.funcName, x102, w102.awaited));
        }
        else {
            throw new RuntimeTrap('R0014', 'value is not callable');
        }
    }
    private unary(t102: string, u102: RuntimeValue): RuntimeValue {
        if (t102 === '!') {
            return new VeraBooleanValue(!this.asBoolean(u102));
        }
        if (u102 instanceof VeraIntValue) {
            return new VeraIntValue(this.checked(-u102.value));
        }
        if (u102 instanceof VeraNumberValue) {
            return new VeraNumberValue(-u102.value);
        }
        throw new RuntimeTrap('R0002', 'invalid unary operand');
    }
    private binary(n102: string, o102: boolean, p102: RuntimeValue, q102: RuntimeValue): RuntimeValue {
        if (n102 === '===') {
            return new VeraBooleanValue(this.equal(p102, q102));
        }
        if (n102 === '!==') {
            return new VeraBooleanValue(!this.equal(p102, q102));
        }
        if (n102 === '&&') {
            return new VeraBooleanValue(this.asBoolean(p102) && this.asBoolean(q102));
        }
        if (n102 === '||') {
            return new VeraBooleanValue(this.asBoolean(p102) || this.asBoolean(q102));
        }
        if (p102 instanceof VeraStringValue && q102 instanceof VeraStringValue) {
            if (n102 === '+') {
                return new VeraStringValue(p102.value + q102.value);
            }
            return new VeraBooleanValue(this.compareStr(n102, p102.value, q102.value));
        }
        if (o102) {
            return this.intBinary(n102, this.asInt(p102), this.asInt(q102));
        }
        let r102 = this.asNumber(p102);
        let s102 = this.asNumber(q102);
        if (n102 === '+') {
            return new VeraNumberValue(r102 + s102);
        }
        if (n102 === '-') {
            return new VeraNumberValue(r102 - s102);
        }
        if (n102 === '*') {
            return new VeraNumberValue(r102 * s102);
        }
        if (n102 === '/') {
            return new VeraNumberValue(r102 / s102);
        }
        return new VeraBooleanValue(this.compareNum(n102, r102, s102));
    }
    private intBinary(k102: string, l102: number, m102: number): RuntimeValue {
        if (k102 === '+') {
            return new VeraIntValue(this.checked(l102 + m102));
        }
        if (k102 === '-') {
            return new VeraIntValue(this.checked(l102 - m102));
        }
        if (k102 === '*') {
            return new VeraIntValue(this.checked(l102 * m102));
        }
        if (k102 === '/') {
            if (m102 === 0) {
                throw new RuntimeTrap('R0003', 'integer division by zero');
            }
            return new VeraIntValue(this.checked(Math.trunc(l102 / m102)));
        }
        if (k102 === '%') {
            if (m102 === 0) {
                throw new RuntimeTrap('R0004', 'integer modulo by zero');
            }
            return new VeraIntValue(l102 % m102);
        }
        if (k102 === '<') {
            return new VeraBooleanValue(l102 < m102);
        }
        if (k102 === '<=') {
            return new VeraBooleanValue(l102 <= m102);
        }
        if (k102 === '>') {
            return new VeraBooleanValue(l102 > m102);
        }
        if (k102 === '>=') {
            return new VeraBooleanValue(l102 >= m102);
        }
        throw new RuntimeTrap('R0005', `invalid comparison ${k102}`);
    }
    private compareNum(h102: string, i102: number, j102: number): boolean {
        if (h102 === '<') {
            return i102 < j102;
        }
        if (h102 === '<=') {
            return i102 <= j102;
        }
        if (h102 === '>') {
            return i102 > j102;
        }
        if (h102 === '>=') {
            return i102 >= j102;
        }
        throw new RuntimeTrap('R0005', `invalid comparison ${h102}`);
    }
    private compareStr(e102: string, f102: string, g102: string): boolean {
        if (e102 === '<') {
            return f102 < g102;
        }
        if (e102 === '<=') {
            return f102 <= g102;
        }
        if (e102 === '>') {
            return f102 > g102;
        }
        if (e102 === '>=') {
            return f102 >= g102;
        }
        throw new RuntimeTrap('R0005', `invalid comparison ${e102}`);
    }
    private equal(c102: RuntimeValue, d102: RuntimeValue): boolean {
        if (c102 instanceof VeraNullValue || d102 instanceof VeraNullValue) {
            return c102 instanceof VeraNullValue && d102 instanceof VeraNullValue;
        }
        if (c102 instanceof VeraIntValue && d102 instanceof VeraIntValue) {
            return c102.value === d102.value;
        }
        if (c102 instanceof VeraNumberValue && d102 instanceof VeraNumberValue) {
            return c102.value === d102.value;
        }
        if (c102 instanceof VeraStringValue && d102 instanceof VeraStringValue) {
            return c102.value === d102.value;
        }
        if (c102 instanceof VeraBooleanValue && d102 instanceof VeraBooleanValue) {
            return c102.value === d102.value;
        }
        if (c102 instanceof FunctionValue && d102 instanceof FunctionValue) {
            return c102 === d102;
        }
        if (c102 instanceof ExternalFunctionValue && d102 instanceof ExternalFunctionValue) {
            return c102 === d102;
        }
        return false;
    }
    private checked(b102: number): number {
        if (b102 < MIN_INT || b102 > MAX_INT) {
            throw new RuntimeTrap('R0006', 'integer overflow');
        }
        return b102;
    }
    private pop(z101: Frame): RuntimeValue {
        let a102 = z101.stack.pop();
        if (a102 == undefined) {
            throw new RuntimeTrap('R0007', 'stack underflow');
        }
        return a102;
    }
    private take(u101: Frame, v101: number): RuntimeValue[] {
        if (u101.stack.length < v101) {
            throw new RuntimeTrap('R0007', 'stack underflow');
        }
        let w101: RuntimeValue[] = [];
        let x101 = u101.stack.length - v101;
        for (let y101 = x101; y101 < u101.stack.length; y101++) {
            w101.push(u101.stack[y101]);
        }
        while (u101.stack.length > x101) {
            this.pop(u101);
        }
        return w101;
    }
    private asInt(t101: RuntimeValue): number {
        if (!(t101 instanceof VeraIntValue)) {
            throw new RuntimeTrap('R0008', 'expected int');
        }
        return (t101 as VeraIntValue).value;
    }
    private asNumber(s101: RuntimeValue): number {
        if (!(s101 instanceof VeraNumberValue)) {
            throw new RuntimeTrap('R0008', 'expected number');
        }
        return (s101 as VeraNumberValue).value;
    }
    private asBoolean(r101: RuntimeValue): boolean {
        if (!(r101 instanceof VeraBooleanValue)) {
            throw new RuntimeTrap('R0008', 'expected boolean');
        }
        return (r101 as VeraBooleanValue).value;
    }
    private asArray(q101: RuntimeValue): VeraArrayValue {
        if (!(q101 instanceof VeraArrayValue)) {
            throw new RuntimeTrap('R0008', 'expected array');
        }
        return q101 as VeraArrayValue;
    }
    private asObject(p101: RuntimeValue): VeraObjectValue {
        if (!(p101 instanceof VeraObjectValue)) {
            throw new RuntimeTrap('R0008', 'expected object');
        }
        return p101 as VeraObjectValue;
    }
    private index(n101: RuntimeValue): number {
        let o101 = this.asInt(n101);
        if (o101 < 0 || o101 > MAX_INT) {
            throw new RuntimeTrap('R0009', 'array index out of bounds');
        }
        return o101;
    }
    private indexValue(l101: VeraArrayValue, m101: number): RuntimeValue {
        if (m101 < 0 || m101 >= l101.elements.length) {
            throw new RuntimeTrap('R0009', 'array index out of bounds');
        }
        return l101.elements[m101];
    }
    private cell(j101: Cell[], k101: number): Cell {
        if (k101 < 0 || k101 >= j101.length) {
            throw new RuntimeTrap('R0016', 'invalid slot');
        }
        return j101[k101];
    }
}
export function formatRuntimeValue(f101: RuntimeValue): string {
    if (f101 instanceof VeraIntValue) {
        return f101.value.toString();
    }
    if (f101 instanceof VeraNumberValue) {
        return f101.value.toString();
    }
    if (f101 instanceof VeraStringValue) {
        return f101.value;
    }
    if (f101 instanceof VeraBooleanValue) {
        return f101.value ? 'true' : 'false';
    }
    if (f101 instanceof VeraNullValue) {
        return 'null';
    }
    if (f101 instanceof VeraArrayValue) {
        return '[' + f101.elements.map((i101: RuntimeValue) => formatRuntimeValue(i101)).join(', ') + ']';
    }
    if (f101 instanceof VeraObjectValue) {
        let g101: string[] = [];
        for (let h101 of f101.fields) {
            g101.push(h101[0] + ': ' + formatRuntimeValue(h101[1]));
        }
        return '{' + g101.join(', ') + '}';
    }
    if (f101 instanceof FunctionValue) {
        return `<function ${f101.name}>`;
    }
    if (f101 instanceof ExternalFunctionValue) {
        return `<external ${f101.module}.${f101.funcName}>`;
    }
    return '<unknown>';
}
export function encodeRuntimeValue(z100: RuntimeValue): Object {
    if (z100 instanceof VeraIntValue) {
        return ['i', (z100 as VeraIntValue).value] as Object;
    }
    if (z100 instanceof VeraNumberValue) {
        return ['n', (z100 as VeraNumberValue).value] as Object;
    }
    if (z100 instanceof VeraStringValue) {
        return ['s', (z100 as VeraStringValue).value] as Object;
    }
    if (z100 instanceof VeraBooleanValue) {
        return ['b', (z100 as VeraBooleanValue).value] as Object;
    }
    if (z100 instanceof VeraNullValue) {
        return ['z'] as Object;
    }
    if (z100 instanceof VeraArrayValue) {
        let d101: Object[] = [];
        for (let e101 of (z100 as VeraArrayValue).elements) {
            d101.push(encodeRuntimeValue(e101));
        }
        return ['a', d101] as Object;
    }
    if (z100 instanceof VeraObjectValue) {
        let a101 = z100 as VeraObjectValue;
        let b101: Object[] = [];
        for (let c101 of a101.fields) {
            b101.push([c101[0], encodeRuntimeValue(c101[1])] as Object);
        }
        return ['o', a101.classIdentity, b101] as Object;
    }
    throw new RuntimeTrap('R0024', 'value cannot be saved: ' + formatRuntimeValue(z100));
}
export function decodeRuntimeValue(r100: Object): RuntimeValue {
    let s100 = r100 as Object[];
    let t100 = s100[0] as string;
    if (t100 === 'i') {
        return new VeraIntValue(s100[1] as number);
    }
    if (t100 === 'n') {
        return new VeraNumberValue(s100[1] as number);
    }
    if (t100 === 's') {
        return new VeraStringValue(s100[1] as string);
    }
    if (t100 === 'b') {
        return new VeraBooleanValue(s100[1] as boolean);
    }
    if (t100 === 'z') {
        return NULL_VALUE;
    }
    if (t100 === 'a') {
        let x100: RuntimeValue[] = [];
        for (let y100 of s100[1] as Object[]) {
            x100.push(decodeRuntimeValue(y100));
        }
        return new VeraArrayValue(x100);
    }
    if (t100 === 'o') {
        let u100 = new Map<string, RuntimeValue>();
        for (let v100 of s100[2] as Object[]) {
            let w100 = v100 as Object[];
            u100.set(w100[0] as string, decodeRuntimeValue(w100[1]));
        }
        return new VeraObjectValue(s100[1] as string, u100);
    }
    throw new RuntimeTrap('R0025', 'unknown saved value tag: ' + t100);
}
export function deserializeVbc2(i100: string): BytecodeModule {
    let j100 = JSON.parse(i100) as Object[];
    if (!Array.isArray(j100) || j100[0] !== 'VBC2') {
        throw new RuntimeTrap('VBC0004', 'unsupported VBC version');
    }
    let k100 = j100[1] as string[];
    let l100 = j100[2] as Object[][];
    let m100: BytecodeFunction[] = [];
    for (let n100 of l100) {
        let o100 = n100[4] as Object[][];
        let p100: Instruction[] = [];
        for (let q100 of o100) {
            p100.push(decodeInstruction(q100));
        }
        m100.push(new BytecodeFunction(n100[0] as string, n100[1] as number, n100[2] as number, n100[3] as boolean, p100));
    }
    return new BytecodeModule(m100, k100);
}
function decodeInstruction(f100: Object[]): Instruction {
    let g100 = f100[0] as string;
    let h100 = new Instruction(g100);
    switch (g100) {
        case 'push-int':
            h100.value = f100[1] as string;
            break;
        case 'push-number':
            h100.numValue = f100[1] as number;
            break;
        case 'push-string':
            h100.value = f100[1] as string;
            break;
        case 'push-boolean':
            h100.boolValue = f100[1] as boolean;
            break;
        case 'push-null': break;
        case 'load-local':
            h100.slot = f100[1] as number;
            break;
        case 'store-local':
            h100.slot = f100[1] as number;
            break;
        case 'load-capture':
            h100.slot = f100[1] as number;
            break;
        case 'store-capture':
            h100.slot = f100[1] as number;
            break;
        case 'load-function':
            h100.name = f100[1] as string;
            break;
        case 'load-external':
            h100.module = f100[1] as string;
            h100.name = f100[2] as string;
            break;
        case 'pop': break;
        case 'duplicate': break;
        case 'unary':
            h100.operator = f100[1] as string;
            break;
        case 'binary':
            h100.operator = f100[1] as string;
            h100.integer = f100[2] as boolean;
            break;
        case 'jump':
            h100.target = f100[1] as number;
            break;
        case 'jump-if-false':
            h100.target = f100[1] as number;
            break;
        case 'call':
            h100.count = f100[1] as number;
            h100.awaited = f100[2] as boolean;
            break;
        case 'return': break;
        case 'make-array':
            h100.count = f100[1] as number;
            break;
        case 'array-push': break;
        case 'array-pop': break;
        case 'length': break;
        case 'string-symbols': break;
        case 'ensure-not-null': break;
        case 'load-index': break;
        case 'store-index': break;
        case 'make-object':
            h100.classIdentity = f100[1] as string;
            h100.fields = f100[2] as string[];
            break;
        case 'load-field':
            h100.name = f100[1] as string;
            break;
        case 'store-field':
            h100.name = f100[1] as string;
            break;
        case 'make-closure':
            h100.functionName = f100[1] as string;
            h100.captures = f100[2] as number[];
            break;
        default:
            throw new RuntimeTrap('VBC0003', `unknown opcode: ${g100}`);
    }
    return h100;
}

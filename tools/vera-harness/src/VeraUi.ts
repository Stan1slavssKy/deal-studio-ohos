import { VeraIntValue, VeraNumberValue, VeraStringValue, VeraBooleanValue, VeraArrayValue, VeraObjectValue, HostEnvironment, RuntimeTrap, } from "./VeraInterpreter";
import type { RuntimeValue } from "./VeraInterpreter";
export class VeraUiNode {
    id: number = 0;
    kind: string = '';
    style: string = '';
    text: string = '';
    source: string = '';
    alt: string = '';
    action: string = '';
    eventValue: number = 0;
    enabled: boolean = true;
    commands: string = '';
    spinPeriodMs: number = 0;
    label: string = '';
    tickerId: string = '';
    columns: number = 1;
    value: string = '';
    checked: boolean = false;
    minimum: number = 0;
    maximum: number = 100;
    options: string[] = [];
    series: number[] = [];
    children: VeraUiNode[] = [];
    intValue: number = 0;
    prefix: string = '';
    suffix: string = '';
    minimumDigits: number = 1;
    icon: string = '';
    keyboardType: string = '';
    required: boolean = false;
    requiredMessage: string = '';
    minLength: number = 0;
    minLengthMessage: string = '';
    maxLength: number = -1;
    maxLengthMessage: string = '';
    pattern: string = '';
    patternMessage: string = '';
    email: boolean = false;
    emailMessage: string = '';
}
function asString(x170: RuntimeValue): string {
    if (x170 instanceof VeraStringValue) {
        return (x170 as VeraStringValue).value;
    }
    throw new RuntimeTrap('R0020', 'expected string argument');
}
function asInt(w170: RuntimeValue): number {
    if (w170 instanceof VeraIntValue) {
        return (w170 as VeraIntValue).value;
    }
    throw new RuntimeTrap('R0020', 'expected int argument');
}
function asBool(v170: RuntimeValue): boolean {
    if (v170 instanceof VeraBooleanValue) {
        return (v170 as VeraBooleanValue).value;
    }
    throw new RuntimeTrap('R0020', 'expected boolean argument');
}
function asArray(u170: RuntimeValue): VeraArrayValue {
    if (u170 instanceof VeraArrayValue) {
        return u170 as VeraArrayValue;
    }
    throw new RuntimeTrap('R0020', 'expected array argument');
}
function argString(r170: RuntimeValue[], s170: number, t170: string = ''): string {
    if (s170 >= r170.length) {
        return t170;
    }
    return asString(r170[s170]);
}
function argInt(o170: RuntimeValue[], p170: number, q170: number = 0): number {
    if (p170 >= o170.length) {
        return q170;
    }
    return asInt(o170[p170]);
}
function argBool(l170: RuntimeValue[], m170: number, n170: boolean = true): boolean {
    if (m170 >= l170.length) {
        return n170;
    }
    return asBool(l170[m170]);
}
function argArray(j170: RuntimeValue[], k170: number): VeraArrayValue {
    if (k170 >= j170.length) {
        return new VeraArrayValue([]);
    }
    return asArray(j170[k170]);
}
function viewNode(f170: string, g170: Array<[
    string,
    RuntimeValue
]>): VeraObjectValue {
    let h170 = new Map<string, RuntimeValue>();
    h170.set('type', new VeraStringValue(f170));
    for (let i170 of g170) {
        h170.set(i170[0], i170[1]);
    }
    return new VeraObjectValue('std/ui:View', h170);
}
function containerNode(d170: string, e170: RuntimeValue[]): RuntimeValue {
    return viewNode(d170, [
        ['style', new VeraStringValue(argString(e170, 0))],
        ['children', argArray(e170, 1)],
    ]);
}
function invokeStdTime(a170: string, b170: RuntimeValue[]): RuntimeValue {
    let c170 = new Date();
    switch (a170) {
        case 'nowSeconds':
            return new VeraIntValue(Math.floor(c170.getTime() / 1000));
        case 'daysSinceEpoch':
            return new VeraIntValue(Math.floor((c170.getTime() - c170.getTimezoneOffset() * 60000) / 86400000));
        case 'millisOfDay':
            return new VeraIntValue(((c170.getHours() * 60 + c170.getMinutes()) * 60 + c170.getSeconds()) * 1000 +
                c170.getMilliseconds());
        case 'hourOfDay': return new VeraIntValue(c170.getHours());
        case 'minuteOfHour': return new VeraIntValue(c170.getMinutes());
        case 'weekday': return new VeraIntValue(c170.getDay());
        case 'dayOfMonth': return new VeraIntValue(c170.getDate());
        case 'monthOfYear': return new VeraIntValue(c170.getMonth() + 1);
        case 'year': return new VeraIntValue(c170.getFullYear());
        default:
            throw new RuntimeTrap('R0015', `unknown std/time function: ${a170}`);
    }
}
const INT32_MIN: number = -2147483648;
const INT32_MAX: number = 2147483647;
function asNumberArg(z169: RuntimeValue): number {
    if (z169 instanceof VeraNumberValue) {
        return (z169 as VeraNumberValue).value;
    }
    throw new RuntimeTrap('R0020', 'expected number argument');
}
function clampInt(x169: number): number {
    let y169 = Math.trunc(x169);
    if (y169 < INT32_MIN) {
        return INT32_MIN;
    }
    if (y169 > INT32_MAX) {
        return INT32_MAX;
    }
    return y169;
}
function invokeStdMath(s169: string, t169: RuntimeValue[]): RuntimeValue {
    switch (s169) {
        case 'intToNumber': return new VeraNumberValue(asInt(t169[0]));
        case 'numberToInt': return new VeraIntValue(clampInt(asNumberArg(t169[0])));
        case 'pi': return new VeraNumberValue(Math.PI);
        case 'sqrt': return new VeraNumberValue(Math.sqrt(asNumberArg(t169[0])));
        case 'sin': return new VeraNumberValue(Math.sin(asNumberArg(t169[0])));
        case 'cos': return new VeraNumberValue(Math.cos(asNumberArg(t169[0])));
        case 'atan2': return new VeraNumberValue(Math.atan2(asNumberArg(t169[0]), asNumberArg(t169[1])));
        case 'pow': return new VeraNumberValue(Math.pow(asNumberArg(t169[0]), asNumberArg(t169[1])));
        case 'floorToInt': return new VeraIntValue(clampInt(Math.floor(asNumberArg(t169[0]))));
        case 'roundToInt': return new VeraIntValue(clampInt(Math.round(asNumberArg(t169[0]))));
        case 'absInt': return new VeraIntValue(clampInt(Math.abs(asInt(t169[0]))));
        case 'absNumber': return new VeraNumberValue(Math.abs(asNumberArg(t169[0])));
        case 'minInt': return new VeraIntValue(Math.min(asInt(t169[0]), asInt(t169[1])));
        case 'maxInt': return new VeraIntValue(Math.max(asInt(t169[0]), asInt(t169[1])));
        case 'minNumber': return new VeraNumberValue(Math.min(asNumberArg(t169[0]), asNumberArg(t169[1])));
        case 'maxNumber': return new VeraNumberValue(Math.max(asNumberArg(t169[0]), asNumberArg(t169[1])));
        case 'randomStep': {
            let w169 = asInt(t169[0]) | 0;
            if (w169 === 0) {
                w169 = 0x2545F491;
            }
            w169 = w169 ^ (w169 << 13);
            w169 = w169 ^ (w169 >>> 17);
            w169 = w169 ^ (w169 << 5);
            return new VeraIntValue(clampInt(w169 | 0));
        }
        case 'randomBelow': {
            let u169 = asInt(t169[0]) | 0;
            let v169 = asInt(t169[1]);
            if (v169 <= 0) {
                throw new RuntimeTrap('R0026', 'randomBelow needs a positive bound');
            }
            return new VeraIntValue(Math.abs(u169) % v169);
        }
        default:
            throw new RuntimeTrap('R0015', `unknown std/math function: ${s169}`);
    }
}
function scalars(r169: string): string[] {
    return Array.from(r169);
}
function isSpace(p169: string): boolean {
    let q169 = p169.charCodeAt(0);
    if (q169 === 0x20 || (q169 >= 0x09 && q169 <= 0x0D)) {
        return true;
    }
    if (q169 === 0x85 || q169 === 0xA0 || q169 === 0x1680) {
        return true;
    }
    if (q169 >= 0x2000 && q169 <= 0x200A) {
        return true;
    }
    return q169 === 0x2028 || q169 === 0x2029 || q169 === 0x202F || q169 === 0x205F || q169 === 0x3000;
}
function invokeStdStrings(v168: string, w168: RuntimeValue[]): RuntimeValue {
    switch (v168) {
        case 'length':
            return new VeraIntValue(scalars(asString(w168[0])).length);
        case 'substring': {
            let m169 = scalars(asString(w168[0]));
            let n169 = asInt(w168[1]);
            let o169 = asInt(w168[2]);
            if (n169 < 0 || o169 < n169 || o169 > m169.length) {
                throw new RuntimeTrap('R0009', 'string index out of bounds');
            }
            return new VeraStringValue(m169.slice(n169, o169).join(''));
        }
        case 'contains':
            return new VeraBooleanValue(asString(w168[0]).indexOf(asString(w168[1])) >= 0);
        case 'startsWith':
            return new VeraBooleanValue(asString(w168[0]).startsWith(asString(w168[1])));
        case 'endsWith':
            return new VeraBooleanValue(asString(w168[0]).endsWith(asString(w168[1])));
        case 'replace': {
            let g169 = asString(w168[0]);
            let h169 = asString(w168[1]);
            let i169 = asString(w168[2]);
            if (h169.length === 0) {
                return new VeraStringValue(g169);
            }
            let j169 = '';
            let k169 = 0;
            while (k169 < g169.length) {
                let l169 = g169.indexOf(h169, k169);
                if (l169 < 0) {
                    j169 += g169.substring(k169);
                    break;
                }
                j169 += g169.substring(k169, l169) + i169;
                k169 = l169 + h169.length;
            }
            return new VeraStringValue(j169);
        }
        case 'split': {
            let a169 = asString(w168[0]);
            let b169 = asString(w168[1]);
            let c169: RuntimeValue[] = [];
            if (b169.length === 0) {
                for (let f169 of scalars(a169)) {
                    c169.push(new VeraStringValue(f169));
                }
                return new VeraArrayValue(c169);
            }
            let d169 = 0;
            while (true) {
                let e169 = a169.indexOf(b169, d169);
                if (e169 < 0) {
                    c169.push(new VeraStringValue(a169.substring(d169)));
                    break;
                }
                c169.push(new VeraStringValue(a169.substring(d169, e169)));
                d169 = e169 + b169.length;
            }
            return new VeraArrayValue(c169);
        }
        case 'trim': {
            let x168 = scalars(asString(w168[0]));
            let y168 = 0;
            let z168 = x168.length;
            while (y168 < z168 && isSpace(x168[y168])) {
                y168++;
            }
            while (z168 > y168 && isSpace(x168[z168 - 1])) {
                z168--;
            }
            return new VeraStringValue(x168.slice(y168, z168).join(''));
        }
        default:
            throw new RuntimeTrap('R0015', `unknown std/strings function: ${v168}`);
    }
}
export class HostEffect {
    id: number;
    kind: string;
    fn: string;
    values: Map<string, string>;
    resultHandler: string;
    rawTarget: string = '';
    rawParams: string = '';
    rawMode: string = '';
    constructor(q168: number, r168: string, s168: string, t168: Map<string, string>, u168: string) {
        this.id = q168;
        this.kind = r168;
        this.fn = s168;
        this.values = t168;
        this.resultHandler = u168;
    }
}
export class UiHostEnvironment extends HostEnvironment {
    pendingEffects: HostEffect[] = [];
    effectsAllowed: boolean = false;
    private nextEffectId: number = 1;
    invoke(m168: string, n168: string, o168: RuntimeValue[], p168: boolean): RuntimeValue {
        if (m168 === 'std/time') {
            return invokeStdTime(n168, o168);
        }
        if (m168 === 'std/math') {
            return invokeStdMath(n168, o168);
        }
        if (m168 === 'std/strings') {
            return invokeStdStrings(n168, o168);
        }
        if (m168 === 'std/sdk') {
            return this.queueSdk(o168);
        }
        if (m168 !== 'std/ui') {
            throw new RuntimeTrap('R0015', `external function unavailable: ${m168}.${n168}`);
        }
        switch (n168) {
            case 'Column': return containerNode('column', o168);
            case 'Row': return containerNode('row', o168);
            case 'Card': return containerNode('card', o168);
            case 'Scroll': return containerNode('scroll', o168);
            case 'Canvas': return containerNode('canvas', o168);
            case 'Text':
                return viewNode('text', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['text', new VeraStringValue(argString(o168, 1))],
                ]);
            case 'Spacer':
                return viewNode('spacer', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                ]);
            case 'Image':
                return viewNode('image', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['src', new VeraStringValue(argString(o168, 1))],
                    ['alt', new VeraStringValue(argString(o168, 2))],
                ]);
            case 'Path':
                return viewNode('path', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['commands', new VeraStringValue(argString(o168, 1))],
                    ['spinPeriodMs', new VeraIntValue(argInt(o168, 2))],
                ]);
            case 'TextField':
                return viewNode('field', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['label', new VeraStringValue(argString(o168, 1))],
                    ['value', new VeraStringValue(argString(o168, 2))],
                    ['action', new VeraStringValue(argString(o168, 3))],
                    ['keyboardType', new VeraStringValue(argString(o168, 4))],
                    ['required', new VeraBooleanValue(argBool(o168, 5, false))],
                    ['requiredMessage', new VeraStringValue(argString(o168, 6))],
                    ['minLength', new VeraIntValue(argInt(o168, 7, 0))],
                    ['minLengthMessage', new VeraStringValue(argString(o168, 8))],
                    ['maxLength', new VeraIntValue(argInt(o168, 9, -1))],
                    ['maxLengthMessage', new VeraStringValue(argString(o168, 10))],
                    ['pattern', new VeraStringValue(argString(o168, 11))],
                    ['patternMessage', new VeraStringValue(argString(o168, 12))],
                    ['email', new VeraBooleanValue(argBool(o168, 13, false))],
                    ['emailMessage', new VeraStringValue(argString(o168, 14))],
                ]);
            case 'Toggle':
            case 'Checkbox':
                return viewNode(n168 === 'Toggle' ? 'toggle' : 'checkbox', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['label', new VeraStringValue(argString(o168, 1))],
                    ['checked', new VeraBooleanValue(argBool(o168, 2))],
                    ['action', new VeraStringValue(argString(o168, 3))],
                ]);
            case 'Slider':
                return viewNode('slider', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['label', new VeraStringValue(argString(o168, 1))],
                    ['value', new VeraIntValue(argInt(o168, 2))],
                    ['minimum', new VeraIntValue(argInt(o168, 3))],
                    ['maximum', new VeraIntValue(argInt(o168, 4))],
                    ['action', new VeraStringValue(argString(o168, 5))],
                ]);
            case 'Select':
                return viewNode('select', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['label', new VeraStringValue(argString(o168, 1))],
                    ['options', argArray(o168, 2)],
                    ['value', new VeraIntValue(argInt(o168, 3))],
                    ['action', new VeraStringValue(argString(o168, 4))],
                ]);
            case 'Grid':
                return viewNode('grid', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['columns', new VeraIntValue(argInt(o168, 1))],
                    ['children', argArray(o168, 2)],
                ]);
            case 'ListItem':
                return viewNode('listitem', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['text', new VeraStringValue(argString(o168, 1))],
                    ['label', new VeraStringValue(argString(o168, 2))],
                    ['value', new VeraStringValue(argString(o168, 3))],
                    ['action', new VeraStringValue(argString(o168, 4))],
                    ['eventValue', new VeraIntValue(argInt(o168, 5))],
                    ['enabled', new VeraBooleanValue(argBool(o168, 6))],
                    ['icon', new VeraStringValue(argString(o168, 7))],
                ]);
            case 'Ticker':
                return viewNode('ticker', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['tickerId', new VeraStringValue(argString(o168, 1))],
                    ['minimum', new VeraIntValue(argInt(o168, 2))],
                    ['checked', new VeraBooleanValue(argBool(o168, 3))],
                    ['action', new VeraStringValue(argString(o168, 4))],
                ]);
            case 'Divider':
                return viewNode('divider', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                ]);
            case 'BackHandler':
                return viewNode('backhandler', [
                    ['action', new VeraStringValue(argString(o168, 0))],
                ]);
            case 'Progress':
                return viewNode('progress', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['label', new VeraStringValue(argString(o168, 1))],
                    ['value', new VeraIntValue(argInt(o168, 2))],
                    ['maximum', new VeraIntValue(argInt(o168, 3))],
                ]);
            case 'Button':
                return viewNode('button', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['text', new VeraStringValue(argString(o168, 1))],
                    ['action', new VeraStringValue(argString(o168, 2))],
                    ['value', new VeraIntValue(argInt(o168, 3))],
                    ['enabled', new VeraBooleanValue(argBool(o168, 4))],
                ]);
            case 'Cell':
                return viewNode('cell', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['text', new VeraStringValue(argString(o168, 1))],
                    ['action', new VeraStringValue(argString(o168, 2))],
                    ['value', new VeraIntValue(argInt(o168, 3))],
                    ['enabled', new VeraBooleanValue(argBool(o168, 4))],
                ]);
            case 'AppTheme':
                return viewNode('apptheme', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['value', new VeraStringValue(argString(o168, 1))],
                    ['children', argArray(o168, 2)],
                ]);
            case 'Header':
                return viewNode('header', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['text', new VeraStringValue(argString(o168, 1))],
                    ['label', new VeraStringValue(argString(o168, 2))],
                    ['value', new VeraStringValue(argString(o168, 3))],
                    ['icon', new VeraStringValue(argString(o168, 4))],
                ]);
            case 'Section':
                return viewNode('section', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['text', new VeraStringValue(argString(o168, 1))],
                    ['label', new VeraStringValue(argString(o168, 2))],
                    ['children', argArray(o168, 3)],
                ]);
            case 'SectionHeader':
                return viewNode('sectionheader', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['text', new VeraStringValue(argString(o168, 1))],
                    ['label', new VeraStringValue(argString(o168, 2))],
                    ['value', new VeraStringValue(argString(o168, 3))],
                ]);
            case 'ListGroup':
                return viewNode('listgroup', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['text', new VeraStringValue(argString(o168, 1))],
                    ['children', argArray(o168, 2)],
                ]);
            case 'InsetBanner':
                return viewNode('banner', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['text', new VeraStringValue(argString(o168, 1))],
                    ['label', new VeraStringValue(argString(o168, 2))],
                    ['value', new VeraStringValue(argString(o168, 3))],
                    ['action', new VeraStringValue(argString(o168, 4))],
                    ['icon', new VeraStringValue(argString(o168, 5))],
                ]);
            case 'EmptyState':
                return viewNode('emptystate', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['text', new VeraStringValue(argString(o168, 1))],
                    ['label', new VeraStringValue(argString(o168, 2))],
                    ['value', new VeraStringValue(argString(o168, 3))],
                    ['action', new VeraStringValue(argString(o168, 4))],
                    ['icon', new VeraStringValue(argString(o168, 5))],
                ]);
            case 'Stat':
                return viewNode('stat', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['label', new VeraStringValue(argString(o168, 1))],
                    ['text', new VeraStringValue(argString(o168, 2))],
                    ['value', new VeraStringValue(argString(o168, 3))],
                    ['icon', new VeraStringValue(argString(o168, 4))],
                ]);
            case 'MetricGroup':
                return viewNode('metricgroup', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['columns', new VeraIntValue(argInt(o168, 1))],
                    ['children', argArray(o168, 2)],
                ]);
            case 'IntText':
                return viewNode('inttext', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['intValue', new VeraIntValue(argInt(o168, 1))],
                    ['prefix', new VeraStringValue(argString(o168, 2))],
                    ['suffix', new VeraStringValue(argString(o168, 3))],
                    ['minimumDigits', new VeraIntValue(argInt(o168, 4))],
                ]);
            case 'ClockText':
                return viewNode('clocktext', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['intValue', new VeraIntValue(argInt(o168, 1))],
                    ['prefix', new VeraStringValue(argString(o168, 2))],
                    ['suffix', new VeraStringValue(argString(o168, 3))],
                ]);
            case 'IntStat':
                return viewNode('intstat', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['label', new VeraStringValue(argString(o168, 1))],
                    ['intValue', new VeraIntValue(argInt(o168, 2))],
                    ['prefix', new VeraStringValue(argString(o168, 3))],
                    ['suffix', new VeraStringValue(argString(o168, 4))],
                    ['minimumDigits', new VeraIntValue(argInt(o168, 5))],
                    ['value', new VeraStringValue(argString(o168, 6))],
                    ['icon', new VeraStringValue(argString(o168, 7))],
                ]);
            case 'IntField':
                return viewNode('intfield', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['label', new VeraStringValue(argString(o168, 1))],
                    ['intValue', new VeraIntValue(argInt(o168, 2))],
                    ['minimum', new VeraIntValue(argInt(o168, 3))],
                    ['maximum', new VeraIntValue(argInt(o168, 4))],
                    ['action', new VeraStringValue(argString(o168, 5))],
                ]);
            case 'TimeField':
                return viewNode('timefield', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['label', new VeraStringValue(argString(o168, 1))],
                    ['intValue', new VeraIntValue(argInt(o168, 2))],
                    ['action', new VeraStringValue(argString(o168, 3))],
                ]);
            case 'IntListItem':
                return viewNode('intlistitem', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['text', new VeraStringValue(argString(o168, 1))],
                    ['label', new VeraStringValue(argString(o168, 2))],
                    ['intValue', new VeraIntValue(argInt(o168, 3))],
                    ['prefix', new VeraStringValue(argString(o168, 4))],
                    ['suffix', new VeraStringValue(argString(o168, 5))],
                    ['minimumDigits', new VeraIntValue(argInt(o168, 6))],
                    ['action', new VeraStringValue(argString(o168, 7))],
                    ['eventValue', new VeraIntValue(argInt(o168, 8))],
                    ['enabled', new VeraBooleanValue(argBool(o168, 9))],
                    ['icon', new VeraStringValue(argString(o168, 10))],
                ]);
            case 'ActionBar':
                return containerNode('actionbar', o168);
            case 'Timeline':
                return viewNode('timeline', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['text', new VeraStringValue(argString(o168, 1))],
                    ['children', argArray(o168, 2)],
                ]);
            case 'TimelineItem':
                return viewNode('timelineitem', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['text', new VeraStringValue(argString(o168, 1))],
                    ['label', new VeraStringValue(argString(o168, 2))],
                    ['value', new VeraStringValue(argString(o168, 3))],
                    ['action', new VeraStringValue(argString(o168, 4))],
                    ['eventValue', new VeraIntValue(argInt(o168, 5))],
                    ['enabled', new VeraBooleanValue(argBool(o168, 6))],
                    ['icon', new VeraStringValue(argString(o168, 7))],
                ]);
            case 'KeyValueGroup':
                return viewNode('kvgroup', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['columns', new VeraIntValue(argInt(o168, 1))],
                    ['children', argArray(o168, 2)],
                ]);
            case 'KeyValueItem':
                return viewNode('kvitem', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['label', new VeraStringValue(argString(o168, 1))],
                    ['text', new VeraStringValue(argString(o168, 2))],
                    ['value', new VeraStringValue(argString(o168, 3))],
                ]);
            case 'Icon':
                return viewNode('icon', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['icon', new VeraStringValue(argString(o168, 1))],
                ]);
            case 'IconButton':
                return viewNode('iconbutton', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['icon', new VeraStringValue(argString(o168, 1))],
                    ['label', new VeraStringValue(argString(o168, 2))],
                    ['action', new VeraStringValue(argString(o168, 3))],
                    ['value', new VeraIntValue(argInt(o168, 4))],
                    ['enabled', new VeraBooleanValue(argBool(o168, 5))],
                ]);
            case 'Badge':
                return viewNode('badge', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['text', new VeraStringValue(argString(o168, 1))],
                    ['icon', new VeraStringValue(argString(o168, 2))],
                ]);
            case 'Skeleton':
                return viewNode('skeleton', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['minimum', new VeraIntValue(argInt(o168, 1))],
                    ['maximum', new VeraIntValue(argInt(o168, 2))],
                    ['checked', new VeraBooleanValue(argBool(o168, 3, false))],
                ]);
            case 'Spinner':
                return viewNode('spinner', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['label', new VeraStringValue(argString(o168, 1))],
                ]);
            case 'Snackbar':
                return viewNode('snackbar', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['text', new VeraStringValue(argString(o168, 1))],
                    ['value', new VeraStringValue(argString(o168, 2))],
                    ['action', new VeraStringValue(argString(o168, 3))],
                ]);
            case 'Sparkline':
                return viewNode('sparkline', [
                    ['style', new VeraStringValue(argString(o168, 0))],
                    ['series', argArray(o168, 1)],
                    ['maximum', new VeraIntValue(argInt(o168, 2))],
                    ['label', new VeraStringValue(argString(o168, 3))],
                ]);
            case 'When':
                if (asBool(o168[0])) {
                    return o168[1];
                }
                return viewNode('spacer', [['style', new VeraStringValue('none')]]);
            case 'intToString':
                return new VeraStringValue(asInt(o168[0]).toString());
            case 'numberToString': {
                if (!(o168[0] instanceof VeraNumberValue)) {
                    throw new RuntimeTrap('R0020', 'expected number argument');
                }
                return new VeraStringValue((o168[0] as VeraNumberValue).value.toString());
            }
            case 'booleanToString':
                return new VeraStringValue(asBool(o168[0]) ? 'true' : 'false');
            default:
                throw new RuntimeTrap('R0015', `unknown std/ui function: ${n168}`);
        }
    }
    private queueSdk(c168: RuntimeValue[]): RuntimeValue {
        if (!this.effectsAllowed) {
            throw new RuntimeTrap('R0026', 'sdk.call may only be called from a handler, not from view');
        }
        let d168 = asString(c168[0]).trim();
        let e168 = asArray(c168[1]).elements;
        if (e168.length % 2 !== 0) {
            throw new RuntimeTrap('R0027', 'sdk.call parameters are name and value in pairs; got ' + e168.length.toString() + ' items');
        }
        let f168 = new Map<string, string>();
        let g168: string[] = [];
        for (let k168 = 0; k168 + 1 < e168.length; k168 = k168 + 2) {
            let l168 = asString(e168[k168]).trim();
            if (l168.length === 0) {
                continue;
            }
            f168.set(l168, asString(e168[k168 + 1]));
            g168.push(l168);
        }
        let h168 = c168.length > 3 ? asString(c168[3]) : 'background';
        let i168 = this.nextEffectId;
        this.nextEffectId = i168 + 1;
        let j168 = new HostEffect(i168, 'sdk', 'call', f168, asString(c168[2]));
        j168.rawTarget = d168;
        j168.rawParams = g168.join(' ');
        j168.rawMode = h168;
        this.pendingEffects.push(j168);
        return new VeraIntValue(i168);
    }
}
let nextNodeId: number = 0;
export function decodeVeraUi(b168: RuntimeValue): VeraUiNode[] {
    nextNodeId = 0;
    if (b168 instanceof VeraObjectValue) {
        return [decodeNode(b168 as VeraObjectValue, 0)];
    }
    return [];
}
function decodeNode(q167: VeraObjectValue, r167: number): VeraUiNode {
    if (r167 > 8) {
        throw new RuntimeTrap('R0021', 'view tree too deep (max 8)');
    }
    let s167 = new VeraUiNode();
    s167.id = nextNodeId;
    nextNodeId += 1;
    for (let t167 of q167.fields.entries()) {
        let u167: string = t167[0];
        let v167: RuntimeValue = t167[1];
        switch (u167) {
            case 'type':
                if (v167 instanceof VeraStringValue) {
                    s167.kind = (v167 as VeraStringValue).value;
                }
                break;
            case 'style':
                if (v167 instanceof VeraStringValue) {
                    s167.style = (v167 as VeraStringValue).value;
                }
                break;
            case 'text':
                if (v167 instanceof VeraStringValue) {
                    s167.text = (v167 as VeraStringValue).value;
                }
                break;
            case 'src':
                if (v167 instanceof VeraStringValue) {
                    s167.source = (v167 as VeraStringValue).value;
                }
                break;
            case 'alt':
                if (v167 instanceof VeraStringValue) {
                    s167.alt = (v167 as VeraStringValue).value;
                }
                break;
            case 'action':
                if (v167 instanceof VeraStringValue) {
                    s167.action = (v167 as VeraStringValue).value;
                }
                break;
            case 'label':
                if (v167 instanceof VeraStringValue) {
                    s167.label = (v167 as VeraStringValue).value;
                }
                break;
            case 'tickerId':
                if (v167 instanceof VeraStringValue) {
                    s167.tickerId = (v167 as VeraStringValue).value;
                }
                break;
            case 'commands':
                if (v167 instanceof VeraStringValue) {
                    s167.commands = (v167 as VeraStringValue).value;
                }
                break;
            case 'prefix':
                if (v167 instanceof VeraStringValue) {
                    s167.prefix = (v167 as VeraStringValue).value;
                }
                break;
            case 'icon':
                if (v167 instanceof VeraStringValue) {
                    s167.icon = (v167 as VeraStringValue).value;
                }
                break;
            case 'suffix':
                if (v167 instanceof VeraStringValue) {
                    s167.suffix = (v167 as VeraStringValue).value;
                }
                break;
            case 'value':
                if (v167 instanceof VeraIntValue) {
                    s167.eventValue = (v167 as VeraIntValue).value;
                }
                else if (v167 instanceof VeraStringValue) {
                    s167.value = (v167 as VeraStringValue).value;
                }
                break;
            case 'eventValue':
                if (v167 instanceof VeraIntValue) {
                    s167.eventValue = (v167 as VeraIntValue).value;
                }
                break;
            case 'intValue':
                if (v167 instanceof VeraIntValue) {
                    s167.intValue = (v167 as VeraIntValue).value;
                }
                break;
            case 'minimumDigits':
                if (v167 instanceof VeraIntValue) {
                    s167.minimumDigits = (v167 as VeraIntValue).value;
                }
                break;
            case 'spinPeriodMs':
                if (v167 instanceof VeraIntValue) {
                    s167.spinPeriodMs = (v167 as VeraIntValue).value;
                }
                break;
            case 'columns':
                if (v167 instanceof VeraIntValue) {
                    s167.columns = (v167 as VeraIntValue).value;
                }
                break;
            case 'minimum':
                if (v167 instanceof VeraIntValue) {
                    s167.minimum = (v167 as VeraIntValue).value;
                }
                break;
            case 'maximum':
                if (v167 instanceof VeraIntValue) {
                    s167.maximum = (v167 as VeraIntValue).value;
                }
                break;
            case 'checked':
                if (v167 instanceof VeraBooleanValue) {
                    s167.checked = (v167 as VeraBooleanValue).value;
                }
                break;
            case 'enabled':
                if (v167 instanceof VeraBooleanValue) {
                    s167.enabled = (v167 as VeraBooleanValue).value;
                }
                break;
            case 'options':
                if (v167 instanceof VeraArrayValue) {
                    let z167: string[] = [];
                    for (let a168 of (v167 as VeraArrayValue).elements) {
                        if (a168 instanceof VeraStringValue) {
                            z167.push((a168 as VeraStringValue).value);
                        }
                    }
                    s167.options = z167;
                }
                break;
            case 'series':
                if (v167 instanceof VeraArrayValue) {
                    let x167: number[] = [];
                    for (let y167 of (v167 as VeraArrayValue).elements) {
                        if (y167 instanceof VeraIntValue) {
                            x167.push((y167 as VeraIntValue).value);
                        }
                    }
                    s167.series = x167;
                }
                break;
            case 'keyboardType':
                if (v167 instanceof VeraStringValue) {
                    s167.keyboardType = (v167 as VeraStringValue).value;
                }
                break;
            case 'required':
                if (v167 instanceof VeraBooleanValue) {
                    s167.required = (v167 as VeraBooleanValue).value;
                }
                break;
            case 'requiredMessage':
                if (v167 instanceof VeraStringValue) {
                    s167.requiredMessage = (v167 as VeraStringValue).value;
                }
                break;
            case 'minLength':
                if (v167 instanceof VeraIntValue) {
                    s167.minLength = (v167 as VeraIntValue).value;
                }
                break;
            case 'minLengthMessage':
                if (v167 instanceof VeraStringValue) {
                    s167.minLengthMessage = (v167 as VeraStringValue).value;
                }
                break;
            case 'maxLength':
                if (v167 instanceof VeraIntValue) {
                    s167.maxLength = (v167 as VeraIntValue).value;
                }
                break;
            case 'maxLengthMessage':
                if (v167 instanceof VeraStringValue) {
                    s167.maxLengthMessage = (v167 as VeraStringValue).value;
                }
                break;
            case 'pattern':
                if (v167 instanceof VeraStringValue) {
                    s167.pattern = (v167 as VeraStringValue).value;
                }
                break;
            case 'patternMessage':
                if (v167 instanceof VeraStringValue) {
                    s167.patternMessage = (v167 as VeraStringValue).value;
                }
                break;
            case 'email':
                if (v167 instanceof VeraBooleanValue) {
                    s167.email = (v167 as VeraBooleanValue).value;
                }
                break;
            case 'emailMessage':
                if (v167 instanceof VeraStringValue) {
                    s167.emailMessage = (v167 as VeraStringValue).value;
                }
                break;
            case 'children':
                if (v167 instanceof VeraArrayValue) {
                    for (let w167 of (v167 as VeraArrayValue).elements) {
                        if (w167 instanceof VeraObjectValue) {
                            s167.children.push(decodeNode(w167 as VeraObjectValue, r167 + 1));
                        }
                    }
                }
                break;
            default:
                break;
        }
    }
    return s167;
}

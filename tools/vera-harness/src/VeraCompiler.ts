import { Instruction, BytecodeFunction, BytecodeModule } from "./VeraInterpreter";
import { CATALOG, stylesFor, payloadKindFor, childRuleFor, listWords } from "./VeraUiCatalog";
import type { ComponentSpec, ChildRule } from "./VeraUiCatalog";
import { iconPath, iconNames } from "./VeraIcons";
import { isValidSdkTarget } from "./VeraSdkIndex";
class Position {
    offset: number;
    line: number;
    column: number;
    constructor(z90: number, a91: number, b91: number) {
        this.offset = z90;
        this.line = a91;
        this.column = b91;
    }
}
class Span {
    start: Position;
    end: Position;
    sourceName: string;
    constructor(w90: Position, x90: Position, y90: string) {
        this.start = w90;
        this.end = x90;
        this.sourceName = y90;
    }
}
abstract class Node {
    span: Span;
    constructor(v90: Span) { this.span = v90; }
}
class TypeNode extends Node {
    name: string;
    parts: TypeNode[];
    nullable: boolean;
    constructor(r90: Span, s90: string, t90: TypeNode[] = [], u90: boolean = false) {
        super(r90);
        this.name = s90;
        this.parts = t90;
        this.nullable = u90;
    }
}
class Parameter extends Node {
    name: string;
    type: TypeNode;
    constructor(o90: Span, p90: string, q90: TypeNode) {
        super(o90);
        this.name = p90;
        this.type = q90;
    }
}
abstract class Declaration extends Node {
}
class ImportDeclaration extends Node {
    name: string;
    specifier: string;
    constructor(l90: Span, m90: string, n90: string) {
        super(l90);
        this.name = m90;
        this.specifier = n90;
    }
}
class FunctionDeclaration extends Declaration {
    name: string;
    parameters: Parameter[];
    returnType: TypeNode;
    body: BlockStatement;
    isAsync: boolean;
    constructor(f90: Span, g90: string, h90: Parameter[], i90: TypeNode, j90: BlockStatement, k90: boolean) {
        super(f90);
        this.name = g90;
        this.parameters = h90;
        this.returnType = i90;
        this.body = j90;
        this.isAsync = k90;
    }
}
class FieldDeclaration extends Node {
    name: string;
    type: TypeNode;
    constructor(c90: Span, d90: string, e90: TypeNode) {
        super(c90);
        this.name = d90;
        this.type = e90;
    }
}
class ClassDeclaration extends Declaration {
    name: string;
    fields: FieldDeclaration[];
    annotation: string | null;
    constructor(y89: Span, z89: string, a90: FieldDeclaration[], b90: string | null) {
        super(y89);
        this.name = z89;
        this.fields = a90;
        this.annotation = b90;
    }
}
class Application extends Node {
    imports: ImportDeclaration[];
    declarations: Declaration[];
    constructor(v89: Span, w89: ImportDeclaration[], x89: Declaration[]) {
        super(v89);
        this.imports = w89;
        this.declarations = x89;
    }
}
abstract class Statement extends Node {
}
class BlockStatement extends Statement {
    statements: Statement[];
    constructor(t89: Span, u89: Statement[]) {
        super(t89);
        this.statements = u89;
    }
}
class LetStatement extends Statement {
    name: string;
    type: TypeNode;
    initializer: Expression;
    constructor(p89: Span, q89: string, r89: TypeNode, s89: Expression) {
        super(p89);
        this.name = q89;
        this.type = r89;
        this.initializer = s89;
    }
}
class IfStatement extends Statement {
    condition: Expression;
    thenBranch: BlockStatement;
    elseBranch: Statement | null;
    constructor(l89: Span, m89: Expression, n89: BlockStatement, o89: Statement | null) {
        super(l89);
        this.condition = m89;
        this.thenBranch = n89;
        this.elseBranch = o89;
    }
}
class WhileStatement extends Statement {
    condition: Expression;
    body: BlockStatement;
    constructor(i89: Span, j89: Expression, k89: BlockStatement) {
        super(i89);
        this.condition = j89;
        this.body = k89;
    }
}
class ForOfStatement extends Statement {
    name: string;
    type: TypeNode;
    iterable: Expression;
    body: BlockStatement;
    constructor(d89: Span, e89: string, f89: TypeNode, g89: Expression, h89: BlockStatement) {
        super(d89);
        this.name = e89;
        this.type = f89;
        this.iterable = g89;
        this.body = h89;
    }
}
class BreakStatement extends Statement {
}
class ContinueStatement extends Statement {
}
class ReturnStatement extends Statement {
    value: Expression | null;
    constructor(b89: Span, c89: Expression | null) {
        super(b89);
        this.value = c89;
    }
}
class AssignStatement extends Statement {
    target: Expression;
    value: Expression;
    constructor(y88: Span, z88: Expression, a89: Expression) {
        super(y88);
        this.target = z88;
        this.value = a89;
    }
}
class ExpressionStatement extends Statement {
    expression: Expression;
    constructor(w88: Span, x88: Expression) {
        super(w88);
        this.expression = x88;
    }
}
class TryStatement extends Statement {
    tryBlock: BlockStatement;
    catchName: string;
    catchBlock: BlockStatement;
    constructor(s88: Span, t88: BlockStatement, u88: string, v88: BlockStatement) {
        super(s88);
        this.tryBlock = t88;
        this.catchName = u88;
        this.catchBlock = v88;
    }
}
abstract class Expression extends Node {
}
class NameExpression extends Expression {
    name: string;
    constructor(q88: Span, r88: string) { super(q88); this.name = r88; }
}
class IntExpression extends Expression {
    value: number;
    constructor(o88: Span, p88: number) { super(o88); this.value = p88; }
}
class NumberExpression extends Expression {
    value: number;
    constructor(m88: Span, n88: number) { super(m88); this.value = n88; }
}
class StringExpression extends Expression {
    value: string;
    constructor(k88: Span, l88: string) { super(k88); this.value = l88; }
}
class BooleanExpression extends Expression {
    value: boolean;
    constructor(i88: Span, j88: boolean) { super(i88); this.value = j88; }
}
class NullExpression extends Expression {
}
class UnaryExpression extends Expression {
    operator: string;
    operand: Expression;
    constructor(f88: Span, g88: string, h88: Expression) {
        super(f88);
        this.operator = g88;
        this.operand = h88;
    }
}
class BinaryExpression extends Expression {
    left: Expression;
    operator: string;
    right: Expression;
    constructor(b88: Span, c88: Expression, d88: string, e88: Expression) {
        super(b88);
        this.left = c88;
        this.operator = d88;
        this.right = e88;
    }
}
class CallExpression extends Expression {
    callee: Expression;
    argumentsList: Expression[];
    constructor(y87: Span, z87: Expression, a88: Expression[]) {
        super(y87);
        this.callee = z87;
        this.argumentsList = a88;
    }
}
class IndexExpression extends Expression {
    target: Expression;
    index: Expression;
    constructor(v87: Span, w87: Expression, x87: Expression) {
        super(v87);
        this.target = w87;
        this.index = x87;
    }
}
class SelectExpression extends Expression {
    target: Expression;
    field: string;
    constructor(s87: Span, t87: Expression, u87: string) {
        super(s87);
        this.target = t87;
        this.field = u87;
    }
}
class ArrayExpression extends Expression {
    elements: Expression[];
    constructor(q87: Span, r87: Expression[]) {
        super(q87);
        this.elements = r87;
    }
}
class Property extends Node {
    name: string;
    value: Expression;
    constructor(n87: Span, o87: string, p87: Expression) {
        super(n87);
        this.name = o87;
        this.value = p87;
    }
}
class ObjectExpression extends Expression {
    properties: Property[];
    constructor(l87: Span, m87: Property[]) {
        super(l87);
        this.properties = m87;
    }
}
class LambdaExpression extends Expression {
    parameters: Parameter[];
    returnType: TypeNode;
    body: BlockStatement;
    constructor(h87: Span, i87: Parameter[], j87: TypeNode, k87: BlockStatement) {
        super(h87);
        this.parameters = i87;
        this.returnType = j87;
        this.body = k87;
    }
}
class AwaitExpression extends Expression {
    operand: Expression;
    constructor(f87: Span, g87: Expression) { super(f87); this.operand = g87; }
}
class EnsureNotNullExpression extends Expression {
    operand: Expression;
    constructor(d87: Span, e87: Expression) { super(d87); this.operand = e87; }
}
abstract class VeraType {
    abstract display(): string;
}
class PrimitiveType extends VeraType {
    name: string;
    constructor(c87: string) { super(); this.name = c87; }
    display(): string { return this.name; }
}
class VeraClassType extends VeraType {
    identity: string;
    name: string;
    fields: Map<string, VeraType> = new Map<string, VeraType>();
    constructor(a87: string, b87: string) { super(); this.identity = a87; this.name = b87; }
    display(): string { return this.name; }
}
class VeraArrayType extends VeraType {
    element: VeraType;
    constructor(z86: VeraType) { super(); this.element = z86; }
    display(): string { return this.element.display() + '[]'; }
}
class NullableType extends VeraType {
    base: VeraType;
    constructor(y86: VeraType) { super(); this.base = y86; }
    display(): string { return '(' + this.base.display() + ' | null)'; }
}
class VeraFunctionType extends VeraType {
    parameters: VeraType[];
    result: VeraType;
    isAsync: boolean;
    identity: string;
    required: number;
    constructor(t86: VeraType[], u86: VeraType, v86: boolean, w86: string, x86: number = -1) {
        super();
        this.parameters = t86;
        this.result = u86;
        this.isAsync = v86;
        this.identity = w86;
        this.required = x86 < 0 ? t86.length : x86;
    }
    display(): string {
        let r86: string[] = [];
        for (let s86 = 0; s86 < this.parameters.length; s86++) {
            r86.push(this.parameters[s86].display());
        }
        return 'function (' + r86.join(', ') + '): ' + this.result.display();
    }
}
class NamespaceType extends VeraType {
    name: string;
    members: Map<string, VeraType>;
    constructor(p86: string, q86: Map<string, VeraType>) { super(); this.name = p86; this.members = q86; }
    display(): string { return 'namespace ' + this.name; }
}
class VeraNullType extends VeraType {
    display(): string { return 'null'; }
}
const INT = new PrimitiveType('int');
const NUMBER = new PrimitiveType('number');
const BOOLEAN = new PrimitiveType('boolean');
const STRING = new PrimitiveType('string');
const VOID = new PrimitiveType('void');
const NULL_TYPE = new VeraNullType();
function identical(m86: VeraType, n86: VeraType): boolean {
    if (m86 === n86)
        return true;
    if (m86 instanceof VeraArrayType && n86 instanceof VeraArrayType)
        return identical(m86.element, n86.element);
    if (m86 instanceof NullableType && n86 instanceof NullableType)
        return identical(m86.base, n86.base);
    if (m86 instanceof VeraFunctionType && n86 instanceof VeraFunctionType) {
        if (m86.isAsync !== n86.isAsync)
            return false;
        if (m86.parameters.length !== n86.parameters.length)
            return false;
        for (let o86 = 0; o86 < m86.parameters.length; o86++) {
            if (!identical(m86.parameters[o86], n86.parameters[o86]))
                return false;
        }
        return identical(m86.result, n86.result);
    }
    return false;
}
function subtypeOf(j86: VeraType, k86: VeraType): boolean {
    if (identical(j86, k86))
        return true;
    if (k86 instanceof NullableType && (subtypeOf(j86, k86.base) || j86 instanceof VeraNullType))
        return true;
    if (j86 instanceof VeraFunctionType && k86 instanceof VeraFunctionType) {
        if (j86.isAsync !== k86.isAsync)
            return false;
        if (j86.parameters.length > k86.parameters.length)
            return false;
        for (let l86 = 0; l86 < j86.parameters.length; l86++) {
            if (!subtypeOf(k86.parameters[l86], j86.parameters[l86]))
                return false;
        }
        return subtypeOf(j86.result, k86.result);
    }
    return false;
}
function assignable(h86: VeraType, i86: VeraType): boolean {
    return subtypeOf(h86, i86);
}
export class Diagnostic {
    code: string;
    message: string;
    span: Span;
    expected: string;
    actual: string;
    constructor(c86: string, d86: string, e86: Span, f86: string = '', g86: string = '') {
        this.code = c86;
        this.message = d86;
        this.span = e86;
        this.expected = f86;
        this.actual = g86;
    }
}
export class CompileError extends Error {
    diagnostics: Diagnostic[];
    constructor(z85: Diagnostic[]) {
        let a86: string[] = [];
        for (let b86 of z85) {
            a86.push(b86.span.start.line + ':' + b86.span.start.column + ' ' + b86.code + ' ' + b86.message);
        }
        super(a86.join('\n'));
        this.diagnostics = z85;
    }
}
class Token {
    kind: string;
    text: string;
    span: Span;
    constructor(w85: string, x85: string, y85: Span) {
        this.kind = w85;
        this.text = x85;
        this.span = y85;
    }
}
const KEYWORDS: string[] = [
    'import', 'as', 'from', 'class', 'function', 'async', 'let', 'if', 'else',
    'while', 'for', 'of', 'break', 'continue', 'return', 'true', 'false', 'null',
    'try', 'catch', 'new'
];
function isAlpha(v85: string): boolean {
    return (v85 >= 'a' && v85 <= 'z') || (v85 >= 'A' && v85 <= 'Z') || v85 === '_';
}
function isDigit(u85: string): boolean {
    return u85 >= '0' && u85 <= '9';
}
function isAlnum(t85: string): boolean {
    return isAlpha(t85) || isDigit(t85);
}
class Lexer {
    private source: string;
    private sourceName: string;
    private pos: number = 0;
    private line: number = 1;
    private col: number = 1;
    constructor(r85: string, s85: string) {
        this.source = r85;
        this.sourceName = s85;
    }
    scan(): Token[] {
        let o85: Token[] = [];
        while (this.pos < this.source.length) {
            this.skipWhitespaceAndComments();
            if (this.pos >= this.source.length)
                break;
            let p85 = this.makePos();
            let q85 = this.source[this.pos];
            if (isAlpha(q85)) {
                o85.push(this.scanIdentifier(p85));
                continue;
            }
            if (isDigit(q85)) {
                o85.push(this.scanNumber(p85));
                continue;
            }
            if (q85 === '"') {
                o85.push(this.scanString(p85));
                continue;
            }
            if (q85 === '@') {
                this.pos++;
                this.col++;
                o85.push(this.scanIdentifier(p85));
                o85[o85.length - 1].kind = 'annotation';
                continue;
            }
            o85.push(this.scanSymbol(p85));
        }
        o85.push(new Token('eof', '', this.makeSpan(this.makePos())));
        return o85;
    }
    private skipWhitespaceAndComments(): void {
        while (this.pos < this.source.length) {
            let n85 = this.source[this.pos];
            if (n85 === ' ' || n85 === '\t' || n85 === '\r') {
                this.pos++;
                this.col++;
                continue;
            }
            if (n85 === '\n') {
                this.pos++;
                this.line++;
                this.col = 1;
                continue;
            }
            if (n85 === '/' && this.pos + 1 < this.source.length && this.source[this.pos + 1] === '/') {
                while (this.pos < this.source.length && this.source[this.pos] !== '\n') {
                    this.pos++;
                    this.col++;
                }
                continue;
            }
            break;
        }
    }
    private scanIdentifier(i85: Position): Token {
        let j85 = this.pos;
        while (this.pos < this.source.length && isAlnum(this.source[this.pos])) {
            this.pos++;
            this.col++;
        }
        let k85 = this.source.substring(j85, this.pos);
        let l85 = 'name';
        if (k85 === 'true' || k85 === 'false')
            l85 = 'boolean';
        else if (k85 === 'null')
            l85 = 'null';
        else {
            for (let m85 of KEYWORDS) {
                if (m85 === k85) {
                    l85 = k85;
                    break;
                }
            }
        }
        return new Token(l85, k85, this.makeSpan(i85));
    }
    private scanNumber(g85: Position): Token {
        let h85 = this.pos;
        while (this.pos < this.source.length && isDigit(this.source[this.pos])) {
            this.pos++;
            this.col++;
        }
        if (this.pos < this.source.length && this.source[this.pos] === '.' && this.pos + 1 < this.source.length && isDigit(this.source[this.pos + 1])) {
            this.pos++;
            this.col++;
            while (this.pos < this.source.length && isDigit(this.source[this.pos])) {
                this.pos++;
                this.col++;
            }
            return new Token('number', this.source.substring(h85, this.pos), this.makeSpan(g85));
        }
        return new Token('integer', this.source.substring(h85, this.pos), this.makeSpan(g85));
    }
    private scanString(d85: Position): Token {
        this.pos++;
        this.col++;
        let e85 = '';
        while (this.pos < this.source.length && this.source[this.pos] !== '"') {
            if (this.source[this.pos] === '\\') {
                this.pos++;
                this.col++;
                if (this.pos >= this.source.length)
                    break;
                let f85 = this.source[this.pos];
                if (f85 === 'n')
                    e85 += '\n';
                else if (f85 === 't')
                    e85 += '\t';
                else if (f85 === '\\')
                    e85 += '\\';
                else if (f85 === '"')
                    e85 += '"';
                else
                    e85 += f85;
                this.pos++;
                this.col++;
            }
            else {
                if (this.source[this.pos] === '\n') {
                    this.line++;
                    this.col = 0;
                }
                e85 += this.source[this.pos];
                this.pos++;
                this.col++;
            }
        }
        if (this.pos < this.source.length) {
            this.pos++;
            this.col++;
        }
        return new Token('string', e85, this.makeSpan(d85));
    }
    private scanSymbol(a85: Position): Token {
        let b85 = this.source[this.pos];
        this.pos++;
        this.col++;
        if (this.pos < this.source.length) {
            let c85 = b85 + this.source[this.pos];
            if (c85 === '==') {
                this.pos++;
                this.col++;
                if (this.pos < this.source.length && this.source[this.pos] === '=') {
                    this.pos++;
                    this.col++;
                    return new Token('===', '===', this.makeSpan(a85));
                }
                return new Token('==', '==', this.makeSpan(a85));
            }
            if (c85 === '!=') {
                this.pos++;
                this.col++;
                if (this.pos < this.source.length && this.source[this.pos] === '=') {
                    this.pos++;
                    this.col++;
                    return new Token('!==', '!==', this.makeSpan(a85));
                }
                return new Token('!=', '!=', this.makeSpan(a85));
            }
            if (c85 === '&&' || c85 === '||' || c85 === '<=' || c85 === '>=') {
                this.pos++;
                this.col++;
                return new Token(c85, c85, this.makeSpan(a85));
            }
        }
        return new Token(b85, b85, this.makeSpan(a85));
    }
    private makePos(): Position { return new Position(this.pos, this.line, this.col); }
    private makeSpan(z84: Position): Span { return new Span(z84, this.makePos(), this.sourceName); }
}
class Parser {
    private tokens: Token[];
    private pos: number = 0;
    private sourceName: string;
    constructor(x84: string, y84: string) {
        this.sourceName = y84;
        this.tokens = new Lexer(x84, y84).scan();
    }
    parse(): Application {
        let t84 = this.current().span;
        let u84: ImportDeclaration[] = [];
        let v84: Declaration[] = [];
        while (!this.atEnd()) {
            if (this.check('import')) {
                u84.push(this.parseImport());
                continue;
            }
            if (this.check('annotation')) {
                let w84 = this.advance();
                v84.push(this.parseClass(w84.text));
                continue;
            }
            if (this.check('class')) {
                v84.push(this.parseClass(null));
                continue;
            }
            if (this.check('async')) {
                v84.push(this.parseFunction());
                continue;
            }
            if (this.check('function')) {
                v84.push(this.parseFunction());
                continue;
            }
            this.error('expected import, class, or function declaration');
        }
        return new Application(this.span(t84), u84, v84);
    }
    private parseImport(): ImportDeclaration {
        let q84 = this.current().span;
        this.expect('import');
        this.expect('*');
        this.expect('as');
        let r84 = this.expect('name').text;
        this.expect('from');
        let s84 = this.expect('string').text;
        return new ImportDeclaration(this.span(q84), r84, s84);
    }
    private parseClass(j84: string | null): ClassDeclaration {
        let k84 = this.current().span;
        this.expect('class');
        let l84 = this.expect('name').text;
        this.expect('{');
        let m84: FieldDeclaration[] = [];
        while (!this.check('}') && !this.atEnd()) {
            let n84 = this.current().span;
            let o84 = this.expect('name').text;
            this.expect(':');
            let p84 = this.parseType();
            if (this.check(';'))
                this.advance();
            m84.push(new FieldDeclaration(this.span(n84), o84, p84));
        }
        this.expect('}');
        return new ClassDeclaration(this.span(k84), l84, m84, j84);
    }
    private parseFunction(): FunctionDeclaration {
        let d84 = this.current().span;
        let e84 = false;
        if (this.check('async')) {
            this.advance();
            e84 = true;
        }
        this.expect('function');
        let f84 = this.expect('name').text;
        this.expect('(');
        let g84 = this.parseParameters();
        this.expect(')');
        this.expect(':');
        let h84 = this.parseType();
        let i84 = this.parseBlock();
        return new FunctionDeclaration(this.span(d84), f84, g84, h84, i84, e84);
    }
    private parseParameters(): Parameter[] {
        let z83: Parameter[] = [];
        if (this.check(')'))
            return z83;
        while (true) {
            let a84 = this.current().span;
            let b84 = this.expect('name').text;
            this.expect(':');
            let c84 = this.parseType();
            z83.push(new Parameter(this.span(a84), b84, c84));
            if (!this.check(','))
                break;
            this.advance();
        }
        return z83;
    }
    private parseType(): TypeNode {
        let x83 = this.current().span;
        let y83 = this.parseBaseType();
        if (this.check('|')) {
            this.advance();
            this.expect('null');
            y83 = new TypeNode(this.span(x83), y83.name, y83.parts, true);
        }
        return y83;
    }
    private parseBaseType(): TypeNode {
        let n83 = this.current().span;
        if (this.check('(')) {
            this.advance();
            let u83: TypeNode[] = [];
            if (!this.check(')')) {
                while (true) {
                    let w83 = this.current().span;
                    this.expect('name');
                    this.expect(':');
                    u83.push(this.parseType());
                    if (!this.check(','))
                        break;
                    this.advance();
                }
            }
            this.expect(')');
            this.expect('=');
            this.expect('>');
            let v83 = this.parseType();
            u83.push(v83);
            return new TypeNode(this.span(n83), 'function', u83);
        }
        if (this.check('async')) {
            this.advance();
            this.expect('(');
            let r83: TypeNode[] = [];
            if (!this.check(')')) {
                while (true) {
                    let t83 = this.current().span;
                    this.expect('name');
                    this.expect(':');
                    r83.push(this.parseType());
                    if (!this.check(','))
                        break;
                    this.advance();
                }
            }
            this.expect(')');
            this.expect('=');
            this.expect('>');
            let s83 = this.parseType();
            r83.push(s83);
            return new TypeNode(this.span(n83), 'async-function', r83);
        }
        let o83 = this.expect('name').text;
        if (this.check('.')) {
            this.advance();
            let q83 = this.expect('name').text;
            o83 = o83 + '.' + q83;
        }
        if (this.check('[')) {
            this.advance();
            this.expect(']');
            let p83 = new TypeNode(this.span(n83), o83);
            return new TypeNode(this.span(n83), 'array', [p83]);
        }
        return new TypeNode(this.span(n83), o83);
    }
    private parseBlock(): BlockStatement {
        let l83 = this.current().span;
        this.expect('{');
        let m83: Statement[] = [];
        while (!this.check('}') && !this.atEnd()) {
            m83.push(this.parseStatement());
        }
        this.expect('}');
        return new BlockStatement(this.span(l83), m83);
    }
    private parseStatement(): Statement {
        if (this.check('let'))
            return this.parseLet();
        if (this.check('if'))
            return this.parseIf();
        if (this.check('while'))
            return this.parseWhile();
        if (this.check('for'))
            return this.parseFor();
        if (this.check('break')) {
            let k83 = this.current().span;
            this.advance();
            if (this.check(';'))
                this.advance();
            return new BreakStatement(this.span(k83));
        }
        if (this.check('continue')) {
            let j83 = this.current().span;
            this.advance();
            if (this.check(';'))
                this.advance();
            return new ContinueStatement(this.span(j83));
        }
        if (this.check('return'))
            return this.parseReturn();
        if (this.check('try'))
            return this.parseTry();
        if (this.check('{'))
            return this.parseBlock();
        return this.parseExpressionOrAssign();
    }
    private parseLet(): LetStatement {
        let f83 = this.current().span;
        this.expect('let');
        let g83 = this.expect('name').text;
        this.expect(':');
        let h83 = this.parseType();
        this.expect('=');
        let i83 = this.parseExpression();
        if (this.check(';'))
            this.advance();
        return new LetStatement(this.span(f83), g83, h83, i83);
    }
    private parseIf(): IfStatement {
        let b83 = this.current().span;
        this.expect('if');
        this.expect('(');
        let c83 = this.parseExpression();
        this.expect(')');
        let d83 = this.parseBlock();
        let e83: Statement | null = null;
        if (this.check('else')) {
            this.advance();
            if (this.check('if'))
                e83 = this.parseIf();
            else
                e83 = this.parseBlock();
        }
        return new IfStatement(this.span(b83), c83, d83, e83);
    }
    private parseWhile(): WhileStatement {
        let y82 = this.current().span;
        this.expect('while');
        this.expect('(');
        let z82 = this.parseExpression();
        this.expect(')');
        let a83 = this.parseBlock();
        return new WhileStatement(this.span(y82), z82, a83);
    }
    private parseFor(): ForOfStatement {
        let t82 = this.current().span;
        this.expect('for');
        this.expect('(');
        this.expect('let');
        let u82 = this.expect('name').text;
        this.expect(':');
        let v82 = this.parseType();
        this.expect('of');
        let w82 = this.parseExpression();
        this.expect(')');
        let x82 = this.parseBlock();
        return new ForOfStatement(this.span(t82), u82, v82, w82, x82);
    }
    private parseReturn(): ReturnStatement {
        let r82 = this.current().span;
        this.expect('return');
        let s82: Expression | null = null;
        if (!this.check('}') && !this.check(';') && !this.atEnd()) {
            s82 = this.parseExpression();
        }
        if (this.check(';'))
            this.advance();
        return new ReturnStatement(this.span(r82), s82);
    }
    private parseTry(): TryStatement {
        let n82 = this.current().span;
        this.expect('try');
        let o82 = this.parseBlock();
        this.expect('catch');
        this.expect('(');
        let p82 = this.expect('name').text;
        this.expect(')');
        let q82 = this.parseBlock();
        return new TryStatement(this.span(n82), o82, p82, q82);
    }
    private parseExpressionOrAssign(): Statement {
        let k82 = this.current().span;
        let l82 = this.parseExpression();
        if (this.check('=')) {
            this.advance();
            let m82 = this.parseExpression();
            if (this.check(';'))
                this.advance();
            return new AssignStatement(this.span(k82), l82, m82);
        }
        if (this.check(';'))
            this.advance();
        return new ExpressionStatement(this.span(k82), l82);
    }
    private parseExpression(): Expression {
        return this.parseBinary(0);
    }
    private parseBinary(e82: number): Expression {
        let f82 = this.parseUnary();
        while (true) {
            let g82 = this.current().kind;
            let h82 = this.precedence(g82);
            if (h82 < 0 || h82 < e82)
                break;
            let i82 = f82.span;
            this.advance();
            let j82 = this.parseBinary(h82 + 1);
            f82 = new BinaryExpression(this.span(i82), f82, g82, j82);
        }
        return f82;
    }
    private precedence(d82: string): number {
        if (d82 === '||')
            return 1;
        if (d82 === '&&')
            return 2;
        if (d82 === '===' || d82 === '!==')
            return 3;
        if (d82 === '<' || d82 === '<=' || d82 === '>' || d82 === '>=')
            return 4;
        if (d82 === '+' || d82 === '-')
            return 5;
        if (d82 === '*' || d82 === '/' || d82 === '%')
            return 6;
        return -1;
    }
    private parseUnary(): Expression {
        let z81 = this.current().span;
        if (this.check('-')) {
            this.advance();
            let c82 = this.parseUnary();
            return new UnaryExpression(this.span(z81), '-', c82);
        }
        if (this.check('!')) {
            this.advance();
            let b82 = this.parseUnary();
            return new UnaryExpression(this.span(z81), '!', b82);
        }
        if (this.check('await')) {
            this.advance();
            let a82 = this.parseUnary();
            return new AwaitExpression(this.span(z81), a82);
        }
        return this.parsePostfix();
    }
    private parsePostfix(): Expression {
        let r81 = this.parsePrimary();
        while (true) {
            if (this.check('(')) {
                let x81 = r81.span;
                this.advance();
                let y81: Expression[] = [];
                if (!this.check(')')) {
                    while (true) {
                        y81.push(this.parseExpression());
                        if (!this.check(','))
                            break;
                        this.advance();
                    }
                }
                this.expect(')');
                r81 = new CallExpression(this.span(x81), r81, y81);
            }
            else if (this.check('[')) {
                let v81 = r81.span;
                this.advance();
                let w81 = this.parseExpression();
                this.expect(']');
                r81 = new IndexExpression(this.span(v81), r81, w81);
            }
            else if (this.check('.')) {
                let t81 = r81.span;
                this.advance();
                let u81 = this.expect('name').text;
                r81 = new SelectExpression(this.span(t81), r81, u81);
            }
            else if (this.check('!')) {
                let s81 = r81.span;
                this.advance();
                r81 = new EnsureNotNullExpression(this.span(s81), r81);
            }
            else {
                break;
            }
        }
        return r81;
    }
    private parsePrimary(): Expression {
        let d81 = this.current().span;
        if (this.check('name')) {
            let q81 = this.advance().text;
            return new NameExpression(this.span(d81), q81);
        }
        if (this.check('integer')) {
            let o81 = this.advance().text;
            let p81 = parseInt(o81);
            return new IntExpression(this.span(d81), p81);
        }
        if (this.check('number')) {
            let m81 = this.advance().text;
            let n81 = parseFloat(m81);
            return new NumberExpression(this.span(d81), n81);
        }
        if (this.check('string')) {
            let l81 = this.advance().text;
            return new StringExpression(this.span(d81), l81);
        }
        if (this.check('boolean')) {
            let k81 = this.advance().text;
            return new BooleanExpression(this.span(d81), k81 === 'true');
        }
        if (this.check('null')) {
            this.advance();
            return new NullExpression(this.span(d81));
        }
        if (this.check('(')) {
            this.advance();
            if (this.check(')') || this.isLambdaStart()) {
                return this.parseLambda(d81);
            }
            let j81 = this.parseExpression();
            this.expect(')');
            return j81;
        }
        if (this.check('[')) {
            this.advance();
            let i81: Expression[] = [];
            if (!this.check(']')) {
                while (true) {
                    i81.push(this.parseExpression());
                    if (!this.check(','))
                        break;
                    this.advance();
                }
            }
            this.expect(']');
            return new ArrayExpression(this.span(d81), i81);
        }
        if (this.check('{')) {
            this.advance();
            let e81: Property[] = [];
            if (!this.check('}')) {
                while (true) {
                    let f81 = this.current().span;
                    let g81 = this.expect('name').text;
                    this.expect(':');
                    let h81 = this.parseExpression();
                    e81.push(new Property(this.span(f81), g81, h81));
                    if (!this.check(','))
                        break;
                    this.advance();
                }
            }
            this.expect('}');
            return new ObjectExpression(this.span(d81), e81);
        }
        this.error('expected expression');
        return new NullExpression(this.span(d81));
    }
    private isLambdaStart(): boolean {
        let b81 = this.pos;
        if (this.check('name')) {
            this.advance();
            let c81 = this.check(':');
            this.pos = b81;
            return c81;
        }
        this.pos = b81;
        return false;
    }
    private parseLambda(u80: Span): LambdaExpression {
        let v80: Parameter[] = [];
        if (!this.check(')')) {
            while (true) {
                let y80 = this.current().span;
                let z80 = this.expect('name').text;
                this.expect(':');
                let a81 = this.parseType();
                v80.push(new Parameter(this.span(y80), z80, a81));
                if (!this.check(','))
                    break;
                this.advance();
            }
        }
        this.expect(')');
        this.expect(':');
        let w80 = this.parseType();
        this.expect('=');
        this.expect('>');
        let x80 = this.parseBlock();
        return new LambdaExpression(this.span(u80), v80, w80, x80);
    }
    private current(): Token { return this.tokens[this.pos]; }
    private atEnd(): boolean { return this.current().kind === 'eof'; }
    private check(t80: string): boolean { return this.current().kind === t80; }
    private advance(): Token { let s80 = this.current(); this.pos++; return s80; }
    private expect(r80: string): Token {
        if (!this.check(r80))
            this.error('expected ' + r80 + ', found ' + this.current().kind);
        return this.advance();
    }
    private span(q80: Span): Span { return new Span(q80.start, this.tokens[this.pos > 0 ? this.pos - 1 : 0].span.end, this.sourceName); }
    private error(o80: string): never {
        let p80 = this.current().span;
        throw new CompileError([new Diagnostic('E1001', o80, p80)]);
    }
}
class ExternalFunction {
    name: string;
    parameters: VeraType[];
    result: VeraType;
    isAsync: boolean;
    required: number;
    constructor(j80: string, k80: VeraType[], l80: VeraType, m80: boolean, n80: number = -1) {
        this.name = j80;
        this.parameters = k80;
        this.result = l80;
        this.isAsync = m80;
        this.required = n80 < 0 ? k80.length : n80;
    }
}
class ExternalClass {
    name: string;
    type: VeraClassType;
    constructor(h80: string, i80: VeraClassType) {
        this.name = h80;
        this.type = i80;
    }
}
class ModuleInterface {
    specifier: string;
    functions: ExternalFunction[];
    classes: ExternalClass[];
    constructor(e80: string, f80: ExternalFunction[], g80: ExternalClass[]) {
        this.specifier = e80;
        this.functions = f80;
        this.classes = g80;
    }
}
function buildStdUiModule(): ModuleInterface {
    let x79 = new VeraClassType('std/ui:View', 'View');
    let y79 = new VeraArrayType(x79);
    let z79: ExternalFunction[] = [];
    for (let a80 of CATALOG) {
        let b80: VeraType[] = [];
        for (let d80 of a80.props) {
            if (d80.kind === 'int')
                b80.push(INT);
            else if (d80.kind === 'boolean')
                b80.push(BOOLEAN);
            else if (d80.kind === 'view')
                b80.push(x79);
            else if (d80.kind === 'view[]')
                b80.push(y79);
            else if (d80.kind === 'string[]')
                b80.push(new VeraArrayType(STRING));
            else if (d80.kind === 'int[]')
                b80.push(new VeraArrayType(INT));
            else
                b80.push(STRING);
        }
        let c80 = b80.length;
        while (c80 > 0 && a80.props[c80 - 1].optional) {
            c80 -= 1;
        }
        z79.push(new ExternalFunction(a80.name, b80, x79, false, c80));
    }
    z79.push(new ExternalFunction('When', [BOOLEAN, x79], x79, false));
    z79.push(new ExternalFunction('intToString', [INT], STRING, false));
    z79.push(new ExternalFunction('numberToString', [NUMBER], STRING, false));
    z79.push(new ExternalFunction('booleanToString', [BOOLEAN], STRING, false));
    return new ModuleInterface('std/ui', z79, [new ExternalClass('View', x79)]);
}
function buildStdMathModule(): ModuleInterface {
    let w79: ExternalFunction[] = [
        new ExternalFunction('intToNumber', [INT], NUMBER, false),
        new ExternalFunction('numberToInt', [NUMBER], INT, false),
        new ExternalFunction('pi', [], NUMBER, false),
        new ExternalFunction('sqrt', [NUMBER], NUMBER, false),
        new ExternalFunction('sin', [NUMBER], NUMBER, false),
        new ExternalFunction('cos', [NUMBER], NUMBER, false),
        new ExternalFunction('atan2', [NUMBER, NUMBER], NUMBER, false),
        new ExternalFunction('pow', [NUMBER, NUMBER], NUMBER, false),
        new ExternalFunction('floorToInt', [NUMBER], INT, false),
        new ExternalFunction('roundToInt', [NUMBER], INT, false),
        new ExternalFunction('absInt', [INT], INT, false),
        new ExternalFunction('absNumber', [NUMBER], NUMBER, false),
        new ExternalFunction('minInt', [INT, INT], INT, false),
        new ExternalFunction('maxInt', [INT, INT], INT, false),
        new ExternalFunction('minNumber', [NUMBER, NUMBER], NUMBER, false),
        new ExternalFunction('maxNumber', [NUMBER, NUMBER], NUMBER, false),
        new ExternalFunction('randomStep', [INT], INT, false),
        new ExternalFunction('randomBelow', [INT, INT], INT, false),
    ];
    return new ModuleInterface('std/math', w79, []);
}
function buildStdTimeModule(): ModuleInterface {
    let v79: ExternalFunction[] = [
        new ExternalFunction('nowSeconds', [], INT, false),
        new ExternalFunction('millisOfDay', [], INT, false),
        new ExternalFunction('daysSinceEpoch', [], INT, false),
        new ExternalFunction('hourOfDay', [], INT, false),
        new ExternalFunction('minuteOfHour', [], INT, false),
        new ExternalFunction('weekday', [], INT, false),
        new ExternalFunction('dayOfMonth', [], INT, false),
        new ExternalFunction('monthOfYear', [], INT, false),
        new ExternalFunction('year', [], INT, false),
    ];
    return new ModuleInterface('std/time', v79, []);
}
function buildStdStringsModule(): ModuleInterface {
    let u79: ExternalFunction[] = [
        new ExternalFunction('length', [STRING], INT, false),
        new ExternalFunction('substring', [STRING, INT, INT], STRING, false),
        new ExternalFunction('contains', [STRING, STRING], BOOLEAN, false),
        new ExternalFunction('startsWith', [STRING, STRING], BOOLEAN, false),
        new ExternalFunction('endsWith', [STRING, STRING], BOOLEAN, false),
        new ExternalFunction('replace', [STRING, STRING, STRING], STRING, false),
        new ExternalFunction('split', [STRING, STRING], new VeraArrayType(STRING), false),
        new ExternalFunction('trim', [STRING], STRING, false),
    ];
    return new ModuleInterface('std/strings', u79, []);
}
function buildStdSdkModule(): ModuleInterface {
    let t79: ExternalFunction[] = [
        new ExternalFunction('call', [STRING, new VeraArrayType(STRING), STRING, STRING], INT, false, 3)
    ];
    return new ModuleInterface('std/sdk', t79, []);
}
class Scope {
    values: Map<string, VeraType> = new Map<string, VeraType>();
    parent: Scope | null;
    constructor(s79: Scope | null) { this.parent = s79; }
    find(q79: string): VeraType | null {
        let r79 = this.values.get(q79);
        if (r79 !== undefined)
            return r79;
        if (this.parent !== null)
            return this.parent.find(q79);
        return null;
    }
}
class SemanticModel {
    expressionTypes: Map<Expression, VeraType> = new Map<Expression, VeraType>();
    declaredTypes: Map<TypeNode, VeraType> = new Map<TypeNode, VeraType>();
    functions: Map<string, VeraFunctionType> = new Map<string, VeraFunctionType>();
    classes: Map<string, VeraClassType> = new Map<string, VeraClassType>();
    imports: Map<string, ModuleInterface> = new Map<string, ModuleInterface>();
    application: Application;
    constructor(p79: Application) { this.application = p79; }
}
class Narrowing {
    whenTrue: Scope;
    whenFalse: Scope;
    constructor(n79: Scope, o79: Scope) { this.whenTrue = n79; this.whenFalse = o79; }
}
class Analyzer {
    private diagnostics: Diagnostic[] = [];
    private model: SemanticModel;
    private globals: Scope = new Scope(null);
    private returnType: VeraType = VOID;
    private inAsyncFunction: boolean = false;
    private loopDepth: number = 0;
    private lambdaCount: number = 0;
    constructor(m79: Application) {
        this.model = new SemanticModel(m79);
    }
    analyze(): SemanticModel {
        this.collectImports();
        for (let k79 of this.model.application.declarations) {
            if (!(k79 instanceof ClassDeclaration) && !(k79 instanceof FunctionDeclaration))
                continue;
            if (this.globals.find(k79.name) !== null) {
                this.addError('E2001', 'duplicate global ' + k79.name, k79.span);
                continue;
            }
            if (k79 instanceof ClassDeclaration) {
                let l79 = new VeraClassType('local:' + k79.name, k79.name);
                this.model.classes.set(k79.name, l79);
                this.globals.values.set(k79.name, l79);
            }
            else {
                this.globals.values.set(k79.name, new VeraFunctionType([], VOID, (k79 as FunctionDeclaration).isAsync, 'pending:' + k79.name));
            }
        }
        for (let f79 of this.model.application.declarations) {
            if (!(f79 instanceof FunctionDeclaration))
                continue;
            let g79: VeraType[] = [];
            for (let j79 of f79.parameters)
                g79.push(this.resolveType(j79.type));
            let h79 = this.resolveType(f79.returnType);
            let i79 = new VeraFunctionType(g79, h79, f79.isAsync, 'function:' + f79.name);
            this.model.functions.set(f79.name, i79);
            this.globals.values.set(f79.name, i79);
        }
        for (let e79 of this.model.application.declarations) {
            if (e79 instanceof ClassDeclaration)
                this.checkClass(e79);
        }
        this.checkJsonableCycles();
        for (let d79 of this.model.application.declarations) {
            if (d79 instanceof FunctionDeclaration)
                this.checkFunction(d79);
        }
        if (this.diagnostics.length > 0)
            throw new CompileError(this.diagnostics);
        return this.model;
    }
    private collectImports(): void {
        let w78 = new Map<string, ModuleInterface>();
        w78.set('std/ui', buildStdUiModule());
        w78.set('std/time', buildStdTimeModule());
        w78.set('std/math', buildStdMathModule());
        w78.set('std/strings', buildStdStringsModule());
        w78.set('std/sdk', buildStdSdkModule());
        for (let x78 of this.model.application.imports) {
            if (this.globals.find(x78.name) !== null) {
                this.addError('E2001', 'duplicate global ' + x78.name, x78.span);
                continue;
            }
            let y78 = w78.get(x78.specifier);
            let z78: ModuleInterface | null = y78 !== undefined ? y78 : null;
            if (z78 === null) {
                this.addError('E2002', 'module not found: ' + x78.specifier, x78.span);
                continue;
            }
            let a79 = new Map<string, VeraType>();
            for (let c79 of z78.functions)
                a79.set(c79.name, new VeraFunctionType(c79.parameters, c79.result, c79.isAsync, 'external:' + z78.specifier + ':' + c79.name, c79.required));
            for (let b79 of z78.classes)
                a79.set(b79.name, b79.type);
            this.model.imports.set(x78.name, z78);
            this.globals.values.set(x78.name, new NamespaceType(x78.name, a79));
        }
    }
    private checkClass(t78: ClassDeclaration): void {
        let u78 = this.model.classes.get(t78.name);
        if (u78 === undefined)
            return;
        if (t78.annotation !== null && t78.annotation !== 'jsonable')
            this.addError('E2039', 'unknown annotation ' + t78.annotation, t78.span);
        for (let v78 of t78.fields) {
            if (u78.fields.has(v78.name))
                this.addError('E2003', 'duplicate field ' + v78.name, v78.span);
            else
                u78.fields.set(v78.name, this.resolveType(v78.type));
        }
    }
    private checkJsonableCycles(): void {
        let m78: ClassDeclaration[] = [];
        for (let s78 of this.model.application.declarations) {
            if (s78 instanceof ClassDeclaration && s78.annotation === 'jsonable')
                m78.push(s78);
        }
        let n78 = new Set<string>();
        let o78 = new Set<string>();
        let p78 = new Set<string>();
        for (let r78 of m78)
            p78.add(r78.name);
        for (let q78 of m78) {
            if (this.visitJsonable(q78.name, p78, n78, o78)) {
                this.addError('E2040', 'circular jsonable dependency involving ' + q78.name, q78.span);
                break;
            }
        }
    }
    private visitJsonable(e78: string, f78: Set<string>, g78: Set<string>, h78: Set<string>): boolean {
        if (g78.has(e78))
            return true;
        if (h78.has(e78))
            return false;
        g78.add(e78);
        let i78 = this.model.classes.get(e78);
        if (i78 !== undefined) {
            let j78 = Array.from(i78.fields.values());
            for (let k78 of j78) {
                let l78 = this.localClass(k78);
                if (l78 !== null && f78.has(l78.name) && this.visitJsonable(l78.name, f78, g78, h78))
                    return true;
            }
        }
        g78.delete(e78);
        h78.add(e78);
        return false;
    }
    private localClass(d78: VeraType): VeraClassType | null {
        if (d78 instanceof NullableType)
            return this.localClass(d78.base);
        if (d78 instanceof VeraArrayType)
            return this.localClass(d78.element);
        if (d78 instanceof VeraClassType && d78.identity.startsWith('local:'))
            return d78;
        return null;
    }
    private checkFunction(v77: FunctionDeclaration): void {
        let w77 = this.model.functions.get(v77.name);
        if (w77 === undefined)
            return;
        let x77 = this.returnType;
        let y77 = this.inAsyncFunction;
        this.returnType = w77.result;
        this.inAsyncFunction = v77.isAsync;
        let z77 = new Scope(this.globals);
        for (let b78 = 0; b78 < v77.parameters.length; b78++) {
            let c78 = v77.parameters[b78];
            if (z77.find(c78.name) !== null)
                this.addError('E2004', 'declaration ' + c78.name + ' shadows a visible entity', c78.span);
            else
                z77.values.set(c78.name, w77.parameters[b78]);
        }
        let a78 = this.checkBlock(v77.body, z77);
        if (!identical(this.returnType, VOID) && !a78)
            this.addError('E2018', 'function ' + v77.name + ' may not return a value', v77.body.span);
        this.returnType = x77;
        this.inAsyncFunction = y77;
    }
    private checkBlock(q77: BlockStatement, r77: Scope): boolean {
        let s77 = new Scope(r77);
        let t77 = false;
        for (let u77 of q77.statements) {
            if (this.checkStatement(u77, s77))
                t77 = true;
        }
        return t77;
    }
    private checkStatement(c77: Statement, d77: Scope): boolean {
        if (c77 instanceof BlockStatement)
            return this.checkBlock(c77, d77);
        if (c77 instanceof LetStatement) {
            let p77 = this.resolveType(c77.type);
            this.checkExpression(c77.initializer, d77, p77);
            if (d77.find(c77.name) !== null)
                this.addError('E2004', 'declaration ' + c77.name + ' shadows a visible entity', c77.span);
            else
                d77.values.set(c77.name, p77);
            return false;
        }
        if (c77 instanceof AssignStatement) {
            let o77 = this.checkAssignable(c77.target, d77);
            this.checkExpression(c77.value, d77, o77);
            return false;
        }
        if (c77 instanceof ExpressionStatement) {
            this.checkExpression(c77.expression, d77, null);
            if (!(c77.expression instanceof CallExpression) && !(c77.expression instanceof AwaitExpression)) {
                this.addError('E2005', 'expression statement must be a function call', c77.span);
            }
            return false;
        }
        if (c77 instanceof IfStatement) {
            this.requireType(this.checkExpression(c77.condition, d77, BOOLEAN), BOOLEAN, c77.condition);
            let l77 = this.narrow(c77.condition, d77);
            let m77 = this.checkBlock(c77.thenBranch, l77.whenTrue);
            let n77 = c77.elseBranch === null ? false : this.checkStatement(c77.elseBranch, l77.whenFalse);
            return m77 && n77;
        }
        if (c77 instanceof WhileStatement) {
            this.requireType(this.checkExpression(c77.condition, d77, BOOLEAN), BOOLEAN, c77.condition);
            this.loopDepth += 1;
            this.checkBlock(c77.body, d77);
            this.loopDepth -= 1;
            return false;
        }
        if (c77 instanceof ForOfStatement) {
            let h77 = this.checkExpression(c77.iterable, d77, null);
            let i77 = this.resolveType(c77.type);
            let j77: VeraType | null = null;
            if (h77 instanceof VeraArrayType)
                j77 = h77.element;
            else if (identical(h77, STRING))
                j77 = STRING;
            else
                this.addError('E2006', 'for-of requires an array or string', c77.iterable.span);
            if (j77 !== null && !identical(j77, i77))
                this.typeError(c77.iterable, i77, j77);
            let k77 = new Scope(d77);
            if (k77.find(c77.name) !== null)
                this.addError('E2004', 'declaration ' + c77.name + ' shadows a visible entity', c77.span);
            else
                k77.values.set(c77.name, i77);
            this.loopDepth += 1;
            this.checkBlock(c77.body, k77);
            this.loopDepth -= 1;
            return false;
        }
        if (c77 instanceof BreakStatement || c77 instanceof ContinueStatement) {
            if (this.loopDepth === 0)
                this.addError('E2007', 'loop control used outside a loop', c77.span);
            return false;
        }
        if (c77 instanceof TryStatement) {
            let e77 = this.checkBlock(c77.tryBlock, d77);
            let f77 = new Scope(d77);
            f77.values.set(c77.catchName, STRING);
            let g77 = this.checkBlock(c77.catchBlock, f77);
            return e77 && g77;
        }
        if (c77 instanceof ReturnStatement) {
            if (c77.value === null) {
                if (!identical(this.returnType, VOID))
                    this.addError('E2008', 'return value required', c77.span);
            }
            else {
                if (identical(this.returnType, VOID))
                    this.addError('E2009', 'void function cannot return a value', c77.span);
                else
                    this.checkExpression(c77.value, d77, this.returnType);
            }
            return true;
        }
        return false;
    }
    private checkAssignable(z76: Expression, a77: Scope): VeraType {
        if (z76 instanceof NameExpression) {
            let b77 = a77.find(z76.name);
            if (b77 === null || a77 === this.globals || b77 instanceof VeraFunctionType || b77 instanceof VeraClassType || b77 instanceof NamespaceType) {
                this.addError('E2010', 'invalid assignment target', z76.span);
                return VOID;
            }
            return b77;
        }
        if (z76 instanceof IndexExpression || z76 instanceof SelectExpression)
            return this.checkExpression(z76, a77, null);
        this.addError('E2010', 'invalid assignment target', z76.span);
        return VOID;
    }
    private checkExpression(s76: Expression, t76: Scope, u76: VeraType | null): VeraType {
        let v76: VeraType = VOID;
        if (s76 instanceof IntExpression) {
            if (s76.value > 2147483647)
                this.addError('E2011', 'integer literal exceeds int32 range', s76.span);
            v76 = (u76 !== null && identical(u76, NUMBER)) ? NUMBER : INT;
        }
        else if (s76 instanceof NumberExpression)
            v76 = NUMBER;
        else if (s76 instanceof StringExpression)
            v76 = STRING;
        else if (s76 instanceof BooleanExpression)
            v76 = BOOLEAN;
        else if (s76 instanceof NullExpression)
            v76 = NULL_TYPE;
        else if (s76 instanceof NameExpression) {
            let y76 = t76.find(s76.name);
            if (y76 !== null)
                v76 = y76;
            else {
                v76 = VOID;
                this.addError('E2012', 'unknown name ' + s76.name, s76.span);
            }
        }
        else if (s76 instanceof ArrayExpression)
            v76 = this.checkArray(s76, t76, u76);
        else if (s76 instanceof ObjectExpression)
            v76 = this.checkObject(s76, t76, u76);
        else if (s76 instanceof UnaryExpression)
            v76 = this.checkUnary(s76, t76);
        else if (s76 instanceof BinaryExpression)
            v76 = this.checkBinary(s76, t76);
        else if (s76 instanceof IndexExpression) {
            let x76 = this.checkExpression(s76.target, t76, null);
            this.requireType(this.checkExpression(s76.index, t76, INT), INT, s76.index);
            if (x76 instanceof VeraArrayType)
                v76 = x76.element;
            else
                this.addError('E2013', 'index target must be an array', s76.target.span);
        }
        else if (s76 instanceof SelectExpression)
            v76 = this.checkSelect(s76, t76);
        else if (s76 instanceof EnsureNotNullExpression) {
            let w76 = this.checkExpression(s76.operand, t76, null);
            if (w76 instanceof NullableType)
                v76 = w76.base;
            else {
                this.addError('E2041', 'ensure-not-null requires a nullable value', s76.span);
                v76 = w76;
            }
        }
        else if (s76 instanceof CallExpression)
            v76 = this.checkCall(s76, t76, false);
        else if (s76 instanceof AwaitExpression) {
            if (!this.inAsyncFunction)
                this.addError('E2014', 'await is valid only in an async function', s76.span);
            if (!(s76.operand instanceof CallExpression)) {
                this.addError('E2015', 'await requires an async function call', s76.span);
                v76 = VOID;
            }
            else
                v76 = this.checkCall(s76.operand, t76, true);
        }
        else if (s76 instanceof LambdaExpression)
            v76 = this.checkLambda(s76, t76);
        this.model.expressionTypes.set(s76, v76);
        if (u76 !== null && !assignable(v76, u76))
            this.typeError(s76, u76, v76);
        return v76;
    }
    private checkArray(n76: ArrayExpression, o76: Scope, p76: VeraType | null): VeraType {
        let q76 = p76 instanceof NullableType ? p76.base : p76;
        if (!(q76 instanceof VeraArrayType)) {
            this.addError('E2020', 'array literal requires array context', n76.span);
            return new VeraArrayType(VOID);
        }
        for (let r76 of n76.elements)
            this.checkExpression(r76, o76, q76.element);
        return q76;
    }
    private checkObject(e76: ObjectExpression, f76: Scope, g76: VeraType | null): VeraType {
        let h76 = g76 instanceof NullableType ? g76.base : g76;
        if (!(h76 instanceof VeraClassType)) {
            this.addError('E2021', 'object literal requires class context', e76.span);
            return VOID;
        }
        let i76 = new Set<string>();
        for (let l76 of e76.properties) {
            let m76 = h76.fields.get(l76.name);
            if (m76 === undefined)
                this.addError('E2022', 'unknown field ' + l76.name, l76.span);
            else
                this.checkExpression(l76.value, f76, m76);
            if (i76.has(l76.name))
                this.addError('E2023', 'duplicate property ' + l76.name, l76.span);
            i76.add(l76.name);
        }
        let j76 = Array.from(h76.fields.keys());
        for (let k76 of j76) {
            if (!i76.has(k76))
                this.addError('E2024', 'missing field ' + k76, e76.span);
        }
        return h76;
    }
    private checkUnary(b76: UnaryExpression, c76: Scope): VeraType {
        if (b76.operator === '-' && b76.operand instanceof IntExpression && b76.operand.value === 2147483648) {
            this.model.expressionTypes.set(b76.operand, INT);
            return INT;
        }
        let d76 = this.checkExpression(b76.operand, c76, null);
        if (b76.operator === '!') {
            this.requireType(d76, BOOLEAN, b76.operand);
            return BOOLEAN;
        }
        if (!identical(d76, INT) && !identical(d76, NUMBER))
            this.addError('E2025', 'unary minus requires int or number', b76.span);
        return d76;
    }
    private checkBinary(s75: BinaryExpression, t75: Scope): VeraType {
        let u75 = this.checkExpression(s75.left, t75, null);
        let v75 = this.checkExpression(s75.right, t75, null);
        let w75 = s75.operator;
        if (w75 === '===' || w75 === '!==') {
            let y75 = this.isNullableNullPair(u75, v75) || this.isNullableNullPair(v75, u75);
            let z75 = u75 instanceof PrimitiveType && identical(u75, v75) && !identical(u75, VOID);
            let a76 = u75 instanceof VeraFunctionType && v75 instanceof VeraFunctionType && (subtypeOf(u75, v75) || subtypeOf(v75, u75));
            if (!y75 && !z75 && !a76)
                this.addError('E2026', 'unsupported equality operands', s75.span);
            return BOOLEAN;
        }
        if (w75 === '&&' || w75 === '||') {
            this.requireType(u75, BOOLEAN, s75.left);
            this.requireType(v75, BOOLEAN, s75.right);
            return BOOLEAN;
        }
        if (w75 === '<' || w75 === '<=' || w75 === '>' || w75 === '>=') {
            if ((!identical(u75, INT) && !identical(u75, NUMBER) && !identical(u75, STRING)) || !identical(u75, v75)) {
                this.addError('E2027', 'relational operands must be equal int, number, or string types', s75.span);
            }
            return BOOLEAN;
        }
        if (!identical(u75, v75))
            this.addError('E2028', 'arithmetic operands must have identical types', s75.span);
        let x75 = identical(u75, INT) || identical(u75, NUMBER) || (w75 === '+' && identical(u75, STRING));
        if (!x75 || (w75 === '%' && !identical(u75, INT)))
            this.addError('E2029', 'operator ' + w75 + ' is invalid for ' + u75.display(), s75.span);
        return u75;
    }
    private checkSelect(m75: SelectExpression, n75: Scope): VeraType {
        let o75 = this.checkExpression(m75.target, n75, null);
        if (o75 instanceof NamespaceType) {
            let r75 = o75.members.get(m75.field);
            if (r75 === undefined)
                this.addError('E2030', 'namespace has no member ' + m75.field, m75.span);
            return r75 !== undefined ? r75 : VOID;
        }
        if ((o75 instanceof VeraArrayType || identical(o75, STRING)) && m75.field === 'length') {
            return new VeraFunctionType([], INT, false, 'intrinsic:length');
        }
        if (o75 instanceof VeraArrayType) {
            let q75 = (o75 as VeraArrayType).element;
            if (m75.field === 'push') {
                return new VeraFunctionType([q75], INT, false, 'intrinsic:push');
            }
            if (m75.field === 'pop') {
                return new VeraFunctionType([], q75, false, 'intrinsic:pop');
            }
        }
        if (o75 instanceof VeraClassType) {
            let p75 = o75.fields.get(m75.field);
            if (p75 === undefined)
                this.addError('E2031', 'class ' + o75.name + ' has no field ' + m75.field, m75.span);
            return p75 !== undefined ? p75 : VOID;
        }
        if (o75 instanceof NullableType)
            this.addError('E2032', 'nullable value must be narrowed before field access', m75.span);
        else
            this.addError('E2033', 'field selection requires class, array, string, or namespace', m75.span);
        return VOID;
    }
    private checkCall(f75: CallExpression, g75: Scope, h75: boolean): VeraType {
        let i75 = this.checkExpression(f75.callee, g75, null);
        if (!(i75 instanceof VeraFunctionType)) {
            this.addError('E2034', 'callee is not a function', f75.callee.span);
            return VOID;
        }
        if (i75.isAsync !== h75)
            this.addError('E2035', i75.isAsync ? 'async call must be awaited' : 'synchronous call cannot be awaited', f75.span);
        if (f75.argumentsList.length < i75.required ||
            f75.argumentsList.length > i75.parameters.length) {
            let l75 = i75.required === i75.parameters.length
                ? i75.parameters.length.toString()
                : i75.required.toString() + ' to ' + i75.parameters.length.toString();
            this.addError('E2036', 'expected ' + l75 + ' arguments, found ' +
                f75.argumentsList.length, f75.span);
        }
        for (let j75 = 0; j75 < f75.argumentsList.length; j75++) {
            let k75 = j75 < i75.parameters.length ? i75.parameters[j75] : null;
            this.checkExpression(f75.argumentsList[j75], g75, k75);
        }
        this.checkStyleArguments(f75, i75);
        this.checkComposition(f75, i75);
        this.checkSdkArguments(f75, i75);
        return i75.result;
    }
    private checkComposition(s74: CallExpression, t74: VeraFunctionType): void {
        const u74 = 'external:std/ui:';
        if (!t74.identity.startsWith(u74))
            return;
        let v74 = t74.identity.substring(u74.length);
        let w74: ChildRule | null = childRuleFor(v74);
        if (w74 === null)
            return;
        if (w74!.allowed.length > 0) {
            for (let a75 of CATALOG) {
                if (a75.name !== v74)
                    continue;
                for (let b75 = 0; b75 < a75.props.length && b75 < s74.argumentsList.length; b75++) {
                    if (a75.props[b75].kind !== 'view[]')
                        continue;
                    let c75 = s74.argumentsList[b75];
                    if (!(c75 instanceof ArrayExpression))
                        break;
                    for (let d75 of (c75 as ArrayExpression).elements) {
                        let e75 = this.uiComponentName(d75);
                        if (e75.length === 0)
                            continue;
                        if (w74!.allowed.indexOf(e75) < 0) {
                            this.addError('E2107', v74 + ' takes only ' + listWords(w74!.allowed) +
                                ' children, not ' + e75, d75.span);
                        }
                    }
                    break;
                }
                break;
            }
        }
        for (let x74 of w74!.refusedInside) {
            for (let y74 of s74.argumentsList) {
                let z74 = this.findUiDescendant(y74, x74);
                if (z74 !== null) {
                    this.addError('E2107', v74 + ' may not contain another ' + x74, z74!.span);
                    break;
                }
            }
        }
    }
    private uiComponentName(o74: Expression): string {
        if (!(o74 instanceof CallExpression))
            return '';
        let p74 = (o74 as CallExpression).callee;
        if (!(p74 instanceof SelectExpression))
            return '';
        let q74 = (p74 as SelectExpression).field;
        if (q74 === 'When')
            return 'When';
        for (let r74 of CATALOG) {
            if (r74.name === q74)
                return q74;
        }
        return '';
    }
    private findUiDescendant(i74: Expression, j74: string): Expression | null {
        if (i74 instanceof ArrayExpression) {
            for (let m74 of (i74 as ArrayExpression).elements) {
                let n74 = this.findUiDescendant(m74, j74);
                if (n74 !== null)
                    return n74;
            }
            return null;
        }
        if (i74 instanceof CallExpression) {
            if (this.uiComponentName(i74) === j74)
                return i74;
            for (let k74 of (i74 as CallExpression).argumentsList) {
                let l74 = this.findUiDescendant(k74, j74);
                if (l74 !== null)
                    return l74;
            }
        }
        return null;
    }
    private checkStyleArguments(z73: CallExpression, a74: VeraFunctionType): void {
        const b74 = 'external:std/ui:';
        if (!a74.identity.startsWith(b74))
            return;
        let c74 = a74.identity.substring(b74.length);
        for (let d74 of CATALOG) {
            if (d74.name !== c74)
                continue;
            for (let e74 = 0; e74 < d74.props.length && e74 < z73.argumentsList.length; e74++) {
                let f74 = d74.props[e74];
                if (f74.styleSet.length === 0)
                    continue;
                let g74 = z73.argumentsList[e74];
                if (!(g74 instanceof StringExpression))
                    continue;
                let h74 = stylesFor(d74.nodeKind);
                if (h74.length === 0)
                    continue;
                if (h74.indexOf((g74 as StringExpression).value) < 0) {
                    this.addError('E2105', 'unknown ' + d74.name + ' style "' + (g74 as StringExpression).value +
                        '"; allowed: ' + h74.join(' '), g74.span);
                }
            }
            this.checkIconArguments(z73, d74);
            this.checkHandlerSignature(z73, d74);
            return;
        }
    }
    private checkIconArguments(u73: CallExpression, v73: ComponentSpec): void {
        for (let w73 = 0; w73 < v73.props.length && w73 < u73.argumentsList.length; w73++) {
            if (v73.props[w73].kind !== 'icon')
                continue;
            let x73 = u73.argumentsList[w73];
            if (!(x73 instanceof StringExpression))
                continue;
            let y73 = (x73 as StringExpression).value;
            if (y73.length === 0)
                continue;
            if (iconPath(y73).length === 0) {
                this.addError('E2108', 'unknown icon "' + y73 + '"; the icons are: ' +
                    iconNames().join(' '), x73.span);
            }
        }
    }
    private checkSdkArguments(f73: CallExpression, g73: VeraFunctionType): void {
        if (g73.identity !== 'external:std/sdk:call')
            return;
        if (f73.argumentsList.length > 0 && f73.argumentsList[0] instanceof StringExpression) {
            let p73 = f73.argumentsList[0];
            let q73 = (p73 as StringExpression).value;
            if (q73.indexOf('/') >= 0) {
                let r73 = q73.split('/');
                let s73 = false;
                for (let t73 of r73) {
                    if (t73.trim().length === 0) {
                        s73 = true;
                    }
                }
                if ((r73.length !== 4 && r73.length !== 3) || s73) {
                    this.addError('E2109', 'an intent-style sdk.call target must be ' +
                        '"bundle/module/ability/IntentName", or "bundle/module/ability" to just launch it; got "' + q73 + '"', p73.span);
                }
            }
            else if (!isValidSdkTarget(q73)) {
                this.addError('E2110', 'sdk.call target "' + q73 + '" is not one find_sdk_function ' +
                    'returned; call it first and use a target exactly as it came back', p73.span);
            }
        }
        if (f73.argumentsList.length > 1 && f73.argumentsList[1] instanceof ArrayExpression) {
            let m73 = f73.argumentsList[1];
            let n73 = (m73 as ArrayExpression).elements;
            if (n73.length % 2 !== 0) {
                this.addError('E2111', 'sdk.call parameters are name and value in pairs, so the ' +
                    'array must have an even number of items; got ' + n73.length.toString(), m73.span);
            }
            for (let o73 = 0; o73 + 1 < n73.length; o73 = o73 + 2) {
                if (!(n73[o73] instanceof StringExpression)) {
                    continue;
                }
                if ((n73[o73] as StringExpression).value.trim().length === 0) {
                    this.addError('E2111', 'sdk.call parameter names cannot be empty', n73[o73].span);
                }
            }
        }
        if (f73.argumentsList.length > 3 && f73.argumentsList[3] instanceof StringExpression) {
            let k73 = f73.argumentsList[3];
            let l73 = (k73 as StringExpression).value;
            if (l73 !== 'foreground' && l73 !== 'background') {
                this.addError('E2109', 'sdk.call mode must be "foreground" or "background"; got "' + l73 + '"', k73.span);
            }
        }
        if (f73.argumentsList.length < 3 || !(f73.argumentsList[2] instanceof StringExpression))
            return;
        let h73 = f73.argumentsList[2];
        let i73 = (h73 as StringExpression).value;
        let j73 = this.model.functions.get(i73);
        if (j73 === undefined) {
            this.addError('E2106', 'no handler named "' + i73 + '"', h73.span);
            return;
        }
        if (j73.parameters.length < 2 || !identical(j73.parameters[1], STRING)) {
            this.addError('E2106', 'sdk.call answers with a string, so "' + i73 +
                '" must take (state, value: string)', h73.span);
        }
    }
    private checkHandlerSignature(w72: CallExpression, x72: ComponentSpec): void {
        let y72 = payloadKindFor(x72.nodeKind);
        if (y72.length === 0)
            return;
        for (let z72 = 0; z72 < x72.props.length && z72 < w72.argumentsList.length; z72++) {
            if (x72.props[z72].name !== 'action')
                continue;
            let a73 = w72.argumentsList[z72];
            if (!(a73 instanceof StringExpression))
                return;
            let b73 = (a73 as StringExpression).value;
            let c73 = this.model.functions.get(b73);
            if (c73 === undefined) {
                this.addError('E2106', 'no handler named "' + b73 + '"', a73.span);
                return;
            }
            let d73: VeraType = y72 === 'string' ? STRING : y72 === 'boolean' ? BOOLEAN : INT;
            if (c73.parameters.length < 2 || !identical(c73.parameters[1], d73)) {
                let e73 = y72 === 'int' ? 'an ' : 'a ';
                this.addError('E2106', x72.name + ' hands its handler ' + e73 + y72 + ', so "' + b73 + '" must take (state, value: ' + y72 + ')', a73.span);
            }
            return;
        }
    }
    private checkLambda(k72: LambdaExpression, l72: Scope): VeraType {
        let m72: VeraType[] = [];
        for (let v72 of k72.parameters)
            m72.push(this.resolveType(v72.type));
        let n72 = this.resolveType(k72.returnType);
        let o72 = new VeraFunctionType(m72, n72, false, 'lambda:' + this.lambdaCount++);
        let p72 = new Scope(l72);
        for (let t72 = 0; t72 < k72.parameters.length; t72++) {
            let u72 = k72.parameters[t72];
            if (p72.find(u72.name) !== null)
                this.addError('E2004', 'declaration ' + u72.name + ' shadows a visible entity', u72.span);
            else
                p72.values.set(u72.name, m72[t72]);
        }
        let q72 = this.returnType;
        let r72 = this.inAsyncFunction;
        this.returnType = n72;
        this.inAsyncFunction = false;
        let s72 = this.checkBlock(k72.body, p72);
        this.returnType = q72;
        this.inAsyncFunction = r72;
        if (!identical(n72, VOID) && !s72)
            this.addError('E2018', 'lambda may not return a value', k72.body.span);
        return o72;
    }
    private narrow(c72: Expression, d72: Scope): Narrowing {
        let e72 = new Scope(d72);
        let f72 = new Scope(d72);
        if (c72 instanceof BinaryExpression) {
            let g72 = c72.operator;
            if (g72 !== '===' && g72 !== '!==')
                return new Narrowing(e72, f72);
            let h72: NameExpression | null = null;
            if (c72.left instanceof NameExpression && c72.right instanceof NullExpression)
                h72 = c72.left;
            else if (c72.right instanceof NameExpression && c72.left instanceof NullExpression)
                h72 = c72.right;
            if (h72 !== null) {
                let i72 = d72.find(h72.name);
                if (i72 !== null && i72 instanceof NullableType) {
                    let j72 = g72 === '!==' ? e72 : f72;
                    j72.values.set(h72.name, i72.base);
                }
            }
        }
        return new Narrowing(e72, f72);
    }
    resolveType(x71: TypeNode): VeraType {
        let y71 = this.model.declaredTypes.get(x71);
        if (y71 !== undefined)
            return y71;
        let z71: VeraType;
        if (x71.name === 'int')
            z71 = INT;
        else if (x71.name === 'number')
            z71 = NUMBER;
        else if (x71.name === 'boolean')
            z71 = BOOLEAN;
        else if (x71.name === 'string')
            z71 = STRING;
        else if (x71.name === 'void')
            z71 = VOID;
        else if (x71.name === 'array')
            z71 = new VeraArrayType(this.resolveType(x71.parts[0]));
        else if (x71.name === 'function' || x71.name === 'async-function') {
            let a72: VeraType[] = [];
            for (let b72 of x71.parts)
                a72.push(this.resolveType(b72));
            z71 = new VeraFunctionType(a72.slice(0, -1), a72[a72.length - 1], x71.name === 'async-function', 'function-type');
        }
        else
            z71 = this.resolveNamedType(x71.name, x71);
        if (x71.nullable) {
            if (identical(z71, VOID))
                this.addError('E2037', 'void cannot be nullable', x71.span);
            z71 = new NullableType(z71);
        }
        this.model.declaredTypes.set(x71, z71);
        return z71;
    }
    private resolveNamedType(r71: string, s71: TypeNode): VeraType {
        let t71 = r71.split('.');
        let u71: VeraType | null = this.globals.find(t71[0]);
        for (let v71 = 1; v71 < t71.length; v71++) {
            if (u71 instanceof NamespaceType) {
                let w71 = u71.members.get(t71[v71]);
                u71 = w71 !== undefined ? w71 : null;
            }
            else {
                u71 = null;
            }
        }
        if (!(u71 instanceof VeraClassType)) {
            this.addError('E2038', 'unknown class type ' + r71, s71.span);
            return VOID;
        }
        return u71;
    }
    private isNullableNullPair(p71: VeraType, q71: VeraType): boolean {
        return p71 instanceof NullableType && q71 instanceof VeraNullType;
    }
    private requireType(m71: VeraType, n71: VeraType, o71: Expression): void {
        if (!identical(m71, n71))
            this.typeError(o71, n71, m71);
    }
    private typeError(j71: Expression, k71: VeraType, l71: VeraType): void {
        this.diagnostics.push(new Diagnostic('E2019', 'expected ' + k71.display() + ', found ' + l71.display(), j71.span, k71.display(), l71.display()));
    }
    private addError(g71: string, h71: string, i71: Span): void {
        this.diagnostics.push(new Diagnostic(g71, h71, i71));
    }
}
class Binding {
    location: string;
    slot: number;
    constructor(e71: string, f71: number) { this.location = e71; this.slot = f71; }
}
class LoopLabels {
    breaks: number[];
    continues: number[];
    continueTarget: number;
    constructor(b71: number[], c71: number[], d71: number) {
        this.breaks = b71;
        this.continues = c71;
        this.continueTarget = d71;
    }
}
class FunctionBuilder {
    instructions: Instruction[] = [];
    bindings: Map<string, Binding> = new Map<string, Binding>();
    capturedBindings: Map<string, number> = new Map<string, number>();
    loops: LoopLabels[] = [];
    localCount: number = 0;
    name: string;
    parent: FunctionBuilder | null;
    constructor(z70: string, a71: FunctionBuilder | null) {
        this.name = z70;
        this.parent = a71;
    }
    emit(y70: Instruction): number {
        this.instructions.push(y70);
        return this.instructions.length - 1;
    }
    local(w70: string): number {
        let x70 = this.localCount++;
        this.bindings.set(w70, new Binding('local', x70));
        return x70;
    }
}
function mkInst(v70: string): Instruction { return new Instruction(v70); }
function mkPushInt(t70: string): Instruction { let u70 = mkInst('push-int'); u70.value = t70; return u70; }
function mkPushNumber(r70: number): Instruction { let s70 = mkInst('push-number'); s70.numValue = r70; return s70; }
function mkPushString(p70: string): Instruction { let q70 = mkInst('push-string'); q70.value = p70; return q70; }
function mkPushBoolean(n70: boolean): Instruction { let o70 = mkInst('push-boolean'); o70.boolValue = n70; return o70; }
function mkLoadLocal(l70: number): Instruction { let m70 = mkInst('load-local'); m70.slot = l70; return m70; }
function mkStoreLocal(j70: number): Instruction { let k70 = mkInst('store-local'); k70.slot = j70; return k70; }
function mkLoadCapture(h70: number): Instruction { let i70 = mkInst('load-capture'); i70.slot = h70; return i70; }
function mkStoreCapture(f70: number): Instruction { let g70 = mkInst('store-capture'); g70.slot = f70; return g70; }
function mkLoadFunction(d70: string): Instruction { let e70 = mkInst('load-function'); e70.name = d70; return e70; }
function mkLoadExternal(a70: string, b70: string): Instruction { let c70 = mkInst('load-external'); c70.module = a70; c70.name = b70; return c70; }
function mkUnary(y69: string): Instruction { let z69 = mkInst('unary'); z69.operator = y69; return z69; }
function mkBinary(v69: string, w69: boolean): Instruction { let x69 = mkInst('binary'); x69.operator = v69; x69.integer = w69; return x69; }
function mkJump(t69: number): Instruction { let u69 = mkInst('jump'); u69.target = t69; return u69; }
function mkJumpIfFalse(r69: number): Instruction { let s69 = mkInst('jump-if-false'); s69.target = r69; return s69; }
function mkCall(o69: number, p69: boolean): Instruction { let q69 = mkInst('call'); q69.count = o69; q69.awaited = p69; return q69; }
function mkMakeArray(m69: number): Instruction { let n69 = mkInst('make-array'); n69.count = m69; return n69; }
function mkMakeObject(j69: string, k69: string[]): Instruction {
    let l69 = mkInst('make-object');
    l69.classIdentity = j69;
    l69.fields = k69;
    return l69;
}
function mkLoadField(h69: string): Instruction { let i69 = mkInst('load-field'); i69.name = h69; return i69; }
function mkStoreField(f69: string): Instruction { let g69 = mkInst('store-field'); g69.name = f69; return g69; }
function mkMakeClosure(c69: string, d69: number[]): Instruction {
    let e69 = mkInst('make-closure');
    e69.functionName = c69;
    e69.captures = d69;
    return e69;
}
class BytecodeCompiler {
    private functions: BytecodeFunction[] = [];
    private lambdaCount: number = 0;
    private model: SemanticModel;
    constructor(b69: SemanticModel) { this.model = b69; }
    compile(): BytecodeModule {
        for (let a69 of this.model.application.declarations) {
            if (a69 instanceof FunctionDeclaration)
                this.compileFunction(a69);
        }
        let x68: string[] = [];
        let y68 = Array.from(this.model.functions.keys());
        for (let z68 of y68)
            x68.push(z68);
        return new BytecodeModule(this.functions, x68);
    }
    private compileFunction(u68: FunctionDeclaration): void {
        let v68 = new FunctionBuilder(u68.name, null);
        for (let w68 of u68.parameters)
            v68.local(w68.name);
        this.block(u68.body, v68);
        v68.emit(mkInst('push-null'));
        v68.emit(mkInst('return'));
        this.functions.push(new BytecodeFunction(u68.name, u68.parameters.length, v68.localCount, u68.isAsync, v68.instructions));
    }
    private block(r68: BlockStatement, s68: FunctionBuilder): void {
        for (let t68 of r68.statements)
            this.statement(t68, s68);
    }
    private statement(h68: Statement, i68: FunctionBuilder): void {
        if (h68 instanceof BlockStatement)
            this.block(h68, i68);
        else if (h68 instanceof LetStatement) {
            this.expression(h68.initializer, i68);
            i68.emit(mkStoreLocal(i68.local(h68.name)));
        }
        else if (h68 instanceof ExpressionStatement) {
            this.expression(h68.expression, i68);
            i68.emit(mkInst('pop'));
        }
        else if (h68 instanceof AssignStatement)
            this.assignment(h68, i68);
        else if (h68 instanceof ReturnStatement) {
            if (h68.value === null)
                i68.emit(mkInst('push-null'));
            else
                this.expression(h68.value, i68);
            i68.emit(mkInst('return'));
        }
        else if (h68 instanceof IfStatement) {
            this.expression(h68.condition, i68);
            let p68 = i68.emit(mkJumpIfFalse(-1));
            this.block(h68.thenBranch, i68);
            if (h68.elseBranch !== null) {
                let q68 = i68.emit(mkJump(-1));
                this.patch(i68, p68, i68.instructions.length);
                this.statement(h68.elseBranch, i68);
                this.patch(i68, q68, i68.instructions.length);
            }
            else {
                this.patch(i68, p68, i68.instructions.length);
            }
        }
        else if (h68 instanceof WhileStatement) {
            let l68 = i68.instructions.length;
            this.expression(h68.condition, i68);
            let m68 = i68.emit(mkJumpIfFalse(-1));
            let n68 = new LoopLabels([], [], l68);
            i68.loops.push(n68);
            this.block(h68.body, i68);
            i68.emit(mkJump(l68));
            let o68 = i68.instructions.length;
            this.patch(i68, m68, o68);
            this.finishLoop(i68, n68, o68, true);
        }
        else if (h68 instanceof ForOfStatement)
            this.forOf(h68, i68);
        else if (h68 instanceof TryStatement) {
            this.block(h68.tryBlock, i68);
        }
        else if (h68 instanceof BreakStatement) {
            let k68 = i68.loops[i68.loops.length - 1];
            k68.breaks.push(i68.emit(mkJump(-1)));
        }
        else if (h68 instanceof ContinueStatement) {
            let j68 = i68.loops[i68.loops.length - 1];
            j68.continues.push(i68.emit(mkJump(-1)));
        }
    }
    private forOf(w67: ForOfStatement, x67: FunctionBuilder): void {
        let y67 = x67.local('$array' + x67.localCount);
        let z67 = x67.local('$index' + x67.localCount);
        let a68 = x67.local(w67.name);
        this.expression(w67.iterable, x67);
        if (this.model.expressionTypes.get(w67.iterable) === STRING)
            x67.emit(mkInst('string-symbols'));
        x67.emit(mkStoreLocal(y67));
        x67.emit(mkPushInt('0'));
        x67.emit(mkStoreLocal(z67));
        let b68 = x67.instructions.length;
        x67.emit(mkLoadLocal(z67));
        x67.emit(mkLoadLocal(y67));
        x67.emit(mkInst('length'));
        x67.emit(mkBinary('<', true));
        let c68 = x67.emit(mkJumpIfFalse(-1));
        x67.emit(mkLoadLocal(y67));
        x67.emit(mkLoadLocal(z67));
        x67.emit(mkInst('load-index'));
        x67.emit(mkStoreLocal(a68));
        let d68 = new LoopLabels([], [], -1);
        x67.loops.push(d68);
        this.block(w67.body, x67);
        let e68 = x67.instructions.length;
        x67.emit(mkLoadLocal(z67));
        x67.emit(mkPushInt('1'));
        x67.emit(mkBinary('+', true));
        x67.emit(mkStoreLocal(z67));
        x67.emit(mkJump(b68));
        let f68 = x67.instructions.length;
        this.patch(x67, c68, f68);
        let g68 = new LoopLabels(d68.breaks, d68.continues, e68);
        x67.loops.pop();
        this.finishLoop(x67, g68, f68, false);
    }
    private finishLoop(q67: FunctionBuilder, r67: LoopLabels, s67: number, t67: boolean): void {
        if (t67)
            q67.loops.pop();
        for (let v67 of r67.breaks)
            this.patch(q67, v67, s67);
        for (let u67 of r67.continues)
            this.patch(q67, u67, r67.continueTarget);
    }
    private assignment(n67: AssignStatement, o67: FunctionBuilder): void {
        let p67 = n67.target;
        if (p67 instanceof NameExpression) {
            this.expression(n67.value, o67);
            this.storeName(p67.name, o67);
        }
        else if (p67 instanceof IndexExpression) {
            this.expression(p67.target, o67);
            this.expression(p67.index, o67);
            this.expression(n67.value, o67);
            o67.emit(mkInst('store-index'));
        }
        else if (p67 instanceof SelectExpression) {
            this.expression(p67.target, o67);
            this.expression(n67.value, o67);
            o67.emit(mkStoreField(p67.field));
        }
    }
    private expression(d67: Expression, e67: FunctionBuilder): void {
        if (d67 instanceof IntExpression) {
            let m67 = this.model.expressionTypes.get(d67);
            if (m67 !== undefined && identical(m67, NUMBER))
                e67.emit(mkPushNumber(d67.value));
            else
                e67.emit(mkPushInt(d67.value.toString()));
        }
        else if (d67 instanceof NumberExpression)
            e67.emit(mkPushNumber(d67.value));
        else if (d67 instanceof StringExpression)
            e67.emit(mkPushString(d67.value));
        else if (d67 instanceof BooleanExpression)
            e67.emit(mkPushBoolean(d67.value));
        else if (d67 instanceof NullExpression)
            e67.emit(mkInst('push-null'));
        else if (d67 instanceof NameExpression)
            this.loadName(d67.name, e67);
        else if (d67 instanceof UnaryExpression) {
            if (d67.operator === '-' && d67.operand instanceof IntExpression && d67.operand.value === 2147483648) {
                e67.emit(mkPushInt('-2147483648'));
            }
            else {
                this.expression(d67.operand, e67);
                e67.emit(mkUnary(d67.operator));
            }
        }
        else if (d67 instanceof BinaryExpression)
            this.binary(d67, e67);
        else if (d67 instanceof CallExpression) {
            if (d67.callee instanceof SelectExpression && d67.callee.field === 'push' && d67.argumentsList.length === 1 &&
                this.model.expressionTypes.get(d67.callee.target) instanceof VeraArrayType) {
                this.expression(d67.callee.target, e67);
                this.expression(d67.argumentsList[0], e67);
                e67.emit(mkInst('array-push'));
            }
            else if (d67.callee instanceof SelectExpression && d67.callee.field === 'pop' && d67.argumentsList.length === 0 &&
                this.model.expressionTypes.get(d67.callee.target) instanceof VeraArrayType) {
                this.expression(d67.callee.target, e67);
                e67.emit(mkInst('array-pop'));
            }
            else if (d67.callee instanceof SelectExpression && d67.callee.field === 'length' && d67.argumentsList.length === 0) {
                this.expression(d67.callee.target, e67);
                e67.emit(mkInst('length'));
            }
            else {
                this.call(d67, e67, false);
            }
        }
        else if (d67 instanceof AwaitExpression) {
            if (d67.operand instanceof CallExpression)
                this.call(d67.operand, e67, true);
        }
        else if (d67 instanceof ArrayExpression) {
            for (let l67 of d67.elements)
                this.expression(l67, e67);
            e67.emit(mkMakeArray(d67.elements.length));
        }
        else if (d67 instanceof ObjectExpression) {
            for (let k67 of d67.properties)
                this.expression(k67.value, e67);
            let g67 = this.model.expressionTypes.get(d67);
            let h67 = g67 instanceof VeraClassType ? g67.identity : 'invalid';
            let i67: string[] = [];
            for (let j67 of d67.properties)
                i67.push(j67.name);
            e67.emit(mkMakeObject(h67, i67));
        }
        else if (d67 instanceof IndexExpression) {
            this.expression(d67.target, e67);
            this.expression(d67.index, e67);
            e67.emit(mkInst('load-index'));
        }
        else if (d67 instanceof EnsureNotNullExpression) {
            this.expression(d67.operand, e67);
            e67.emit(mkInst('ensure-not-null'));
        }
        else if (d67 instanceof SelectExpression) {
            if (d67.target instanceof NameExpression) {
                let f67 = this.model.imports.get(d67.target.name);
                if (f67 !== undefined) {
                    e67.emit(mkLoadExternal(f67.specifier, d67.field));
                    return;
                }
            }
            this.expression(d67.target, e67);
            e67.emit(mkLoadField(d67.field));
        }
        else if (d67 instanceof LambdaExpression)
            this.lambda(d67, e67);
    }
    private binary(w66: BinaryExpression, x66: FunctionBuilder): void {
        if (w66.operator === '&&') {
            this.expression(w66.left, x66);
            let b67 = x66.emit(mkJumpIfFalse(-1));
            this.expression(w66.right, x66);
            let c67 = x66.emit(mkJump(-1));
            this.patch(x66, b67, x66.instructions.length);
            x66.emit(mkPushBoolean(false));
            this.patch(x66, c67, x66.instructions.length);
            return;
        }
        if (w66.operator === '||') {
            this.expression(w66.left, x66);
            x66.emit(mkUnary('!'));
            let z66 = x66.emit(mkJumpIfFalse(-1));
            this.expression(w66.right, x66);
            let a67 = x66.emit(mkJump(-1));
            this.patch(x66, z66, x66.instructions.length);
            x66.emit(mkPushBoolean(true));
            this.patch(x66, a67, x66.instructions.length);
            return;
        }
        this.expression(w66.left, x66);
        this.expression(w66.right, x66);
        let y66 = this.model.expressionTypes.get(w66.left);
        x66.emit(mkBinary(w66.operator, y66 === INT));
    }
    private call(s66: CallExpression, t66: FunctionBuilder, u66: boolean): void {
        this.expression(s66.callee, t66);
        for (let v66 of s66.argumentsList)
            this.expression(v66, t66);
        t66.emit(mkCall(s66.argumentsList.length, u66));
    }
    private lambda(k66: LambdaExpression, l66: FunctionBuilder): void {
        let m66 = '$lambda' + this.lambdaCount++;
        let n66 = new FunctionBuilder(m66, l66);
        for (let r66 of k66.parameters)
            n66.local(r66.name);
        this.block(k66.body, n66);
        n66.emit(mkInst('push-null'));
        n66.emit(mkInst('return'));
        let o66: number[] = [];
        let p66 = Array.from(n66.capturedBindings.values());
        for (let q66 of p66)
            o66.push(q66);
        this.functions.push(new BytecodeFunction(m66, k66.parameters.length, n66.localCount, false, n66.instructions));
        l66.emit(mkMakeClosure(m66, o66));
    }
    private loadName(b66: string, c66: FunctionBuilder): void {
        let d66 = c66.bindings.get(b66);
        if (d66 !== undefined) {
            if (d66.location === 'local')
                c66.emit(mkLoadLocal(d66.slot));
            else
                c66.emit(mkLoadCapture(d66.slot));
            return;
        }
        if (this.model.functions.has(b66)) {
            c66.emit(mkLoadFunction(b66));
            return;
        }
        let e66 = b66.split('.');
        if (e66.length >= 2) {
            let j66 = this.model.imports.get(e66[0]);
            if (j66 !== undefined) {
                c66.emit(mkLoadExternal(j66.specifier, e66[1]));
                return;
            }
        }
        let f66 = c66.parent;
        if (f66 !== null) {
            let g66 = this.findBinding(b66, f66);
            if (g66 !== null) {
                let h66 = c66.capturedBindings.size;
                let i66 = g66.location === 'local' ? g66.slot : -g66.slot - 1;
                c66.capturedBindings.set(b66, i66);
                c66.bindings.set(b66, new Binding('capture', h66));
                c66.emit(mkLoadCapture(h66));
                return;
            }
        }
        c66.emit(mkLoadFunction(b66));
    }
    private storeName(y65: string, z65: FunctionBuilder): void {
        let a66 = z65.bindings.get(y65);
        if (a66 === undefined)
            throw new Error('compiler invariant');
        if (a66.location === 'local')
            z65.emit(mkStoreLocal(a66.slot));
        else
            z65.emit(mkStoreCapture(a66.slot));
    }
    private findBinding(v65: string, w65: FunctionBuilder): Binding | null {
        let x65 = w65.bindings.get(v65);
        if (x65 !== undefined)
            return x65;
        if (w65.parent !== null)
            return this.findBinding(v65, w65.parent);
        return null;
    }
    private patch(p65: FunctionBuilder, q65: number, r65: number): void {
        let s65 = p65.instructions[q65];
        if (s65.op === 'jump-if-false') {
            let u65 = mkJumpIfFalse(r65);
            p65.instructions[q65] = u65;
        }
        else {
            let t65 = mkJump(r65);
            p65.instructions[q65] = t65;
        }
    }
}
function encodeInstruction(n65: Instruction): Object[] {
    let o65 = n65.op;
    switch (o65) {
        case 'push-int': return [o65, n65.value];
        case 'push-number': return [o65, n65.numValue];
        case 'push-string': return [o65, n65.value];
        case 'push-boolean': return [o65, n65.boolValue];
        case 'push-null': return [o65];
        case 'load-local': return [o65, n65.slot];
        case 'store-local': return [o65, n65.slot];
        case 'load-capture': return [o65, n65.slot];
        case 'store-capture': return [o65, n65.slot];
        case 'load-function': return [o65, n65.name];
        case 'load-external': return [o65, n65.module, n65.name];
        case 'pop': return [o65];
        case 'duplicate': return [o65];
        case 'unary': return [o65, n65.operator];
        case 'binary': return [o65, n65.operator, n65.integer];
        case 'jump': return [o65, n65.target];
        case 'jump-if-false': return [o65, n65.target];
        case 'call': return [o65, n65.count, n65.awaited];
        case 'return': return [o65];
        case 'make-array': return [o65, n65.count];
        case 'array-push': return [o65];
        case 'array-pop': return [o65];
        case 'length': return [o65];
        case 'string-symbols': return [o65];
        case 'ensure-not-null': return [o65];
        case 'load-index': return [o65];
        case 'store-index': return [o65];
        case 'make-object': return [o65, n65.classIdentity, n65.fields];
        case 'load-field': return [o65, n65.name];
        case 'store-field': return [o65, n65.name];
        case 'make-closure': return [o65, n65.functionName, n65.captures];
        default: return [o65];
    }
}
function serializeVbc2(i65: BytecodeModule): string {
    let j65: Object[] = [];
    for (let k65 of i65.functions) {
        let l65: Object[] = [];
        for (let m65 of k65.instructions)
            l65.push(encodeInstruction(m65));
        j65.push([k65.name, k65.parameterCount, k65.localCount, k65.isAsync, l65]);
    }
    return JSON.stringify(['VBC2', i65.entryCandidates, j65]);
}
export class CompileResult {
    vbc2: string;
    constructor(h65: string) { this.vbc2 = h65; }
}
export function compileVeraSource(c65: string, d65: string = '<source>'): CompileResult {
    let e65 = new Parser(c65, d65).parse();
    let f65 = new Analyzer(e65).analyze();
    let g65 = new BytecodeCompiler(f65).compile();
    return new CompileResult(serializeVbc2(g65));
}

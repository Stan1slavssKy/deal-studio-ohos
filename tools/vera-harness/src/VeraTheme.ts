export const PRESET_NAMES: string[] = [
    'clean', 'soft', 'expressive', 'editorial', 'technical', 'playful'
];
export class ResolvedTheme {
    preset: string = 'clean';
    primary: string = '#007DFF';
    onPrimary: string = '#FFFFFF';
    primaryFill: string = '#EBF0FF';
    primaryInk: string = '#007DFF';
    secondaryFill: string = '#E0E0E0';
    secondaryInk: string = '#333333';
    background: string = '#FFFFFF';
    surface: string = '#F3F6FA';
    surfaceRaised: string = '#FFFFFF';
    surfaceDisabled: string = '#F5F5F5';
    ink: string = '#000000';
    inkStrong: string = '#333333';
    inkSoft: string = '#666666';
    inkMuted: string = '#888888';
    inkDisabled: string = '#CCCCCC';
    line: string = '#D8E1ED';
    lineSoft: string = '#E4EAF2';
    lineStrong: string = '#CBD6E4';
    success: string = '#4CAF50';
    successInk: string = '#2E7D32';
    successFill: string = '#E8F8E8';
    warning: string = '#E65100';
    warningInk: string = '#E65100';
    warningFill: string = '#FFF8E0';
    danger: string = '#F44336';
    dangerInk: string = '#C62828';
    dangerFill: string = '#FFECEC';
    pathDefault: string = '#37474F';
    pathMuted: string = '#B0BEC5';
    sizeDisplay: number = 30;
    sizeTitle: number = 24;
    sizeHeading: number = 18;
    sizeBody: number = 15;
    sizeCaption: number = 12;
    sizeMetric: number = 32;
    sizeEyebrow: number = 11;
    weightDisplay: number = 700;
    weightTitle: number = 700;
    weightHeading: number = 500;
    weightBody: number = 400;
    weightMetric: number = 700;
    eyebrowSpacing: number = 1;
    fontFamily: string = '';
    radiusCard: number = 14;
    radiusControl: number = 10;
    radiusSmall: number = 8;
    borderWidth: number = 1;
    padTight: number = 6;
    padBase: number = 10;
    padLoose: number = 16;
    padCard: number = 14;
    padRow: number = 6;
    padGrid: number = 4;
    padListX: number = 14;
    padListY: number = 12;
    gapTight: number = 4;
    gapBase: number = 8;
    gapLoose: number = 12;
    gapSection: number = 14;
    spacerSmall: number = 8;
    spacerBase: number = 18;
    spacerLarge: number = 32;
    controlHeight: number = 44;
    chipHeight: number = 36;
}
export function makeTheme(h165: string): ResolvedTheme {
    let i165 = new ResolvedTheme();
    i165.preset = 'clean';
    if (h165 === 'soft') {
        i165.preset = 'soft';
        i165.primary = '#4C6EF5';
        i165.primaryFill = '#E7EAFD';
        i165.background = '#FBF9F7';
        i165.surface = '#F4F0EC';
        i165.surfaceRaised = '#FFFFFF';
        i165.secondaryFill = '#EAE4DD';
        i165.secondaryInk = '#4A4340';
        i165.ink = '#2C2724';
        i165.inkStrong = '#453E39';
        i165.inkSoft = '#6E645D';
        i165.inkMuted = '#857A70';
        i165.line = '#E6DED6';
        i165.lineSoft = '#EFE9E3';
        i165.lineStrong = '#DDD3C9';
        i165.successFill = '#E4F5E6';
        i165.warningFill = '#FBF0DC';
        i165.dangerFill = '#FBE7E4';
        i165.radiusCard = 20;
        i165.radiusControl = 16;
        i165.radiusSmall = 12;
        i165.padTight = 10;
        i165.padBase = 14;
        i165.padLoose = 20;
        i165.padCard = 18;
        i165.padListX = 16;
        i165.padListY = 14;
        i165.gapBase = 10;
        i165.gapLoose = 16;
        i165.gapSection = 18;
        i165.weightHeading = 600;
    }
    else if (h165 === 'expressive') {
        i165.preset = 'expressive';
        i165.primary = '#6D28D9';
        i165.primaryFill = '#EDE4FD';
        i165.background = '#F6F2FC';
        i165.surface = '#EDE6F8';
        i165.surfaceRaised = '#FFFFFF';
        i165.secondaryFill = '#E2D8F2';
        i165.secondaryInk = '#3B2A5C';
        i165.ink = '#1F1533';
        i165.inkStrong = '#332553';
        i165.inkSoft = '#5C4B7D';
        i165.inkMuted = '#7A6B99';
        i165.line = '#DCCFF2';
        i165.lineSoft = '#E8DEF8';
        i165.lineStrong = '#C9B6E8';
        i165.success = '#059669';
        i165.successInk = '#047857';
        i165.successFill = '#D8F3E8';
        i165.warning = '#D97706';
        i165.warningInk = '#B45309';
        i165.warningFill = '#FBEDD6';
        i165.danger = '#DC2626';
        i165.dangerInk = '#B91C1C';
        i165.dangerFill = '#FBE0E0';
        i165.pathDefault = '#3B2A5C';
        i165.sizeDisplay = 36;
        i165.sizeTitle = 28;
        i165.sizeMetric = 38;
        i165.weightHeading = 700;
        i165.weightBody = 500;
        i165.radiusCard = 18;
        i165.radiusControl = 14;
        i165.padCard = 16;
        i165.gapSection = 18;
    }
    else if (h165 === 'editorial') {
        i165.preset = 'editorial';
        i165.fontFamily = 'serif';
        i165.primary = '#1A1A1A';
        i165.onPrimary = '#FFFFFF';
        i165.primaryFill = '#F0EEE9';
        i165.background = '#FDFCF9';
        i165.surface = '#FDFCF9';
        i165.surfaceRaised = '#FFFFFF';
        i165.secondaryFill = '#EDEAE3';
        i165.secondaryInk = '#1A1A1A';
        i165.ink = '#111111';
        i165.inkStrong = '#1A1A1A';
        i165.inkSoft = '#55524B';
        i165.inkMuted = '#8A857A';
        i165.line = '#DAD5C9';
        i165.lineSoft = '#E7E3D9';
        i165.lineStrong = '#C9C3B4';
        i165.successInk = '#1F6B37';
        i165.successFill = '#EDF4EC';
        i165.warningInk = '#8A4B0B';
        i165.warningFill = '#F7F0E2';
        i165.dangerInk = '#9B2226';
        i165.dangerFill = '#F6E9E7';
        i165.pathDefault = '#1A1A1A';
        i165.sizeDisplay = 38;
        i165.sizeTitle = 30;
        i165.sizeHeading = 20;
        i165.sizeBody = 16;
        i165.sizeMetric = 34;
        i165.weightTitle = 700;
        i165.weightHeading = 600;
        i165.weightMetric = 500;
        i165.eyebrowSpacing = 2;
        i165.radiusCard = 4;
        i165.radiusControl = 4;
        i165.radiusSmall = 2;
        i165.padLoose = 20;
        i165.padCard = 16;
        i165.gapSection = 22;
    }
    else if (h165 === 'technical') {
        i165.preset = 'technical';
        i165.fontFamily = 'monospace';
        i165.primary = '#0F766E';
        i165.primaryFill = '#DCF0EE';
        i165.background = '#FFFFFF';
        i165.surface = '#F4F6F7';
        i165.surfaceRaised = '#FFFFFF';
        i165.secondaryFill = '#E3E8EA';
        i165.secondaryInk = '#1F2A2E';
        i165.ink = '#101820';
        i165.inkStrong = '#26313A';
        i165.inkSoft = '#55636D';
        i165.inkMuted = '#7C8A94';
        i165.line = '#C6D0D6';
        i165.lineSoft = '#D8E0E4';
        i165.lineStrong = '#AEBBC3';
        i165.success = '#0F766E';
        i165.successInk = '#0B5B55';
        i165.successFill = '#DCF0EE';
        i165.warning = '#B45309';
        i165.warningInk = '#92400E';
        i165.warningFill = '#F7EEDF';
        i165.danger = '#B91C1C';
        i165.dangerInk = '#991B1B';
        i165.dangerFill = '#F7E3E3';
        i165.pathDefault = '#26313A';
        i165.sizeDisplay = 24;
        i165.sizeTitle = 20;
        i165.sizeHeading = 16;
        i165.sizeBody = 14;
        i165.sizeCaption = 11;
        i165.sizeMetric = 26;
        i165.sizeEyebrow = 10;
        i165.weightTitle = 600;
        i165.weightHeading = 600;
        i165.weightMetric = 600;
        i165.radiusCard = 6;
        i165.radiusControl = 6;
        i165.radiusSmall = 4;
        i165.padTight = 4;
        i165.padBase = 8;
        i165.padLoose = 12;
        i165.padCard = 10;
        i165.padListX = 10;
        i165.padListY = 8;
        i165.gapTight = 3;
        i165.gapBase = 6;
        i165.gapLoose = 9;
        i165.gapSection = 10;
        i165.spacerBase = 12;
        i165.spacerLarge = 22;
        i165.controlHeight = 40;
        i165.chipHeight = 32;
    }
    else if (h165 === 'playful') {
        i165.preset = 'playful';
        i165.primary = '#F0426B';
        i165.primaryFill = '#FFE3EA';
        i165.background = '#FFFCF5';
        i165.surface = '#FFF1E6';
        i165.surfaceRaised = '#FFFFFF';
        i165.secondaryFill = '#FFE6CC';
        i165.secondaryInk = '#7A3E12';
        i165.ink = '#2B1B22';
        i165.inkStrong = '#432A33';
        i165.inkSoft = '#7A5C66';
        i165.inkMuted = '#8F7681';
        i165.line = '#FBD9C5';
        i165.lineSoft = '#FFE8D9';
        i165.lineStrong = '#F2C3A8';
        i165.success = '#12A150';
        i165.successInk = '#0E7A3D';
        i165.successFill = '#DEF7E7';
        i165.warning = '#F59E0B';
        i165.warningInk = '#B45309';
        i165.warningFill = '#FFF1D6';
        i165.danger = '#F0426B';
        i165.dangerInk = '#C2185B';
        i165.dangerFill = '#FFE3EA';
        i165.pathDefault = '#432A33';
        i165.sizeDisplay = 34;
        i165.sizeTitle = 26;
        i165.sizeMetric = 36;
        i165.weightHeading = 700;
        i165.weightBody = 500;
        i165.radiusCard = 22;
        i165.radiusControl = 22;
        i165.radiusSmall = 14;
        i165.padTight = 8;
        i165.padBase = 12;
        i165.padLoose = 20;
        i165.padCard = 18;
        i165.gapBase = 10;
        i165.gapLoose = 16;
        i165.gapSection = 20;
        i165.spacerBase = 20;
    }
    i165.primaryInk = i165.primary;
    return i165;
}
const HEX_DIGITS: string = '0123456789abcdefABCDEF';
export function isHexColor(f165: string): boolean {
    if (f165.length !== 7 || f165.charAt(0) !== '#') {
        return false;
    }
    for (let g165 = 1; g165 < 7; g165++) {
        if (HEX_DIGITS.indexOf(f165.charAt(g165)) < 0) {
            return false;
        }
    }
    return true;
}
function channel(d165: string, e165: number): number {
    return Number.parseInt(d165.substring(e165, e165 + 2), 16);
}
function twoDigits(a165: number): string {
    let b165 = Math.round(a165);
    if (b165 < 0) {
        b165 = 0;
    }
    if (b165 > 255) {
        b165 = 255;
    }
    let c165 = b165.toString(16).toUpperCase();
    return c165.length < 2 ? '0' + c165 : c165;
}
export function blendHex(x164: string, y164: string, z164: number): string {
    if (!isHexColor(x164) || !isHexColor(y164)) {
        return x164;
    }
    return '#' +
        twoDigits(channel(x164, 1) + (channel(y164, 1) - channel(x164, 1)) * z164) +
        twoDigits(channel(x164, 3) + (channel(y164, 3) - channel(x164, 3)) * z164) +
        twoDigits(channel(x164, 5) + (channel(y164, 5) - channel(x164, 5)) * z164);
}
export function readableInk(v164: string): string {
    if (!isHexColor(v164)) {
        return '#FFFFFF';
    }
    let w164 = (channel(v164, 1) * 299 + channel(v164, 3) * 587 + channel(v164, 5) * 114) / 1000;
    return w164 > 150 ? '#1A1A1A' : '#FFFFFF';
}
function luminance(u164: string): number {
    if (!isHexColor(u164)) {
        return 0;
    }
    return (channel(u164, 1) * 299 + channel(u164, 3) * 587 + channel(u164, 5) * 114) / 1000;
}
function lighten(s164: string, t164: number): string {
    return blendHex(s164, '#FFFFFF', t164);
}
function applyDark(q164: ResolvedTheme, r164: string): void {
    if (r164 === 'soft') {
        q164.background = '#17140F';
        q164.surface = '#211C15';
        q164.surfaceRaised = '#2B241C';
        q164.line = '#3A3229';
        q164.lineSoft = '#2F2822';
        q164.lineStrong = '#4A4034';
        q164.ink = '#F3ECE1';
        q164.inkStrong = '#E3D9CA';
        q164.inkSoft = '#B6A996';
        q164.inkMuted = '#8A7E6D';
    }
    else if (r164 === 'expressive') {
        q164.background = '#140F20';
        q164.surface = '#1D1630';
        q164.surfaceRaised = '#261D3E';
        q164.line = '#382B54';
        q164.lineSoft = '#2B2143';
        q164.lineStrong = '#4A3A6B';
        q164.ink = '#EFE8FA';
        q164.inkStrong = '#DDD3EE';
        q164.inkSoft = '#AFA2C8';
        q164.inkMuted = '#8477A0';
    }
    else if (r164 === 'editorial') {
        q164.background = '#101010';
        q164.surface = '#101010';
        q164.surfaceRaised = '#1A1A1A';
        q164.line = '#2E2E2C';
        q164.lineSoft = '#242422';
        q164.lineStrong = '#3E3E3A';
        q164.ink = '#F3F1EA';
        q164.inkStrong = '#E4E1D8';
        q164.inkSoft = '#ADA99C';
        q164.inkMuted = '#807C70';
    }
    else if (r164 === 'technical') {
        q164.background = '#0B0F11';
        q164.surface = '#131A1D';
        q164.surfaceRaised = '#182126';
        q164.line = '#26323A';
        q164.lineSoft = '#1D272C';
        q164.lineStrong = '#35444E';
        q164.ink = '#E4EDF2';
        q164.inkStrong = '#D0DCE3';
        q164.inkSoft = '#94A5B0';
        q164.inkMuted = '#6E7F8A';
    }
    else if (r164 === 'playful') {
        q164.background = '#1A1114';
        q164.surface = '#241A1E';
        q164.surfaceRaised = '#2F2228';
        q164.line = '#402F37';
        q164.lineSoft = '#32252B';
        q164.lineStrong = '#523B45';
        q164.ink = '#FCEDF1';
        q164.inkStrong = '#F0DCE2';
        q164.inkSoft = '#C0A3AD';
        q164.inkMuted = '#967A84';
    }
    else {
        q164.background = '#0E1116';
        q164.surface = '#161B22';
        q164.surfaceRaised = '#1C242F';
        q164.line = '#2A3440';
        q164.lineSoft = '#212933';
        q164.lineStrong = '#3A4756';
        q164.ink = '#E6EDF3';
        q164.inkStrong = '#D2DBE4';
        q164.inkSoft = '#9FADBC';
        q164.inkMuted = '#78889A';
    }
    q164.surfaceDisabled = q164.lineSoft;
    q164.inkDisabled = q164.inkMuted;
    if (luminance(q164.primary) < 70) {
        q164.primary = lighten(q164.primary, 0.82);
    }
    q164.primaryInk = luminance(q164.primary) < 150 ? lighten(q164.primary, 0.45) : q164.primary;
    q164.success = lighten(q164.success, 0.26);
    q164.warning = lighten(q164.warning, 0.30);
    q164.danger = lighten(q164.danger, 0.26);
    q164.successInk = q164.success;
    q164.warningInk = q164.warning;
    q164.dangerInk = q164.danger;
    q164.onPrimary = readableInk(q164.primary);
    q164.primaryFill = blendHex(q164.primaryInk, q164.surface, 0.84);
    q164.successFill = blendHex(q164.success, q164.surface, 0.84);
    q164.warningFill = blendHex(q164.warning, q164.surface, 0.84);
    q164.dangerFill = blendHex(q164.danger, q164.surface, 0.84);
    q164.secondaryFill = q164.surfaceRaised;
    q164.secondaryInk = q164.ink;
    q164.pathDefault = q164.inkStrong;
    q164.pathMuted = q164.inkMuted;
}
export function resolveTheme(m164: string, n164: string, o164: boolean): ResolvedTheme {
    let p164 = makeTheme(m164);
    if (isHexColor(n164)) {
        p164.primary = n164;
        p164.primaryInk = n164;
        p164.onPrimary = readableInk(n164);
        p164.primaryFill = blendHex(n164, p164.background, 0.88);
    }
    if (o164) {
        applyDark(p164, p164.preset);
    }
    return p164;
}
export function containerFill(k164: ResolvedTheme, l164: string): string {
    if (l164 === 'surface') {
        return k164.surface;
    }
    if (l164 === 'accent') {
        return k164.primaryFill;
    }
    return '#00000000';
}
export function toneFill(h164: ResolvedTheme, i164: string, j164: string): string {
    if (i164 === 'accent') {
        return h164.primaryFill;
    }
    if (i164 === 'success') {
        return h164.successFill;
    }
    if (i164 === 'warning') {
        return h164.warningFill;
    }
    if (i164 === 'danger') {
        return h164.dangerFill;
    }
    return j164;
}
export function toneEdge(e164: ResolvedTheme, f164: string, g164: string): string {
    if (f164 === 'accent') {
        return e164.primaryInk;
    }
    if (f164 === 'success') {
        return e164.success;
    }
    if (f164 === 'warning') {
        return e164.warning;
    }
    if (f164 === 'danger') {
        return e164.danger;
    }
    return g164;
}
export function toneInk(b164: ResolvedTheme, c164: string, d164: string): string {
    if (c164 === 'accent') {
        return b164.primaryInk;
    }
    if (c164 === 'success') {
        return b164.successInk;
    }
    if (c164 === 'warning') {
        return b164.warningInk;
    }
    if (c164 === 'danger') {
        return b164.dangerInk;
    }
    if (c164 === 'muted') {
        return b164.inkMuted;
    }
    return d164;
}
export function textSize(z163: ResolvedTheme, a164: string): number {
    if (a164 === 'display') {
        return z163.sizeDisplay;
    }
    if (a164 === 'title') {
        return z163.sizeTitle;
    }
    if (a164 === 'heading') {
        return z163.sizeHeading;
    }
    if (a164 === 'metric') {
        return z163.sizeMetric;
    }
    if (a164 === 'caption') {
        return z163.sizeCaption;
    }
    if (a164 === 'eyebrow') {
        return z163.sizeEyebrow;
    }
    return z163.sizeBody;
}
export function textWeight(x163: ResolvedTheme, y163: string): number {
    if (y163 === 'display') {
        return x163.weightDisplay;
    }
    if (y163 === 'title') {
        return x163.weightTitle;
    }
    if (y163 === 'heading') {
        return x163.weightHeading;
    }
    if (y163 === 'metric') {
        return x163.weightMetric;
    }
    if (y163 === 'eyebrow') {
        return x163.weightHeading;
    }
    return x163.weightBody;
}
export function textInk(v163: ResolvedTheme, w163: string): string {
    if (w163 === 'eyebrow') {
        return v163.inkMuted;
    }
    return toneInk(v163, w163, v163.ink);
}
export function buttonFill(t163: ResolvedTheme, u163: string): string {
    if (u163 === 'success') {
        return t163.success;
    }
    if (u163 === 'danger') {
        return t163.danger;
    }
    if (u163 === 'secondary') {
        return t163.secondaryFill;
    }
    return t163.primary;
}
export function buttonInk(r163: ResolvedTheme, s163: string): string {
    if (s163 === 'secondary') {
        return r163.secondaryInk;
    }
    if (s163 === 'success') {
        return readableInk(r163.success);
    }
    if (s163 === 'danger') {
        return readableInk(r163.danger);
    }
    return r163.onPrimary;
}
export function pathFill(p163: ResolvedTheme, q163: string): string {
    if (q163 === 'accent') {
        return p163.primary;
    }
    if (q163 === 'success') {
        return p163.success;
    }
    if (q163 === 'warning') {
        return p163.warning;
    }
    if (q163 === 'danger') {
        return p163.danger;
    }
    if (q163 === 'muted') {
        return p163.pathMuted;
    }
    if (q163 === 'light') {
        return '#FFFFFF';
    }
    return p163.pathDefault;
}
export function densityPad(n163: ResolvedTheme, o163: string): number {
    if (o163 === 'compact') {
        return n163.padTight;
    }
    if (o163 === 'spacious') {
        return n163.padLoose;
    }
    return n163.padBase;
}
export function densityGap(l163: ResolvedTheme, m163: string): number {
    if (m163 === 'compact') {
        return l163.gapTight;
    }
    if (m163 === 'spacious') {
        return l163.gapLoose;
    }
    if (m163 === 'joined') {
        return 0;
    }
    return l163.gapBase;
}
export function spacerSize(j163: ResolvedTheme, k163: string): number {
    if (k163 === 'none') {
        return 0;
    }
    if (k163 === 'small') {
        return j163.spacerSmall;
    }
    if (k163 === 'large') {
        return j163.spacerLarge;
    }
    return j163.spacerBase;
}

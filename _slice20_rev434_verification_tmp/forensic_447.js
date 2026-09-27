const fs = require('fs');
const crypto = require('crypto');

const rev446Path = 'D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.46_CLEAN_LITERAL_SECURITY_PLAN.md';

if (!fs.existsSync(rev446Path)) {
  console.log('TARGET FILE NOT FOUND');
  process.exit(1);
}

const statsBefore = fs.statSync(rev446Path);
const bufBefore = fs.readFileSync(rev446Path);
const sha256Before = crypto.createHash('sha256').update(bufBefore).digest('hex').toUpperCase();

const content = bufBefore.toString('utf8');
const lines = content.split('\n');

// Unicode byte representation helper
function toUnicodeRep(str) {
  return str.split('').map(ch => {
    const code = ch.charCodeAt(0);
    const hex = code.toString(16).toUpperCase().padStart(4, '0');
    switch (ch) {
      case '\\': return 'U+005C BACKSLASH [ \\ ]';
      case '|': return 'U+007C VERTICAL LINE [ | ]';
      case '_': return 'U+005F LOW LINE [ _ ]';
      case '`': return 'U+0060 GRAVE ACCENT [ ` ]';
      case '<': return 'U+003C LESS-THAN SIGN [ < ]';
      case '>': return 'U+003E GREATER-THAN SIGN [ > ]';
      case '#': return 'U+0023 NUMBER SIGN [ # ]';
      case '-': return 'U+002D HYPHEN-MINUS [ - ]';
      case '\r': return 'U+000D CARRIAGE RETURN [ \\r ]';
      case '\n': return 'U+000A LINE FEED [ \\n ]';
      case ' ': return 'U+0020 SPACE [   ]';
      case '\t': return 'U+0009 CHARACTER TABULATION [ \\t ]';
      default:
        if (code < 32 || code > 126) return `U+${hex} (non-ascii)`;
        return ch;
    }
  }).join(' ');
}

// Section Extractor
function getSection(startHeader, endHeader) {
  const startIdx = content.indexOf(startHeader);
  if (startIdx === -1) return null;
  const endIdx = endHeader ? content.indexOf(endHeader, startIdx) : content.length;
  const actualEndIdx = (endIdx === -1) ? content.length : endIdx;

  const sectionText = content.substring(startIdx, actualEndIdx);
  const sectionBytes = Buffer.byteLength(sectionText, 'utf8');

  const startLine = content.substring(0, startIdx).split('\n').length;
  const endLine = startLine + sectionText.split('\n').length - 1;

  return {
    startLine,
    endLine,
    startIdx,
    endIdx: actualEndIdx,
    bytes: sectionBytes,
    text: sectionText
  };
}

const sec6 = getSection('## 6. PIN CSPRNG PROOF', '## 7. TOKEN CONTRACT');
const sec7 = getSection('## 7. TOKEN CONTRACT', '## 8. NOC STATE MODEL');
const sec9 = getSection('## 9. LOCKING AND SERIALIZATION', '## 10. WRITER INVENTORY');
const sec24 = getSection('## 24. ASSERTION REGISTER', '## 25. GATE REGISTER');

// Code Fence Extractor within section
function extractCodeBlock(secText) {
  if (!secText) return '';
  const firstFence = secText.indexOf('```');
  if (firstFence === -1) return '';
  const secondFence = secText.indexOf('```', firstFence + 3);
  if (secondFence === -1) return '';
  const closingEnd = secText.indexOf('\n', secondFence);
  return secText.substring(firstFence, closingEnd === -1 ? secText.length : closingEnd);
}

// Global Renderer Scan
const rendererTokens = ['svgsvg', '<svg', '</svg>', 'foreignObject', '<foreignObject', 'rendered', 'renderer', 'xmlns='];
const globalRendererMatches = [];
lines.forEach((l, i) => {
  const lineNum = i + 1;
  const trimmed = l.trim();
  if (trimmed === 'svg' || trimmed === 'text' || trimmed === 'wait' || trimmed === 'svgsvg') {
    globalRendererMatches.push({ line: lineNum, text: l, reason: 'Standalone renderer token line' });
  }
  rendererTokens.forEach(tok => {
    if (l.includes(tok)) {
      globalRendererMatches.push({ line: lineNum, text: l, reason: `Contains forbidden token '${tok}'` });
    }
  });
});

// Global Escape Scan
const escapeTargets = ['\\_', '\\|', '\\-', '\\#', '\\*', '\\`', '\\(', '\\)', '\\[', '\\]', '\\{', '\\}', '\\;', '\\```sql', '\\```text', '\\--'];
const globalEscapeMatches = [];

lines.forEach((l, i) => {
  const lineNum = i + 1;
  escapeTargets.forEach(esc => {
    if (l.includes(esc)) {
      globalEscapeMatches.push({ line: lineNum, esc, text: l });
    }
  });
});

// Code Fence Scan
const fences = [];
lines.forEach((l, i) => {
  if (l.trim().startsWith('```')) {
    fences.push({ line: i + 1, text: l.trim() });
  }
});

// Mathematical notation scan
const mathTargets = ['2^32', '4,294,967,296', '4,294,000,000', '967,296', '99.97747%', '0.02253%', '4,294 × 1,000,000', '10^6', '1,000,000', '2^48', '281,474,976,710,656', '248', '232', '106'];
const mathMatches = [];
lines.forEach((l, i) => {
  mathTargets.forEach(m => {
    if (l.includes(m)) {
      mathMatches.push({ line: i + 1, target: m, text: l });
    }
  });
});

// Immutability Check
const bufAfter = fs.readFileSync(rev446Path);
const sha256After = crypto.createHash('sha256').update(bufAfter).digest('hex').toUpperCase();

console.log(JSON.stringify({
  targetFile: rev446Path,
  mtime: statsBefore.mtime,
  sha256Before,
  sha256After,
  bytes: bufBefore.length,
  lines: lines.length,
  hasBOM: bufBefore[0] === 0xEF && bufBefore[1] === 0xBB && bufBefore[2] === 0xBF,
  sec6,
  sec7,
  sec9,
  sec24,
  sec6Code: extractCodeBlock(sec6 ? sec6.text : ''),
  sec7Code: extractCodeBlock(sec7 ? sec7.text : ''),
  sec9Code: extractCodeBlock(sec9 ? sec9.text : ''),
  globalRendererMatches,
  globalEscapeMatches,
  fences,
  mathMatches
}, null, 2));

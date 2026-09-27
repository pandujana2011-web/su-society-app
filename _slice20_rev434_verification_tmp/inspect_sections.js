const fs = require('fs');

const rev446Path = 'D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.46_CLEAN_LITERAL_SECURITY_PLAN.md';
const content = fs.readFileSync(rev446Path, 'utf8');

function charRep(str) {
  return str.split('').map(c => {
    const code = c.charCodeAt(0);
    const hex = code.toString(16).toUpperCase().padStart(4, '0');
    if (c === '\\') return 'U+005C (BACKSLASH)';
    if (c === '|') return 'U+007C (PIPE)';
    if (c === '_') return 'U+005F (UNDERSCORE)';
    if (c === '`') return 'U+0060 (BACKTICK)';
    if (c === '<') return 'U+003C (LESS_THAN)';
    if (c === '>') return 'U+003E (GREATER_THAN)';
    if (c === '#') return 'U+0023 (HASH)';
    if (c === '-') return 'U+002D (HYPHEN)';
    if (c === '\r') return 'U+000D (CR)';
    if (c === '\n') return 'U+000A (LF)';
    if (c === ' ') return 'U+0020 (SPACE)';
    if (c === '\t') return 'U+0009 (TAB)';
    return c;
  }).join(' ');
}

function dumpSec(title, startText, endText) {
  const start = content.indexOf(startText);
  if (start === -1) return console.log('START NOT FOUND:', startText);
  const end = endText ? content.indexOf(endText, start) : content.length;
  const rawText = content.substring(start, end === -1 ? content.length : end);
  const startLine = content.substring(0, start).split('\n').length;
  const endLine = startLine + rawText.split('\n').length - 1;
  const byteCount = Buffer.byteLength(rawText, 'utf8');

  console.log(`=== ${title} ===`);
  console.log(`Lines: ${startLine} - ${endLine}`);
  console.log(`Byte Count: ${byteCount}`);
  console.log('--- EXACT RAW TEXT ---');
  console.log(rawText);
  console.log('--- BYTE/UNICODE REPRESENTATION ---');
  console.log(charRep(rawText));
  console.log('\n');
}

dumpSec('SECTION 6', '## 6. PIN CSPRNG PROOF', '## 7. TOKEN CONTRACT');
dumpSec('SECTION 7', '## 7. TOKEN CONTRACT', '## 8. NOC STATE MODEL');
dumpSec('SECTION 9', '## 9. LOCKING AND SERIALIZATION', '## 10. WRITER INVENTORY');

// Section 24 Header & Separator
const s24Start = content.indexOf('## 24. ASSERTION REGISTER');
const s24Sec = content.substring(s24Start, content.indexOf('## 25. GATE REGISTER'));
const s24Lines = s24Sec.split('\n');
const headerIdx = s24Lines.findIndex(l => l.includes('Assertion ID'));
const headerLine = s24Lines[headerIdx];
const sepLine = s24Lines[headerIdx + 1];

console.log('=== SECTION 24 HEADER & SEPARATOR ===');
console.log('Header Line:', headerLine);
console.log('Header Unicode:', charRep(headerLine));
console.log('Header Pipe Count:', (headerLine.match(/\|/g) || []).length);
console.log('Separator Line:', sepLine);
console.log('Separator Unicode:', charRep(sepLine));
console.log('Separator Pipe Count:', (sepLine.match(/\|/g) || []).length);

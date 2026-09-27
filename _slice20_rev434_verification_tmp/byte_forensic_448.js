const fs = require('fs');
const crypto = require('crypto');

const targetPath = 'D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.46_CLEAN_LITERAL_SECURITY_PLAN.md';

if (!fs.existsSync(targetPath)) {
  console.log(JSON.stringify({ error: 'FILE_NOT_FOUND' }));
  process.exit(1);
}

const statsBefore = fs.statSync(targetPath);
const bufBefore = fs.readFileSync(targetPath);
const sha256Before = crypto.createHash('sha256').update(bufBefore).digest('hex').toUpperCase();

// Helper to find all occurrences of a Buffer or String in buf
function findAll(buf, needle) {
  const needleBuf = Buffer.isBuffer(needle) ? needle : Buffer.from(needle);
  const matches = [];
  let pos = 0;
  while ((pos = buf.indexOf(needleBuf, pos)) !== -1) {
    // Derive line number
    let line = 1;
    for (let i = 0; i < pos; i++) {
      if (buf[i] === 0x0A) line++;
    }
    matches.push({
      offsetDec: pos,
      offsetHex: '0x' + pos.toString(16).toUpperCase(),
      length: needleBuf.length,
      hexStr: needleBuf.toString('hex').toUpperCase(),
      line
    });
    pos += 1; // move 1 byte forward
  }
  return matches;
}

// Byte window helper (32 bytes before, match, 32 bytes after)
function getHexWindow(buf, offsetDec, length) {
  const start = Math.max(0, offsetDec - 32);
  const end = Math.min(buf.length, offsetDec + length + 32);
  const beforeHex = buf.slice(start, offsetDec).toString('hex').toUpperCase();
  const matchHex = buf.slice(offsetDec, offsetDec + length).toString('hex').toUpperCase();
  const afterHex = buf.slice(offsetDec + length, end).toString('hex').toUpperCase();

  return {
    offsetDec,
    offsetHex: '0x' + offsetDec.toString(16).toUpperCase(),
    beforeHex,
    matchHex,
    afterHex
  };
}

// 1. CRLF / LF stats
let crlfCount = 0;
let lfCount = 0;
for (let i = 0; i < bufBefore.length; i++) {
  if (bufBefore[i] === 0x0D && i + 1 < bufBefore.length && bufBefore[i + 1] === 0x0A) {
    crlfCount++;
  } else if (bufBefore[i] === 0x0A && (i === 0 || bufBefore[i - 1] !== 0x0D)) {
    lfCount++;
  }
}

// 2. Renderer scan
const rendererPatterns = [
  { name: 'svgsvg', pattern: 'svgsvg' },
  { name: 'text', pattern: 'text' },
  { name: 'svg', pattern: 'svg' },
  { name: '<svg', pattern: '<svg' },
  { name: '</svg>', pattern: '</svg>' },
  { name: 'foreignObject', pattern: 'foreignObject' },
  { name: 'xmlns=', pattern: 'xmlns=' },
  { name: 'wait', pattern: 'wait' }
];

const rendererResults = {};
rendererPatterns.forEach(p => {
  rendererResults[p.name] = findAll(bufBefore, p.pattern);
});

// 3. Escape scan
const escapePatterns = [
  { name: '\\_', pattern: Buffer.from([0x5C, 0x5F]) },
  { name: '\\|', pattern: Buffer.from([0x5C, 0x7C]) },
  { name: '\\-', pattern: Buffer.from([0x5C, 0x2D]) },
  { name: '\\#', pattern: Buffer.from([0x5C, 0x23]) },
  { name: '\\*', pattern: Buffer.from([0x5C, 0x2A]) },
  { name: '\\`', pattern: Buffer.from([0x5C, 0x60]) },
  { name: '\\(', pattern: Buffer.from([0x5C, 0x28]) },
  { name: '\\)', pattern: Buffer.from([0x5C, 0x29]) },
  { name: '\\[', pattern: Buffer.from([0x5C, 0x5B]) },
  { name: '\\]', pattern: Buffer.from([0x5C, 0x5D]) },
  { name: '\\{', pattern: Buffer.from([0x5C, 0x7B]) },
  { name: '\\}', pattern: Buffer.from([0x5C, 0x7D]) },
  { name: '\\;', pattern: Buffer.from([0x5C, 0x3B]) }
];

const escapeResults = {};
escapePatterns.forEach(p => {
  escapeResults[p.name] = findAll(bufBefore, p.pattern);
});

// 4. Code Fence Scan
const codeFenceResults = {
  sqlFence: findAll(bufBefore, '```sql'),
  textFence: findAll(bufBefore, '```text'),
  closingFence: findAll(bufBefore, '```')
};

// Helper for Section Byte Anchors
const sec6HeaderPos = bufBefore.indexOf(Buffer.from('## 6. PIN CSPRNG PROOF'));
const sec7HeaderPos = bufBefore.indexOf(Buffer.from('## 7. TOKEN CONTRACT'));
const sec8HeaderPos = bufBefore.indexOf(Buffer.from('## 8. NOC STATE MODEL'));
const sec9HeaderPos = bufBefore.indexOf(Buffer.from('## 9. LOCKING AND SERIALIZATION'));
const sec10HeaderPos = bufBefore.indexOf(Buffer.from('## 10. WRITER INVENTORY'));
const sec24HeaderPos = bufBefore.indexOf(Buffer.from('## 24. ASSERTION REGISTER'));
const sec25HeaderPos = bufBefore.indexOf(Buffer.from('## 25. GATE REGISTER'));

function sliceBuf(start, end) {
  return bufBefore.slice(start, end);
}

// Section 6 Analysis
const sec6Buf = sliceBuf(sec6HeaderPos, sec7HeaderPos);
const sec6Analysis = {
  headerOffsetDec: sec6HeaderPos,
  headerOffsetHex: '0x' + sec6HeaderPos.toString(16).toUpperCase(),
  nextHeaderOffsetDec: sec7HeaderPos,
  nextHeaderOffsetHex: '0x' + sec7HeaderPos.toString(16).toUpperCase(),
  v_bytes: findAll(sec6Buf, 'v_bytes').map(m => ({ ...m, offsetDec: sec6HeaderPos + m.offsetDec, offsetHex: '0x' + (sec6HeaderPos + m.offsetDec).toString(16).toUpperCase() })),
  escaped_v_bytes: findAll(sec6Buf, Buffer.from([0x76, 0x5C, 0x5F, 0x62, 0x79, 0x74, 0x65, 0x73])),
  v_random_bigint: findAll(sec6Buf, 'v_random_bigint').map(m => ({ ...m, offsetDec: sec6HeaderPos + m.offsetDec, offsetHex: '0x' + (sec6HeaderPos + m.offsetDec).toString(16).toUpperCase() })),
  escaped_v_random_bigint: findAll(sec6Buf, Buffer.from('v\\_random\\_bigint')),
  pipe: findAll(sec6Buf, '|').map(m => ({ ...m, offsetDec: sec6HeaderPos + m.offsetDec, offsetHex: '0x' + (sec6HeaderPos + m.offsetDec).toString(16).toUpperCase() })),
  escaped_pipe: findAll(sec6Buf, Buffer.from([0x5C, 0x7C])),
  proposed_comment: findAll(sec6Buf, '-- Proposed').map(m => ({ ...m, offsetDec: sec6HeaderPos + m.offsetDec, offsetHex: '0x' + (sec6HeaderPos + m.offsetDec).toString(16).toUpperCase() })),
  escaped_proposed_comment: findAll(sec6Buf, Buffer.from('\\-- Proposed'))
};

// Section 7 Analysis
const sec7Buf = sliceBuf(sec7HeaderPos, sec8HeaderPos);
const sec7Analysis = {
  headerOffsetDec: sec7HeaderPos,
  headerOffsetHex: '0x' + sec7HeaderPos.toString(16).toUpperCase(),
  v_token_bytes: findAll(sec7Buf, 'v_token_bytes').map(m => ({ ...m, offsetDec: sec7HeaderPos + m.offsetDec, offsetHex: '0x' + (sec7HeaderPos + m.offsetDec).toString(16).toUpperCase() })),
  escaped_v_token_bytes: findAll(sec7Buf, Buffer.from('v\\_token\\_bytes')),
  v_raw_token: findAll(sec7Buf, 'v_raw_token').map(m => ({ ...m, offsetDec: sec7HeaderPos + m.offsetDec, offsetHex: '0x' + (sec7HeaderPos + m.offsetDec).toString(16).toUpperCase() })),
  escaped_v_raw_token: findAll(sec7Buf, Buffer.from('v\\_raw\\_token')),
  v_token_hash: findAll(sec7Buf, 'v_token_hash').map(m => ({ ...m, offsetDec: sec7HeaderPos + m.offsetDec, offsetHex: '0x' + (sec7HeaderPos + m.offsetDec).toString(16).toUpperCase() })),
  escaped_v_token_hash: findAll(sec7Buf, Buffer.from('v\\_token\\_hash'))
};

// Section 9 Analysis
const sec9Buf = sliceBuf(sec9HeaderPos, sec10HeaderPos);
const sec9Analysis = {
  headerOffsetDec: sec9HeaderPos,
  headerOffsetHex: '0x' + sec9HeaderPos.toString(16).toUpperCase(),
  v_property_id: findAll(sec9Buf, 'v_property_id').map(m => ({ ...m, offsetDec: sec9HeaderPos + m.offsetDec, offsetHex: '0x' + (sec9HeaderPos + m.offsetDec).toString(16).toUpperCase() })),
  escaped_v_property_id: findAll(sec9Buf, Buffer.from('v\\_property\\_id'))
};

// Section 24 Table Header Analysis
const sec24Buf = sliceBuf(sec24HeaderPos, sec25HeaderPos);
const expectedHeaderStr = '| Assertion ID | Security Property | Expected PASS Condition | Verification Method | Dependency | Evidence Class | Status |';
const expectedHeaderMatches = findAll(bufBefore, expectedHeaderStr);
const escapedHeaderMatches = findAll(bufBefore, Buffer.from([0x5C, 0x7C, 0x20, 0x41, 0x73, 0x73, 0x65, 0x72, 0x74, 0x69, 0x6F, 0x6E, 0x20, 0x49, 0x44]));

// Find line 278 (header line) exact offset
const headerLineOffset = expectedHeaderMatches[0] ? expectedHeaderMatches[0].offsetDec : -1;
let headerLinePipeCount = 0;
let headerLineEscapedPipeCount = 0;
if (headerLineOffset !== -1) {
  const headerBuf = bufBefore.slice(headerLineOffset, headerLineOffset + expectedHeaderStr.length);
  for (let i = 0; i < headerBuf.length; i++) {
    if (headerBuf[i] === 0x7C) headerLinePipeCount++;
    if (headerBuf[i] === 0x5C && i + 1 < headerBuf.length && headerBuf[i + 1] === 0x7C) headerLineEscapedPipeCount++;
  }
}

// Math Analysis
const mathTargets = [
  '2^32', '4,294,967,296', '4,294,000,000', '967,296', '99.97747%', '0.02253%',
  '4,294 × 1,000,000', '10^6', '1,000,000', '2^48', '281,474,976,710,656', '10^-6',
  '248', '232', '106'
];
const mathResults = {};
mathTargets.forEach(m => {
  mathResults[m] = findAll(bufBefore, m);
});

// Token Byte Analysis
const tokenTargets = {
  gen_random_bytes6: findAll(bufBefore, 'gen_random_bytes(6)'),
  prefix_noc_pass: findAll(bufBefore, 'NOC-PASS-'),
  upper_encode: findAll(bufBefore, "upper(encode(v_token_bytes, 'hex'))"),
  encode_digest: findAll(bufBefore, "encode(digest(v_raw_token, 'sha256'), 'hex')")
};

// PIN Byte Analysis
const pinTargets = {
  gen_random_bytes4: findAll(bufBefore, 'gen_random_bytes(4)'),
  t_4294000000: findAll(bufBefore, '4294000000'),
  t_1000000: findAll(bufBefore, '1000000'),
  t_2_32: findAll(bufBefore, '2^32')
};

// Provenance Byte Analysis
const provTargets = {
  rev445: findAll(bufBefore, 'Revision 4.45'),
  rev446: findAll(bufBefore, 'Revision 4.46'),
  superseded: findAll(bufBefore, 'SUPERSEDED BY REVISION 4.46'),
  current: findAll(bufBefore, 'CURRENT DOCUMENT'),
  rev439: findAll(bufBefore, 'REV 4.39'),
  rev440: findAll(bufBefore, 'REV 4.40')
};

// Authorization Byte Analysis
const authTargets = {
  impl_none: findAll(bufBefore, 'IMPLEMENTATION AUTHORIZATION: NONE'),
  s20_impl_none: findAll(bufBefore, 'SLICE 20 IMPLEMENTATION AUTHORIZATION: NONE'),
  not_ready: findAll(bufBefore, 'NOT IMPLEMENTATION-READY'),
  locked_baseline: findAll(bufBefore, '639 / 639 PASS'),
  assertions: findAll(bufBefore, '71/71'),
  gates: findAll(bufBefore, '15/15')
};

// Immutability Check
const bufAfter = fs.readFileSync(targetPath);
const sha256After = crypto.createHash('sha256').update(bufAfter).digest('hex').toUpperCase();

console.log(JSON.stringify({
  targetPath,
  sha256Before,
  sha256After,
  bytes: bufBefore.length,
  lines: findAll(bufBefore, '\n').length + 1,
  mtime: statsBefore.mtime,
  crlfCount,
  lfCount,
  rendererResults,
  escapeResults,
  codeFenceResults,
  sec6Analysis,
  sec7Analysis,
  sec9Analysis,
  expectedHeaderMatches,
  escapedHeaderMatches,
  headerLinePipeCount,
  headerLineEscapedPipeCount,
  mathResults,
  tokenTargets,
  pinTargets,
  provTargets,
  authTargets
}, null, 2));

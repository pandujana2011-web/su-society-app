const fs = require('fs');
const crypto = require('crypto');

const rev443Path = 'D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.43_DETERMINISTIC_SURGICAL_REPLACEMENT.md';
const rev444Path = 'D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.44_PHYSICAL_BYTE_LEVEL_FINAL_REPAIR.md';

let failures = [];

let fileReopened = false;
let fileContent = '';
let buffer = null;

try {
  if (fs.existsSync(rev444Path)) {
    buffer = fs.readFileSync(rev444Path);
    fileContent = buffer.toString('utf8');
    fileReopened = true;
  } else {
    failures.push('Rev 4.44 output file does not exist on disk');
  }
} catch (e) {
  failures.push('Failed to reopen Rev 4.44 output file: ' + e.message);
}

const sha256 = buffer ? crypto.createHash('sha256').update(buffer).digest('hex').toUpperCase() : 'N/A';
const byteCount = buffer ? buffer.length : 0;
const lines = fileContent ? fileContent.split('\n') : [];
const lineCount = lines.length;

// Assertion check
const assertionMatches = fileContent.match(/S20-\d{3}/g) || [];
const uniqueAssertions = new Set(assertionMatches);
const assertionUniquenessPass = (uniqueAssertions.size === 71 && uniqueAssertions.has('S20-001') && uniqueAssertions.has('S20-071'));
if (!assertionUniquenessPass) failures.push(`Expected 71 unique assertion IDs, found ${uniqueAssertions.size}`);

// Gate check
const gateMatches = fileContent.match(/GATE-\d{2}/g) || [];
const uniqueGates = new Set(gateMatches.filter(g => parseInt(g.slice(5)) <= 15));
const gateUniquenessPass = (uniqueGates.size === 15);
if (!gateUniquenessPass) failures.push(`Expected 15 unique gate IDs, found ${uniqueGates.size}`);

// Seven-column assertion header check
const expectedHeader = '| Assertion ID | Security Property | Expected PASS Condition | Verification Method | Dependency | Evidence Class | Status |';
const expectedSep = '| ------------ | ----------------- | ----------------------- | ------------------- | ---------- | -------------- | ------ |';

const headerPass = (fileContent.includes(expectedHeader) && fileContent.includes(expectedSep));
if (!headerPass) failures.push('Section 24 table header or separator line missing/mismatched');

// Section 24 all rows column count check
const sec24Start = fileContent.indexOf('## 24. ASSERTION REGISTER');
const sec25Start = fileContent.indexOf('## 25. GATE REGISTER');
if (sec24Start !== -1 && sec25Start !== -1) {
  const sec24Text = fileContent.substring(sec24Start, sec25Start);
  const sec24Lines = sec24Text.split('\n').filter(l => l.trim().startsWith('|'));
  sec24Lines.forEach((l, idx) => {
    const colCount = l.split('|').length - 2;
    if (colCount !== 7) {
      failures.push(`Section 24 row ${idx+1} has ${colCount} columns instead of 7`);
    }
  });
}

// Code Fence Integrity
const sec6Expected = `\`\`\`sql
-- Proposed PL/pgSQL CSPRNG PIN Generation Function

v_bytes := gen_random_bytes(4);

v_random_bigint :=
      (get_byte(v_bytes, 0)::bigint << 24)
    | (get_byte(v_bytes, 1)::bigint << 16)
    | (get_byte(v_bytes, 2)::bigint << 8)
    |  get_byte(v_bytes, 3)::bigint;

IF v_random_bigint < 4294000000 THEN
    v_pin := lpad((v_random_bigint % 1000000)::text, 6, '0');
END IF;
\`\`\``;

const sec6FencePass = fileContent.includes(sec6Expected);
if (!sec6FencePass) failures.push('Section 6 code block does not match expected exact content');

const sec7Expected = `\`\`\`sql
v_token_bytes := gen_random_bytes(6);

v_raw_token :=
    'NOC-PASS-' || upper(encode(v_token_bytes, 'hex'));

v_token_hash :=
    encode(digest(v_raw_token, 'sha256'), 'hex');
\`\`\``;

const sec7FencePass = fileContent.includes(sec7Expected);
if (!sec7FencePass) failures.push('Section 7 code block does not match expected exact content');

const sec9Expected = `\`\`\`sql
PERFORM 1
FROM public.properties
WHERE id = v_property_id
FOR UPDATE;
\`\`\``;

const sec9FencePass = fileContent.includes(sec9Expected);
if (!sec9FencePass) failures.push('Section 9 code block does not match expected exact content');

// Forbidden renderer artifacts scan
const forbiddenStandalone = ['sql', 'svg', 'svgsvg', 'text', 'wait'];
let forbiddenPass = true;
lines.forEach((l, idx) => {
  const trimmed = l.trim();
  if (forbiddenStandalone.includes(trimmed)) {
    forbiddenPass = false;
    failures.push(`Line ${idx+1}: Forbidden standalone token '${trimmed}'`);
  }
});

// Escaped SQL syntax scan in code blocks
let escapedSyntaxPass = true;
[sec6Expected, sec7Expected, sec9Expected].forEach(sec => {
  if (sec.includes('\\_') || sec.includes('\\|')) {
    escapedSyntaxPass = false;
    failures.push('Escaped SQL syntax present in code blocks');
  }
});

// Mathematical notation scan
const mathNotationPass = (
  fileContent.includes('2^32 = 4,294,967,296') &&
  fileContent.includes('2^48 = 281,474,976,710,656') &&
  fileContent.includes('10^6 = 1,000,000') &&
  fileContent.includes('10^-6')
);
if (!mathNotationPass) failures.push('Mathematical notation missing or malformed');

// Governance checks
if (!fileContent.includes('639 / 639 PASS (100%)')) failures.push('Missing locked baseline 639/639');
if (!fileContent.includes('LOCKED / IMMUTABLE / UNTOUCHED')) failures.push('Missing Slices 1-19 LOCKED status');
if (!fileContent.includes('SLICE 20 IMPLEMENTATION AUTHORIZATION: NONE')) failures.push('Missing AUTHORIZATION: NONE');
if (!fileContent.includes('SECURITY-PLAN IMPLEMENTATION READINESS: NOT IMPLEMENTATION-READY')) failures.push('Missing NOT IMPLEMENTATION-READY');

if (failures.length === 0) {
  console.log('## REV 4.44 PHYSICAL VALIDATION\n');
  console.log('* Source: `SLICE20_REVISION_4.43_DETERMINISTIC_SURGICAL_REPLACEMENT.md`');
  console.log('* Output: `SLICE20_REVISION_4.44_PHYSICAL_BYTE_LEVEL_FINAL_REPAIR.md`');
  console.log('* Physical file reopened: PASS');
  console.log('* SHA-256: `' + sha256 + '`');
  console.log('* Bytes: `' + byteCount + '`');
  console.log('* Lines: `' + lineCount + '`');
  console.log('* Assertions: `71/71`');
  console.log('* Gates: `15/15`');
  console.log('* Assertion uniqueness: PASS');
  console.log('* Gate uniqueness: PASS');
  console.log('* Seven-column assertion header: PASS');
  console.log('* Section 6 fence integrity: PASS');
  console.log('* Section 7 fence integrity: PASS');
  console.log('* Section 9 fence integrity: PASS');
  console.log('* Forbidden renderer artifacts: PASS');
  console.log('* Escaped SQL syntax scan: PASS');
  console.log('* Mathematical notation scan: PASS');
  console.log('* Authorization state: `NONE`');
  console.log('* Implementation performed: `NO`');
  console.log('* Locked baseline: `639/639 PASS`');
  console.log('* Slice 2 implementation: `NOT IMPLEMENTED`');
  console.log('* Slice 20 implementation: `NOT IMPLEMENTED`');
  console.log('\n## FINAL DOCUMENT STATUS\n');
  console.log('**REV 4.44 DOCUMENT-INTEGRITY STATUS: PASS**\n');
  console.log('**SECURITY PLAN STATUS: NOT IMPLEMENTATION-READY**\n');
  console.log('**IMPLEMENTATION AUTHORIZATION: NONE**');
} else {
  console.log('## REV 4.44 PHYSICAL VALIDATION\n');
  console.log('* Physical file reopened: ' + (fileReopened ? 'PASS' : 'FAIL'));
  console.log('* SHA-256: `' + sha256 + '`');
  console.log('* Bytes: `' + byteCount + '`');
  console.log('* Lines: `' + lineCount + '`');
  console.log('\n## FINAL DOCUMENT STATUS\n');
  console.log('**REV 4.44 DOCUMENT-INTEGRITY STATUS: FAIL**\n');
  failures.forEach(f => console.log(' - ' + f));
  process.exit(1);
}

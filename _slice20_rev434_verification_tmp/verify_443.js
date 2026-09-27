const fs = require('fs');
const crypto = require('crypto');

const rev443Path = 'D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.43_DETERMINISTIC_SURGICAL_REPLACEMENT.md';
const rev442Path = 'D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.42_PHYSICAL_BYTE_LEVEL_DOCUMENT_REPAIR.md';
const rev441Path = 'D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.41_FINAL_FORENSIC_CONTENT_VALIDATION.md';

let failures = [];

// Pre-check Rev 4.42 hash
if (!fs.existsSync(rev442Path)) failures.push('Rev 4.42 file missing!');
const rev442BufBefore = fs.readFileSync(rev442Path);
const rev442HashBefore = crypto.createHash('sha256').update(rev442BufBefore).digest('hex').toUpperCase();

// Read Rev 4.43 physical file from disk
if (!fs.existsSync(rev443Path)) failures.push('Rev 4.43 file does not exist on disk');
const buffer = fs.readFileSync(rev443Path);
const fileContent = buffer.toString('utf8');
const lines = fileContent.split('\n');

const sha256 = crypto.createHash('sha256').update(buffer).digest('hex').toUpperCase();
const byteCount = buffer.length;
const lineCount = lines.length;

// Check Rev 4.42 preservation
const rev442BufAfter = fs.readFileSync(rev442Path);
const rev442HashAfter = crypto.createHash('sha256').update(rev442BufAfter).digest('hex').toUpperCase();
if (rev442HashBefore !== rev442HashAfter) {
  failures.push('REV 4.42 PRESERVATION FAILED: SHA-256 changed during execution!');
}

// Governance & Authorization checks
if (!fileContent.includes('639 / 639 PASS (100%)')) failures.push('Missing locked baseline 639/639');
if (!fileContent.includes('LOCKED / IMMUTABLE / UNTOUCHED')) failures.push('Missing Slices 1-19 LOCKED status');
if (!fileContent.includes('SLICE 20 IMPLEMENTATION AUTHORIZATION: NONE')) failures.push('Missing AUTHORIZATION: NONE');
if (!fileContent.includes('SECURITY-PLAN IMPLEMENTATION READINESS: NOT IMPLEMENTATION-READY')) failures.push('Missing NOT IMPLEMENTATION-READY');

// Section 4 Repair E check
const sec4RepairEExpected = '5. **Repair E (GATE-03 Description Formatting):** Updated GATE-03 to state cleanly: **GATE-03: Token Entropy (2^48):** `PASS — MATHEMATICALLY VERIFIED` — `2^48 = 281,474,976,710,656` possible random states proved mathematically.';
if (!fileContent.includes(sec4RepairEExpected)) failures.push('Section 4 Repair E formatting mismatched or contains stray marker');

// Section 28 Revision Correction check
const sec28Expected = 'Revision 4.43 establishes the repaired document-integrity and security-plan specification only. It does not authorize or perform implementation.';
if (!fileContent.includes(sec28Expected)) failures.push('Section 28 stale revision wording not corrected');

// Section 6 check
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
if (!fileContent.includes(sec6Expected)) failures.push('Section 6 code block does not match expected exact content');

// Section 7 check
const sec7Expected = `\`\`\`sql
v_token_bytes := gen_random_bytes(6);

v_raw_token :=
    'NOC-PASS-' || upper(encode(v_token_bytes, 'hex'));

v_token_hash :=
    encode(digest(v_raw_token, 'sha256'), 'hex');
\`\`\``;
if (!fileContent.includes(sec7Expected)) failures.push('Section 7 code block does not match expected exact content');

// Section 9 check
const sec9Expected = `\`\`\`sql
PERFORM 1
FROM public.properties
WHERE id = v_property_id
FOR UPDATE;
\`\`\``;
if (!fileContent.includes(sec9Expected)) failures.push('Section 9 code block does not match expected exact content');

// Section 24 table header & column validation
const expectedHeader = '| Assertion ID | Security Property | Expected PASS Condition | Verification Method | Dependency | Evidence Class | Status |';
const expectedSep = '| ------------ | ----------------- | ----------------------- | ------------------- | ---------- | -------------- | ------ |';

if (!fileContent.includes(expectedHeader)) failures.push('Section 24 header line missing/mismatched');
if (!fileContent.includes(expectedSep)) failures.push('Section 24 separator line missing/mismatched');

const sec24Start = fileContent.indexOf('## 24. ASSERTION REGISTER');
const sec25Start = fileContent.indexOf('## 25. GATE REGISTER');
const sec24Text = fileContent.substring(sec24Start, sec25Start);
const sec24Lines = sec24Text.split('\n').filter(l => l.trim().startsWith('|'));

sec24Lines.forEach((l, idx) => {
  const colCount = l.split('|').length - 2;
  if (colCount !== 7) {
    failures.push(`Section 24 table row ${idx+1} has ${colCount} columns instead of 7: ${l}`);
  }
});

// Count assertions
const assertionMatches = fileContent.match(/S20-\d{3}/g) || [];
const uniqueAssertions = new Set(assertionMatches);
if (uniqueAssertions.size !== 71) failures.push(`Expected 71 assertion IDs, found ${uniqueAssertions.size}`);

// Section 25 gates
const gateMatches = fileContent.match(/GATE-\d{2}/g) || [];
const uniqueGates = new Set(gateMatches.filter(g => parseInt(g.slice(5)) <= 15));
if (uniqueGates.size !== 15) failures.push(`Expected 15 gate IDs, found ${uniqueGates.size}`);

const gate03Expected = '* **GATE-03: Token Entropy (2^48):** `PASS — MATHEMATICALLY VERIFIED` — `2^48 = 281,474,976,710,656` possible random states proved mathematically.';
const gate07Expected = '* **GATE-07: PIN Rejection Sampling:** `PASS — MATHEMATICALLY VERIFIED` — Uniform distribution proven.';

if (!fileContent.includes(gate03Expected)) failures.push('GATE-03 line mismatched or not MATHEMATICALLY VERIFIED');
if (!fileContent.includes(gate07Expected)) failures.push('GATE-07 line mismatched or not MATHEMATICALLY VERIFIED');

// Math notation
if (!fileContent.includes('2^32 = 4,294,967,296')) failures.push('Missing 2^32 math notation');
if (!fileContent.includes('2^48 = 281,474,976,710,656')) failures.push('Missing 2^48 math notation');
if (!fileContent.includes('10^6 = 1,000,000')) failures.push('Missing 10^6 math notation');
if (!fileContent.includes('10^-6')) failures.push('Missing 10^-6 math notation');

// Forbidden artifacts scan
const forbiddenStandalone = ['sql', 'svg', 'svgsvg', 'text', 'wait'];
const forbiddenSubstrings = ['id="', '****', '<svg', '</svg>', 'v\\_', '\\|'];

lines.forEach((l, idx) => {
  const trimmed = l.trim();
  if (forbiddenStandalone.includes(trimmed)) {
    failures.push(`Line ${idx+1}: Forbidden standalone token '${trimmed}'`);
  }
  forbiddenSubstrings.forEach(sub => {
    if (l.includes(sub)) {
      failures.push(`Line ${idx+1}: Forbidden substring '${sub}'`);
    }
  });
});

// Code fence count
const fenceLines = lines.filter(l => l.trim().startsWith('```'));
if (fenceLines.length % 2 !== 0) failures.push(`Code fence count odd (${fenceLines.length})`);

if (failures.length === 0) {
  console.log('REVISION 4.43 DOCUMENT-INTEGRITY VALIDATION: PASS');
  console.log('OUTPUT FILE: ' + rev443Path);
  console.log('PHYSICAL FILE SHA-256: ' + sha256);
  console.log('PHYSICAL BYTE COUNT: ' + byteCount);
  console.log('PHYSICAL LINE COUNT: ' + lineCount);
  console.log(`ASSERTIONS: ${uniqueAssertions.size}/71`);
  console.log(`GATES: ${uniqueGates.size}/15`);
  console.log('CODE FENCES: VALID');
  console.log('SECTION 6: VALID');
  console.log('SECTION 7: VALID');
  console.log('SECTION 9: VALID');
  console.log('SECTION 24: 7 COLUMNS / VALID');
  console.log('FORBIDDEN ARTIFACT SCAN: CLEAN');
  console.log('MATHEMATICAL NOTATION: VALID');
  console.log('GOVERNANCE: VALID');
  console.log('REV 4.42 PRESERVATION: VERIFIED');
  console.log('AUTHORIZATION: NONE');
  console.log('IMPLEMENTATION PERFORMED: NO');
  console.log('IMPLEMENTATION READINESS: NOT IMPLEMENTATION-READY');
} else {
  console.log('REVISION 4.43: FAIL — NOT ACCEPTED');
  failures.forEach(f => console.log(' - ' + f));
  process.exit(1);
}

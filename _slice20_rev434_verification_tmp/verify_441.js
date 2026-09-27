const fs = require('fs');
const path = require('path');

const rev441Path = 'D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.41_FINAL_FORENSIC_CONTENT_VALIDATION.md';
const rev440Path = 'D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.40_HARD_LITERAL_FINAL_SECURITY_PLAN.md';

const fileContent = fs.readFileSync(rev441Path, 'utf8');
const lines = fileContent.split('\n');

let failures = [];

// 1. Verify files exist
if (!fs.existsSync(rev441Path)) failures.push('Rev 4.41 file does not exist');
if (!fs.existsSync(rev440Path)) failures.push('Rev 4.40 file missing!');

// 2. Governance checks
if (!fileContent.includes('639 / 639 PASS (100%)')) failures.push('Missing locked baseline 639/639');
if (!fileContent.includes('LOCKED / IMMUTABLE / UNTOUCHED')) failures.push('Missing Slices 1-19 LOCKED status');
if (!fileContent.includes('SLICE 20 IMPLEMENTATION AUTHORIZATION: NONE')) failures.push('Missing AUTHORIZATION: NONE');
if (!fileContent.includes('SECURITY-PLAN IMPLEMENTATION READINESS: NOT IMPLEMENTATION-READY')) failures.push('Missing NOT IMPLEMENTATION-READY');

// 3. Section 6 check
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

// 4. Section 7 check
const sec7Expected = `\`\`\`sql
v_token_bytes := gen_random_bytes(6);

v_raw_token :=
    'NOC-PASS-' || upper(encode(v_token_bytes, 'hex'));

v_token_hash :=
    encode(digest(v_raw_token, 'sha256'), 'hex');
\`\`\``;
if (!fileContent.includes(sec7Expected)) failures.push('Section 7 code block does not match expected exact content');

// 5. Section 9 check
const sec9Expected = `\`\`\`sql
PERFORM 1
FROM public.properties
WHERE id = v_property_id
FOR UPDATE;
\`\`\``;
if (!fileContent.includes(sec9Expected)) failures.push('Section 9 code block does not match expected exact content');

// 6. Section 24 table header & columns
const expectedHeader = '| Assertion ID | Security Property | Expected PASS Condition | Verification Method | Dependency | Evidence Class | Status |';
const expectedSep = '| ------------ | ----------------- | ----------------------- | ------------------- | ---------- | -------------- | ------ |';

if (!fileContent.includes(expectedHeader)) failures.push('Section 24 header line missing/mismatched');
if (!fileContent.includes(expectedSep)) failures.push('Section 24 separator line missing/mismatched');

// Verify 7 columns on all table rows in Section 24
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
if (!uniqueAssertions.has('S20-001')) failures.push('S20-001 missing');
if (!uniqueAssertions.has('S20-071')) failures.push('S20-071 missing');

// 7. Section 25 gates
const gateMatches = fileContent.match(/GATE-\d{2}/g) || [];
const uniqueGates = new Set(gateMatches.filter(g => parseInt(g.slice(5)) <= 15));
if (uniqueGates.size !== 15) failures.push(`Expected 15 gate IDs, found ${uniqueGates.size}`);

const gate03Expected = '* **GATE-03: Token Entropy (2^48):** `PASS — MATHEMATICALLY VERIFIED` — `2^48 = 281,474,976,710,656` possible random states proved mathematically.';
const gate07Expected = '* **GATE-07: PIN Rejection Sampling:** `PASS — MATHEMATICALLY VERIFIED` — Uniform distribution proven.';

if (!fileContent.includes(gate03Expected)) failures.push('GATE-03 line mismatched or not MATHEMATICALLY VERIFIED');
if (!fileContent.includes(gate07Expected)) failures.push('GATE-07 line mismatched or not MATHEMATICALLY VERIFIED');

// 8. Math notation
if (!fileContent.includes('2^32 = 4,294,967,296')) failures.push('Missing 2^32 math notation');
if (!fileContent.includes('2^48 = 281,474,976,710,656')) failures.push('Missing 2^48 math notation');
if (!fileContent.includes('10^6 = 1,000,000')) failures.push('Missing 10^6 math notation');
if (!fileContent.includes('10^-6')) failures.push('Missing 10^-6 math notation');

// 9. Forbidden artifacts scan
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

// 10. Code fence count
const fenceLines = lines.filter(l => l.trim().startsWith('```'));
if (fenceLines.length % 2 !== 0) failures.push(`Code fence count odd (${fenceLines.length})`);

if (failures.length === 0) {
  console.log('REVISION 4.41 PHYSICAL FILE VERIFICATION SUCCESSFUL: ALL CHECKS PASSED CLEAN');
  console.log(`Assertions: ${uniqueAssertions.size}/71`);
  console.log(`Gates: ${uniqueGates.size}/15`);
  console.log(`Code Fences: ${fenceLines.length} (${fenceLines.length/2} pairs)`);
} else {
  console.log('VERIFICATION FAILURES (' + failures.length + '):');
  failures.forEach(f => console.log(' - ' + f));
  process.exit(1);
}

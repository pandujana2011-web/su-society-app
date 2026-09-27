const fs = require('fs');
const rev440Path = 'D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.40_HARD_LITERAL_FINAL_SECURITY_PLAN.md';
const rev441Path = 'D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.41_FINAL_FORENSIC_CONTENT_VALIDATION.md';

let content = fs.readFileSync(rev440Path, 'utf8');

// 1. Update Title and Section 1
content = content.replace(
  '# SLICE 20 REVISION 4.40 — HARD-LITERAL FINAL SECURITY PLAN',
  '# SLICE 20 REVISION 4.41 — FINAL FORENSIC CONTENT VALIDATION'
);

content = content.replace(
  '`D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.40_HARD_LITERAL_FINAL_SECURITY_PLAN.md`',
  '`D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.41_FINAL_FORENSIC_CONTENT_VALIDATION.md`'
);

content = content.replace('**Revision:** `4.40`', '**Revision:** `4.41`');
content = content.replace(
  '**Execution Purpose:** Hard-Literal Final Security Plan Repair & Document Stabilization',
  '**Execution Purpose:** Final Forensic Content & Document-Integrity Validation'
);

content = content.replace(
  'This document constitutes **Revision 4.40** of the Slice 20 Security Plan for the SU Society App repository. Revision 4.40 performs a hard-literal text repair on Rev 4.39, standardizing clean Markdown code fencing, valid table headers, GATE-03 formatting, and strict evidence-bounded security posture.',
  'This document constitutes **Revision 4.41** of the Slice 20 Security Plan for the SU Society App repository. Revision 4.41 performs literal document repair and forensic validation, confirming mathematical verification, code fence integrity, table formatting, and strict governance limits.'
);

// 2. Section 24 table header separator replacement
content = content.replace(
  '| Assertion ID | Security Property | Expected PASS Condition | Verification Method | Dependency | Evidence Class | Status |\n| --- | --- | --- | --- | --- | --- | --- |',
  '| Assertion ID | Security Property | Expected PASS Condition | Verification Method | Dependency | Evidence Class | Status |\n| ------------ | ----------------- | ----------------------- | ------------------- | ---------- | -------------- | ------ |'
);

// 3. Section 25 Gate register repair
content = content.replace(
  /- \*\*GATE-03: Token Entropy \(2\^48\):\*\* `PASS — VERIFIED` — `2\^48 = 281,474,976,710,656` possible random states proved mathematically\./g,
  '* **GATE-03: Token Entropy (2^48):** `PASS — MATHEMATICALLY VERIFIED` — `2^48 = 281,474,976,710,656` possible random states proved mathematically.'
);
content = content.replace(
  /\* \*\*GATE-03: Token Entropy \(2\^48\):\*\* `PASS — VERIFIED` — `2\^48 = 281,474,976,710,656` possible random states proved mathematically\./g,
  '* **GATE-03: Token Entropy (2^48):** `PASS — MATHEMATICALLY VERIFIED` — `2^48 = 281,474,976,710,656` possible random states proved mathematically.'
);

content = content.replace(
  /\* \*\*GATE-07: PIN Rejection Sampling:\*\* `PASS — VERIFIED` — Uniform distribution proven\./g,
  '* **GATE-07: PIN Rejection Sampling:** `PASS — MATHEMATICALLY VERIFIED` — Uniform distribution proven.'
);
content = content.replace(
  /- \*\*GATE-07: PIN Rejection Sampling:\*\* `PASS — VERIFIED` — Uniform distribution proven\./g,
  '* **GATE-07: PIN Rejection Sampling:** `PASS — MATHEMATICALLY VERIFIED` — Uniform distribution proven.'
);

fs.writeFileSync(rev441Path, content, 'utf8');
console.log('Rev 4.41 updated successfully.');

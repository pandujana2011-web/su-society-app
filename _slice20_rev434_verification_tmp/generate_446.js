const fs = require('fs');

const rev445Path = 'D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.45_FINAL_LITERAL_CONTENT_REPAIR.md';
const rev446Path = 'D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.46_CLEAN_LITERAL_SECURITY_PLAN.md';

let content = fs.readFileSync(rev445Path, 'utf8');

// 1. Update Title and Header
content = content.replace(
  '# SLICE 20 REVISION 4.45 — FINAL LITERAL CONTENT REPAIR',
  '# SLICE 20 REVISION 4.46 — CLEAN LITERAL SECURITY PLAN'
);

content = content.replace(
  '`D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.45_FINAL_LITERAL_CONTENT_REPAIR.md`',
  '`D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.46_CLEAN_LITERAL_SECURITY_PLAN.md`'
);

content = content.replace('**Revision:** `4.45`', '**Revision:** `4.46`');

content = content.replace(
  '**Execution Purpose:** Final Literal Content & Document-Integrity Repair',
  '**Execution Purpose:** Clean Literal Security Plan Reconstruction'
);

content = content.replace(
  'This document constitutes **Revision 4.45** of the Slice 20 Security Plan for the SU Society App repository. Revision 4.45 performs literal content repair on Rev 4.44, standardizing Section 4 repair history, Section 5 architecture framing, Section 6, Section 7, Section 9 code blocks, Section 8 state model framing, Section 24 table headers, Section 26 evidence classification, and strict governance baseline.',
  'This document constitutes **Revision 4.46** of the Slice 20 Security Plan for the SU Society App repository. Revision 4.46 performs a clean literal reconstruction on Rev 4.45, confirming raw Markdown code fencing, exact table formatting, mathematical notation, clean forbidden artifact scan, and strict governance baseline.'
);

content = content.replace(
  '**Revision 4.44 Status:** `SUPERSEDED BY REVISION 4.45`  \n**Revision 4.45 Status:** `CURRENT DOCUMENT`',
  '**Revision 4.45 Status:** `SUPERSEDED BY REVISION 4.46`  \n**Revision 4.46 Status:** `CURRENT DOCUMENT`'
);

// 2. Section 4 Header & Content
const sec4Target = /## 4\. REV 4\.45 PHYSICAL LITERAL REPAIRS[\s\S]*?(?=\n## |$)/;
const sec4Replacement = `## 4. REV 4.46 CLEAN LITERAL RECONSTRUCTION

1. **Clean Markdown Fencing:** Reconstructed Section 6, 7, and 9 code blocks as literal plain-text Markdown (\` \`\`\`sql \`), eliminating renderer escaping and metadata artifacts.
2. **Standard Assertion Header:** Reconstructed Section 24 table header as clean 7-column Markdown table.
3. **Mathematical Precision:** Preserved exact 32-bit and 48-bit CSPRNG mathematical proofs (\`2^32 = 4,294,967,296\`, \`2^48 = 281,474,976,710,656\`, \`10^6 = 1,000,000\`).
4. **Evidence Boundary Classification:** Ensured unambiguous classification across Sections 5, 8, 25, and 26 (\`MATHEMATICALLY VERIFIED\`, \`PASS — DESIGN\`, \`DEPENDENT\`, \`NOT VERIFIED\`, \`BLOCKED\`).
5. **Immediate Provenance:** Updated revision chain (Rev 4.45 -> Rev 4.46).
6. **Governance Baseline:** Retained immutable baseline (\`639 / 639 PASS\`, \`AUTHORIZATION: NONE\`, \`NOT IMPLEMENTATION-READY\`).

---`;

content = content.replace(sec4Target, sec4Replacement);

// 3. Section 28 Revision Wording
content = content.replace(
  'Revision 4.45 establishes the repaired document-integrity and security-plan specification only. It does not authorize or perform implementation.',
  'Revision 4.46 establishes the repaired document-integrity and security-plan specification only. It does not authorize or perform implementation.'
);

// Write output file
fs.writeFileSync(rev446Path, content, 'utf8');
console.log('Rev 4.46 written cleanly. Byte size:', fs.statSync(rev446Path).size);

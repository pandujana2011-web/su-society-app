const fs = require('fs');

const rev444Path = 'D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.44_PHYSICAL_BYTE_LEVEL_FINAL_REPAIR.md';
const rev445Path = 'D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.45_FINAL_LITERAL_CONTENT_REPAIR.md';

let content = fs.readFileSync(rev444Path, 'utf8');

// 1. Update Title and Header
content = content.replace(
  '# SLICE 20 REVISION 4.44 — PHYSICAL BYTE-LEVEL FINAL REPAIR',
  '# SLICE 20 REVISION 4.45 — FINAL LITERAL CONTENT REPAIR'
);

content = content.replace(
  '`D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.44_PHYSICAL_BYTE_LEVEL_FINAL_REPAIR.md`',
  '`D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.45_FINAL_LITERAL_CONTENT_REPAIR.md`'
);

content = content.replace('**Revision:** `4.44`', '**Revision:** `4.45`');

content = content.replace(
  '**Execution Purpose:** Physical Byte-Level Final Security Plan Repair',
  '**Execution Purpose:** Final Literal Content & Document-Integrity Repair'
);

content = content.replace(
  'This document constitutes **Revision 4.44** of the Slice 20 Security Plan for the SU Society App repository. Revision 4.44 performs physical byte-level document repair on Rev 4.43, confirming code fence validity, exact table structure, mathematical verification, clean forbidden artifact scan, and strict governance baseline.',
  'This document constitutes **Revision 4.45** of the Slice 20 Security Plan for the SU Society App repository. Revision 4.45 performs literal content repair on Rev 4.44, standardizing Section 4 repair history, Section 5 architecture framing, Section 6, Section 7, Section 9 code blocks, Section 8 state model framing, Section 24 table headers, Section 26 evidence classification, and strict governance baseline.'
);

content = content.replace(
  '**Revision 4.43 Status:** `SUPERSEDED BY REVISION 4.44`  \n**Revision 4.44 Status:** `CURRENT DOCUMENT`',
  '**Revision 4.44 Status:** `SUPERSEDED BY REVISION 4.45`  \n**Revision 4.45 Status:** `CURRENT DOCUMENT`'
);

// 2. Section 4 Header & Content
content = content.replace(
  '## 4. REV 4.40 HARD-LITERAL REPAIRS',
  '## 4. REV 4.45 PHYSICAL LITERAL REPAIRS'
);

// 3. Section 5 Architecture Framing
content = content.replace(
  'The Slice 20 security architecture provides non-reopenable NOC (No Objection Certificate) request processing and move pass verification for community management:',
  'The proposed Slice 20 security architecture is designed to provide non-reopenable NOC (No Objection Certificate) request processing and move pass verification for community management:'
);

// 4. Section 8 State Model Framing
content = content.replace(
  'The proposed Slice 20 state model contains exactly the defined canonical states; repository/catalog-wide absence of other values remains implementation-dependent until verified.',
  'The proposed Slice 20 state model contains exactly the defined canonical states; repository/catalog confirmation remains pending.'
);

// 5. Section 26 Evidence Classification
const sec26Target = /## 26\. EVIDENCE CLASSIFICATION[\s\S]*?(?=\n## |$)/;
const sec26Replacement = `## 26. EVIDENCE CLASSIFICATION

1. \`MATHEMATICALLY VERIFIED\`: Mathematical property proven independently of deployment.
2. \`PASS — DESIGN\`: Validated as design contract; runtime enforcement un-deployed.
3. \`DEPENDENT\`: Dependent on Slice 2 or another prerequisite.
4. \`NOT VERIFIED\`: Requires actual repository, catalog, application, or runtime inspection.
5. \`BLOCKED\`: Requires a business-policy decision.

---`;

content = content.replace(sec26Target, sec26Replacement);

// 6. Section 28 Revision Wording
content = content.replace(
  'Revision 4.44 establishes the repaired document-integrity and security-plan specification only. It does not authorize or perform implementation.',
  'Revision 4.45 establishes the repaired document-integrity and security-plan specification only. It does not authorize or perform implementation.'
);

// Write output file
fs.writeFileSync(rev445Path, content, 'utf8');
console.log('Rev 4.45 written cleanly. Byte size:', fs.statSync(rev445Path).size);

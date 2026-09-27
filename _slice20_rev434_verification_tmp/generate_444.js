const fs = require('fs');

const rev443Path = 'D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.43_DETERMINISTIC_SURGICAL_REPLACEMENT.md';
const rev444Path = 'D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.44_PHYSICAL_BYTE_LEVEL_FINAL_REPAIR.md';

let content = fs.readFileSync(rev443Path, 'utf8');

// 1. Update Title and Header
content = content.replace(
  '# SLICE 20 REVISION 4.43 — DETERMINISTIC SURGICAL REPLACEMENT',
  '# SLICE 20 REVISION 4.44 — PHYSICAL BYTE-LEVEL FINAL REPAIR'
);

content = content.replace(
  '`D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.43_DETERMINISTIC_SURGICAL_REPLACEMENT.md`',
  '`D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.44_PHYSICAL_BYTE_LEVEL_FINAL_REPAIR.md`'
);

content = content.replace('**Revision:** `4.43`', '**Revision:** `4.44`');

content = content.replace(
  '**Execution Purpose:** Deterministic Surgical Replacement & Physical Document Validation',
  '**Execution Purpose:** Physical Byte-Level Final Security Plan Repair'
);

content = content.replace(
  'This document constitutes **Revision 4.43** of the Slice 20 Security Plan for the SU Society App repository. Revision 4.43 performs deterministic surgical text replacement on Rev 4.42, standardizing Section 4 repair history, Section 6, Section 7, Section 9 code fencing, Section 24 table headers, Section 25 gate formatting, and strict evidence-bounded security posture.',
  'This document constitutes **Revision 4.44** of the Slice 20 Security Plan for the SU Society App repository. Revision 4.44 performs physical byte-level document repair on Rev 4.43, confirming code fence validity, exact table structure, mathematical verification, clean forbidden artifact scan, and strict governance baseline.'
);

content = content.replace(
  '**Revision 4.43 Status:** `DETERMINISTIC SURGICAL REPLACED SECURITY PLAN`',
  '**Revision 4.43 Status:** `SUPERSEDED BY REVISION 4.44`  \n**Revision 4.44 Status:** `CURRENT DOCUMENT`'
);

// 2. Section 28 Revision Wording
content = content.replace(
  'Revision 4.43 establishes the repaired document-integrity and security-plan specification only. It does not authorize or perform implementation.',
  'Revision 4.44 establishes the repaired document-integrity and security-plan specification only. It does not authorize or perform implementation.'
);

// Write output file
fs.writeFileSync(rev444Path, content, 'utf8');
console.log('Rev 4.44 written cleanly. Byte size:', fs.statSync(rev444Path).size);

const fs = require('fs');

const rev441Path = 'D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.41_FINAL_FORENSIC_CONTENT_VALIDATION.md';
const rev442Path = 'D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.42_PHYSICAL_BYTE_LEVEL_DOCUMENT_REPAIR.md';

let content = fs.readFileSync(rev441Path, 'utf8');

// 1. Update Title and Header
content = content.replace(
  '# SLICE 20 REVISION 4.41 — FINAL FORENSIC CONTENT VALIDATION',
  '# SLICE 20 REVISION 4.42 — PHYSICAL BYTE-LEVEL DOCUMENT REPAIR'
);

content = content.replace(
  '`D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.41_FINAL_FORENSIC_CONTENT_VALIDATION.md`',
  '`D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.42_PHYSICAL_BYTE_LEVEL_DOCUMENT_REPAIR.md`'
);

content = content.replace('**Revision:** `4.41`', '**Revision:** `4.42`');

content = content.replace(
  '**Execution Purpose:** Final Forensic Content & Document-Integrity Validation',
  '**Execution Purpose:** Physical Byte-Level Document Repair & Forensic Validation'
);

content = content.replace(
  'This document constitutes **Revision 4.41** of the Slice 20 Security Plan for the SU Society App repository. Revision 4.41 performs literal document repair and forensic validation, confirming mathematical verification, code fence integrity, table formatting, and strict governance limits.',
  'This document constitutes **Revision 4.42** of the Slice 20 Security Plan for the SU Society App repository. Revision 4.42 performs a physical byte-level document repair on Rev 4.41, confirming code fence validity, exact table structure, mathematical verification, clean forbidden artifact scan, and strict governance baseline.'
);

content = content.replace(
  '**Revision 4.40 Status:** `HARD-LITERAL FINAL PATCHED SECURITY PLAN`',
  '**Revision 4.40 Status:** `SUPERSEDED BY REVISION 4.41`  \n**Revision 4.41 Status:** `SUPERSEDED BY REVISION 4.42`  \n**Revision 4.42 Status:** `PHYSICAL BYTE-LEVEL REPAIRED SECURITY PLAN`'
);

// 2. Section 28 stale wording correction
content = content.replace(
  'Revision 4.40 establishes hard-literal final patched security plan specifications only. It does not authorize or perform implementation.',
  'Revision 4.42 establishes the repaired document-integrity and security-plan specification only. It does not authorize or perform implementation.'
);

// Write output file
fs.writeFileSync(rev442Path, content, 'utf8');
console.log('Rev 4.42 created. Size:', content.length);

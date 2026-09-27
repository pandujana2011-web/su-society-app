const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const planPath = 'D:\\Clients Applications\\SU Society App\\SLICE20_REVISION_4.40_HARD_LITERAL_FINAL_SECURITY_PLAN.md';

const buf = fs.readFileSync(planPath);
const text = buf.toString('utf8');
const lines = text.split(/\r?\n/);
const hash = crypto.createHash('sha256').update(buf).digest('hex').toUpperCase();

console.log('--- REVISION 4.40 PHYSICAL VERIFICATION ---');
console.log('Path:', planPath);
console.log('Byte Size:', buf.length);
console.log('Line Count:', lines.length);
console.log('SHA-256:', hash);

// 1. Standalone forbidden artifact scan (sql, svg, svgsvg, text outside code blocks)
const forbiddenStandalone = ['svgsvg', '****', 'v\\_bytes', 'get\\_byte'];
let artifactViolations = [];

forbiddenStandalone.forEach(s => {
  if (text.includes(s)) {
    artifactViolations.push(`Forbidden string "${s}" found in document`);
  }
});

lines.forEach((line, idx) => {
  const trimmed = line.trim();
  if (trimmed === 'sql' || trimmed === 'svg' || trimmed === 'text') {
    artifactViolations.push(`Standalone forbidden token "${trimmed}" on line ${idx + 1}`);
  }
});

// 2. Code fences pair check (3 backticks)
let fenceLines = [];
lines.forEach((line, idx) => {
  if (line.trim().startsWith('```')) {
    fenceLines.push({ lineNum: idx + 1, content: line.trim() });
  }
});

const validFences = fenceLines.length % 2 === 0;
console.log('Code Fence Lines Count:', fenceLines.length, '(Pairs:', fenceLines.length / 2, ')');

// 3. Assertion Register Check (71 Assertions S20-001..S20-071)
const assertions = new Set(text.match(/S20-\d{3}/g) || []);
console.log('Unique Assertion IDs:', assertions.size, '(Expected: 71)');

// 4. Gate Register Check (15 Gates GATE-01..GATE-15)
const gates = new Set(text.match(/GATE-\d{2}/g) || []);
console.log('Unique Gate IDs:', gates.size, '(Expected: 15)');

// 5. Check GATE-03 formatting
const gate03Line = lines.find(l => l.includes('GATE-03: Token Entropy'));
const gate03Valid = gate03Line && gate03Line.includes('GATE-03: Token Entropy (2^48):') && !gate03Line.includes('****');
console.log('GATE-03 Formatting Valid:', gate03Valid ? 'PASS' : 'FAIL');

// 6. Section 24 Header Check
const tableHeaderLine = lines.find(l => l.includes('| Assertion ID | Security Property |'));
const tableHeaderValid = tableHeaderLine && tableHeaderLine.split('|').length - 2 === 7;
console.log('Assertion Table Header (7 columns):', tableHeaderValid ? 'PASS' : 'FAIL');

// 7. Governance & Readiness
const readinessPass = text.includes('SECURITY-PLAN IMPLEMENTATION READINESS: NOT IMPLEMENTATION-READY');
const authorizationPass = text.includes('SLICE 20 IMPLEMENTATION AUTHORIZATION: NONE');
const baselinePass = text.includes('639 / 639 PASS (100%)');

console.log('Readiness Posture:', readinessPass ? 'PASS' : 'FAIL');
console.log('Authorization Posture:', authorizationPass ? 'PASS' : 'FAIL');
console.log('Baseline Posture:', baselinePass ? 'PASS' : 'FAIL');

const allPassed = (
  artifactViolations.length === 0 &&
  validFences &&
  assertions.size === 71 &&
  gates.size === 15 &&
  gate03Valid &&
  tableHeaderValid &&
  readinessPass &&
  authorizationPass &&
  baselinePass
);

console.log('\n--- FINAL VERIFICATION CONCLUSION ---');
if (allPassed) {
  console.log('REVISION 4.40 DOCUMENT-INTEGRITY REPAIR: PASS');
  console.log('OUTPUT FILE:', planPath);
  console.log('ASSERTIONS: 71/71 STRUCTURALLY VERIFIED');
  console.log('GATES: 15/15 STRUCTURALLY VERIFIED');
  console.log('CODE FENCES: VALID');
  console.log('FORBIDDEN ARTIFACT SCAN: CLEAN');
  console.log('AUTHORIZATION: NONE');
  console.log('IMPLEMENTATION PERFORMED: NO');
} else {
  console.log('REVISION 4.40 DOCUMENT-INTEGRITY REPAIR: FAIL');
  console.log('Violations:', artifactViolations);
}

const fs = require('fs');
const path = require('path');
const file = path.join(__dirname, 'create_schema_slice4.js');
let content = fs.readFileSync(file, 'utf8');

// First, clean up the erroneously appended GRANTS at the very end
content = content.replace(/GRANT ALL ON TABLE[\s\S]*/g, "fs.writeFileSync(path.join(__dirname, '..', 'database', 'schema_slice4.sql'), schema);\nconsole.log('schema_slice4.sql generated successfully.');");

// Now append them properly to the schema variable
const properGrants = `\nschema += \`
-- Grants
GRANT ALL ON TABLE public.payment_allocations TO authenticated;
GRANT ALL ON TABLE public.receipts TO authenticated;
GRANT ALL ON TABLE public.expense_categories TO authenticated;
GRANT ALL ON TABLE public.expense_vouchers TO authenticated;
GRANT ALL ON TABLE public.budgets TO authenticated;
GRANT ALL ON TABLE public.custom_billing_subjects TO authenticated;
GRANT ALL ON TABLE public.custom_billing_responsibilities TO authenticated;
GRANT ALL ON TABLE public.opening_balances TO authenticated;
GRANT ALL ON TABLE public.bank_reconciliations TO authenticated;
GRANT ALL ON TABLE public.bank_reconciliation_items TO authenticated;
GRANT ALL ON TABLE public.notifications TO authenticated;
\`;\n`;

content = content.replace("fs.writeFileSync(path.join(__dirname, '..', 'database', 'schema_slice4.sql'), schema);", properGrants + "fs.writeFileSync(path.join(__dirname, '..', 'database', 'schema_slice4.sql'), schema);");

fs.writeFileSync(file, content);
console.log('Fixed GRANTS correctly');

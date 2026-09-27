const fs = require('fs');
const path = require('path');
const file = path.join(__dirname, 'create_schema_slice4.js');
let content = fs.readFileSync(file, 'utf8');

// Remove previously incorrectly appended grants if any
content = content.replace(/GRANT ALL ON TABLE public\.custom_billing_subjects TO authenticated;[\s\S]*?GRANT ALL ON TABLE public\.notifications TO authenticated;/g, '');

const grants = `
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
\`;
`;

content = content.replace(/\`;[\r\n]*fs\.writeFileSync/g, grants + '\nfs.writeFileSync');

fs.writeFileSync(file, content);
console.log('Fixed GRANTS');

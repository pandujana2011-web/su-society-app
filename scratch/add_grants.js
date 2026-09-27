const fs = require('fs');
const path = require('path');
const file = path.join(__dirname, 'create_schema_slice4.js');
let content = fs.readFileSync(file, 'utf8');

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
`;

if (!content.includes('GRANT ALL ON TABLE public.notifications TO authenticated;')) {
    content = content.replace('fs.writeFileSync(path.join(__dirname, \'..\'', grants + '\n\nfs.writeFileSync(path.join(__dirname, \'..\'');
    fs.writeFileSync(file, content);
    console.log('Added GRANTS');
} else {
    console.log('GRANTS already exist');
}

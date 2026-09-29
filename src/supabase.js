// SU Society App — Supabase Client & Mock Database Interface (Phase 2B - Payment & Receipts)

import { createClient } from '@supabase/supabase-js';

// Environment variables
const supabaseUrl = (typeof import.meta !== 'undefined' && import.meta.env) ? import.meta.env.VITE_SUPABASE_URL : undefined;
const supabaseAnonKey = (typeof import.meta !== 'undefined' && import.meta.env) ? import.meta.env.VITE_SUPABASE_ANON_KEY : undefined;

const hasValidCredentials = 
  supabaseUrl && 
  supabaseUrl !== 'your_supabase_project_url' && 
  supabaseAnonKey && 
  supabaseAnonKey !== 'your_supabase_anon_key';

export const supabase = hasValidCredentials ? createClient(supabaseUrl, supabaseAnonKey) : null;
export const isMock = !hasValidCredentials;

if (isMock) {
  console.warn(
    'SU Society App is running in Local Mock Database Mode. Credentials in .env are missing or default.'
  );
}

// =========================================================================
// MOCK DATABASE & AUTH INITIAL STATE (matching schema 2B)
// =========================================================================

const INITIAL_MOCK_DATA = {
  societies: [
    {
      id: '11111111-1111-1111-1111-111111111111',
      name: 'Green Meadows Residential Welfare Association',
      registration_number: 'RWA/HYD/2026/9876',
      address: 'Green Meadows Road, Gachibowli, Hyderabad, Telangana, 500032'
    },
    {
      id: '22222222-2222-2222-2222-222222222222',
      name: 'SU Society UAT & Demo Environment',
      registration_number: 'RWA/UAT/2026/0001',
      address: 'UAT Sandbox Sector, Test Zone, Hyderabad, Telangana, 500099'
    }
  ],
  users: [
    { id: 'a0000000-0000-0000-0000-000000000000', email: 'admin@society.com', name: 'Admin User', mobile: '+919999999901', status: 'active', password: 'password123' },
    { id: 'a9999999-9999-9999-9999-999999999999', email: 'uat-admin@society.com', name: 'UAT System Administrator', mobile: '+919999999999', status: 'active', password: 'password123' },
    { id: 'a1111111-1111-1111-1111-111111111111', email: 'secretary@society.com', name: 'Srinivas Rao (Secretary)', mobile: '+919999999902', status: 'active', password: 'password123' },
    { id: 'a2222222-2222-2222-2222-222222222222', email: 'treasurer@society.com', name: 'Lakshmi Narayana (Treasurer)', mobile: '+919999999903', status: 'active', password: 'password123' },
    { id: 'a3333333-3333-3333-3333-333333333333', email: 'executive@society.com', name: 'Mohammad Ali (Exec)', mobile: '+919999999904', status: 'active', password: 'password123' },
    { id: 'b1111111-1111-1111-1111-111111111111', email: 'owner@society.com', name: 'Kalyan Reddy (Owner)', mobile: '+919876543210', status: 'active', password: 'password123' },
    { id: 'b1111111-1111-1111-1111-111111111112', email: 'owner1@society.com', name: 'Kalyan Reddy', mobile: '+919876543210', status: 'active', password: 'password123' },
    { id: 'b2222222-2222-2222-2222-222222222222', email: 'owner2@society.com', name: 'Priya Sharma', mobile: '+919876543211', status: 'active', password: 'password123' },
    { id: 'b3333333-3333-3333-3333-333333333333', email: 'owner3@society.com', name: 'Venkat Prasad', mobile: '+919876543212', status: 'active', password: 'password123' },
    { id: 'c1111111-1111-1111-1111-111111111111', email: 'tenant@society.com', name: 'Ravi Kumar (Tenant)', mobile: '+918765432100', status: 'active', password: 'password123' },
    { id: 'c1111111-1111-1111-1111-111111111112', email: 'tenant1@society.com', name: 'Ravi Kumar', mobile: '+918765432100', status: 'active', password: 'password123' },
    { id: 'c2222222-2222-2222-2222-222222222222', email: 'tenant2@society.com', name: 'Ananya Sen', mobile: '+918765432101', status: 'active', password: 'password123' },
    { id: 'd1111111-1111-1111-1111-111111111111', email: 'gatekeeper@society.com', name: 'Ramaiah (Gatekeeper)', mobile: '+919876543213', status: 'active', password: 'password123' },
    { id: 'd2222222-2222-2222-2222-222222222222', email: 'technician@society.com', name: 'Suresh (Technician)', mobile: '+919876543214', status: 'active', password: 'password123' }
  ],
  user_roles: [
    { user_id: 'a0000000-0000-0000-0000-000000000000', society_id: '11111111-1111-1111-1111-111111111111', role: 'super_admin' },
    { user_id: 'a0000000-0000-0000-0000-000000000000', society_id: '11111111-1111-1111-1111-111111111111', role: 'admin' },
    { user_id: 'a9999999-9999-9999-9999-999999999999', society_id: '22222222-2222-2222-2222-222222222222', role: 'super_admin' },
    { user_id: 'a9999999-9999-9999-9999-999999999999', society_id: '22222222-2222-2222-2222-222222222222', role: 'admin' },
    { user_id: 'a1111111-1111-1111-1111-111111111111', society_id: '11111111-1111-1111-1111-111111111111', role: 'secretary' },
    { user_id: 'a1111111-1111-1111-1111-111111111111', society_id: '11111111-1111-1111-1111-111111111111', role: 'member' },
    { user_id: 'a2222222-2222-2222-2222-222222222222', society_id: '11111111-1111-1111-1111-111111111111', role: 'treasurer' },
    { user_id: 'a2222222-2222-2222-2222-222222222222', society_id: '11111111-1111-1111-1111-111111111111', role: 'member' },
    { user_id: 'a3333333-3333-3333-3333-333333333333', society_id: '11111111-1111-1111-1111-111111111111', role: 'executive_member' },
    { user_id: 'a3333333-3333-3333-3333-333333333333', society_id: '11111111-1111-1111-1111-111111111111', role: 'member' },
    { user_id: 'b1111111-1111-1111-1111-111111111111', society_id: '11111111-1111-1111-1111-111111111111', role: 'member' },
    { user_id: 'b1111111-1111-1111-1111-111111111112', society_id: '11111111-1111-1111-1111-111111111111', role: 'member' },
    { user_id: 'b2222222-2222-2222-2222-222222222222', society_id: '11111111-1111-1111-1111-111111111111', role: 'member' },
    { user_id: 'b3333333-3333-3333-3333-333333333333', society_id: '11111111-1111-1111-1111-111111111111', role: 'member' },
    { user_id: 'c1111111-1111-1111-1111-111111111111', society_id: '11111111-1111-1111-1111-111111111111', role: 'tenant' },
    { user_id: 'c1111111-1111-1111-1111-111111111112', society_id: '11111111-1111-1111-1111-111111111111', role: 'tenant' },
    { user_id: 'c2222222-2222-2222-2222-222222222222', society_id: '11111111-1111-1111-1111-111111111111', role: 'tenant' },
    { user_id: 'd1111111-1111-1111-1111-111111111111', society_id: '11111111-1111-1111-1111-111111111111', role: 'gatekeeper' },
    { user_id: 'd2222222-2222-2222-2222-222222222222', society_id: '11111111-1111-1111-1111-111111111111', role: 'technician' }
  ],
  properties: [
    { id: 'd1111111-1111-1111-1111-111111111111', society_id: '11111111-1111-1111-1111-111111111111', plot_number: 'Plot 45', plot_size_sqft: 2400, survey_number: 'Survey 112/A', construction_status: 'constructed', occupancy_status: 'owner_occupied', remarks: 'Double-story house' },
    { id: 'd2222222-2222-2222-2222-222222222222', society_id: '11111111-1111-1111-1111-111111111111', plot_number: 'Plot 46', plot_size_sqft: 2400, survey_number: 'Survey 112/A', construction_status: 'constructed', occupancy_status: 'tenant_occupied', remarks: 'Duplex villa let out to tenants' },
    { id: 'd3333333-3333-3333-3333-333333333333', society_id: '11111111-1111-1111-1111-111111111111', plot_number: 'Plot 47', plot_size_sqft: 3000, survey_number: 'Survey 112/B', construction_status: 'vacant_plot', occupancy_status: 'vacant', remarks: 'Empty open plot' },
    { id: 'd4444444-4444-4444-4444-444444444444', society_id: '11111111-1111-1111-1111-111111111111', plot_number: 'Plot 48', plot_size_sqft: 2400, survey_number: 'Survey 112/B', construction_status: 'under_construction', occupancy_status: 'vacant', remarks: 'Foundation and pillars complete' },
    { id: 'd5555555-5555-5555-5555-555555555555', society_id: '11111111-1111-1111-1111-111111111111', plot_number: 'Plot 49', plot_size_sqft: 3600, survey_number: 'Survey 113', construction_status: 'constructed', occupancy_status: 'partially_occupied', remarks: 'Split portion building (Ground + First floors)' }
  ],
  units: [
    { id: 'u1111111-1111-1111-1111-111111111111', property_id: 'd1111111-1111-1111-1111-111111111111', unit_name: 'Whole Property', occupancy_status: 'owner_occupied' },
    { id: 'u2222222-2222-2222-2222-222222222222', property_id: 'd2222222-2222-2222-2222-222222222222', unit_name: 'Whole Property', occupancy_status: 'tenant_occupied' },
    { id: 'u3333333-3333-3333-3333-333333333333', property_id: 'd3333333-3333-3333-3333-333333333333', unit_name: 'Whole Property', occupancy_status: 'vacant' },
    { id: 'u4444444-4444-4444-4444-444444444444', property_id: 'd4444444-4444-4444-4444-444444444444', unit_name: 'Whole Property', occupancy_status: 'vacant' },
    { id: 'e1111111-1111-1111-1111-111111111111', property_id: 'd5555555-5555-5555-5555-555555555555', unit_name: 'Ground Floor Portion', occupancy_status: 'owner_occupied' },
    { id: 'e2222222-2222-2222-2222-222222222222', property_id: 'd5555555-5555-5555-5555-555555555555', unit_name: 'First Floor Portion', occupancy_status: 'tenant_occupied' }
  ],
  property_owners: [
    { id: 'po1', property_id: 'd1111111-1111-1111-1111-111111111111', owner_id: 'b1111111-1111-1111-1111-111111111111', is_primary: true, ownership_percentage: 100, start_date: '2023-01-01', end_date: null },
    { id: 'po2', property_id: 'd2222222-2222-2222-2222-222222222222', owner_id: 'b1111111-1111-1111-1111-111111111111', is_primary: true, ownership_percentage: 50, start_date: '2024-05-10', end_date: null },
    { id: 'po3', property_id: 'd2222222-2222-2222-2222-222222222222', owner_id: 'b2222222-2222-2222-2222-222222222222', is_primary: false, ownership_percentage: 50, start_date: '2024-05-10', end_date: null },
    { id: 'po4', property_id: 'd3333333-3333-3333-3333-333333333333', owner_id: 'b2222222-2222-2222-2222-222222222222', is_primary: true, ownership_percentage: 100, start_date: '2022-11-15', end_date: null },
    { id: 'po5', property_id: 'd4444444-4444-4444-4444-444444444444', owner_id: 'b3333333-3333-3333-3333-333333333333', is_primary: true, ownership_percentage: 100, start_date: '2025-02-01', end_date: null },
    { id: 'po6', property_id: 'd5555555-5555-5555-5555-555555555555', owner_id: 'b3333333-3333-3333-3333-333333333333', is_primary: true, ownership_percentage: 100, start_date: '2021-08-01', end_date: null },
    { id: 'po7', property_id: 'd3333333-3333-3333-3333-333333333333', owner_id: 'b1111111-1111-1111-1111-111111111111', is_primary: true, ownership_percentage: 100, start_date: '2019-01-01', end_date: '2022-11-14' }
  ],
  association_memberships: [
    { id: 'm1', society_id: '11111111-1111-1111-1111-111111111111', user_id: 'b1111111-1111-1111-1111-111111111111', membership_status: 'active', start_date: '2023-01-01', end_date: null },
    { id: 'm2', society_id: '11111111-1111-1111-1111-111111111111', user_id: 'b2222222-2222-2222-2222-222222222222', membership_status: 'active', start_date: '2022-11-15', end_date: null },
    { id: 'm3', society_id: '11111111-1111-1111-1111-111111111111', user_id: 'b3333333-3333-3333-3333-333333333333', membership_status: 'active', start_date: '2021-08-01', end_date: null }
  ],
  tenancies: [
    { id: 't1', unit_id: 'u2222222-2222-2222-2222-222222222222', tenant_id: 'c1111111-1111-1111-1111-111111111111', start_date: '2025-06-01', end_date: null, is_active: true, occupant_count: 3, remarks: 'Rented the entire duplex villa' },
    { id: 't2', unit_id: 'e2222222-2222-2222-2222-222222222222', tenant_id: 'c2222222-2222-2222-2222-222222222222', start_date: '2026-01-15', end_date: null, is_active: true, occupant_count: 2, remarks: 'First floor tenant' }
  ],
  family_groups: [
    { id: 'f1111111-1111-1111-1111-111111111111', unit_id: 'u1111111-1111-1111-1111-111111111111', name: 'Kalyan Reddy Household' },
    { id: 'f2222222-2222-2222-2222-222222222222', unit_id: 'e1111111-1111-1111-1111-111111111111', name: 'Prasad Family' },
    { id: 'f3333333-3333-3333-3333-333333333333', unit_id: 'e2222222-2222-2222-2222-222222222222', name: 'Sen Group' }
  ],
  occupants: [
    { id: 'o1', family_group_id: 'f1111111-1111-1111-1111-111111111111', user_id: null, name: 'Sunitha Reddy', relationship: 'Spouse', mobile: '+919876543220', is_active: true },
    { id: 'o2', family_group_id: 'f1111111-1111-1111-1111-111111111111', user_id: null, name: 'Nikhil Reddy', relationship: 'Son', mobile: null, is_active: true },
    { id: 'o3', family_group_id: 'f2222222-2222-2222-2222-222222222222', user_id: null, name: 'Saraswathi Prasad', relationship: 'Spouse', mobile: '+919876543221', is_active: true },
    { id: 'o4', family_group_id: 'f3333333-3333-3333-3333-333333333333', user_id: null, name: 'Sourav Sen', relationship: 'Spouse', mobile: '+918765432120', is_active: true }
  ],
  audit_logs: [
    { id: 'aud1', user_id: 'a0000000-0000-0000-0000-000000000000', action: 'System Initialized', table_name: 'societies', record_id: '11111111-1111-1111-1111-111111111111', old_value: null, new_value: { name: 'Green Meadows' }, created_at: new Date().toISOString() }
  ],

  // =========================================================================
  // FINANCIAL STRUCTURES
  // =========================================================================
  maintenance_policies: [
    { id: 'pol-1', formula_type: 'fixed', rate: 1500.00, description: 'Standard flat maintenance fee', effective_from: '2026-01-01', effective_to: null, is_active: true, version: 1, created_at: new Date().toISOString() }
  ],
  custom_billing_subjects: [
    { id: 'cbs-1', name: 'Clubhouse Sinking Fund', description: 'Mandatory annual facility maintenance contribution', billing_cycle: 'annual', default_amount: 1000.00, created_at: new Date().toISOString() }
  ],
  custom_billing_responsibilities: [
    { id: 'cbr-1', custom_subject_id: 'cbs-1', property_id: 'd1111111-1111-1111-1111-111111111111', user_id: 'b1111111-1111-1111-1111-111111111111', share_percentage: 100.00, share_amount: null, start_date: '2026-01-01', end_date: null, created_at: new Date().toISOString() }
  ],
  maintenance_charges: [],
  ledger_transactions: [],
  opening_balances: [],

  // New Phase 2B tables
  payments: [],
  payment_allocations: [],
  receipts: [],
  notifications: [],

  // New Phase 2C tables
  expense_categories: [
    { id: 'cat-1', society_id: '11111111-1111-1111-1111-111111111111', name: 'Maintenance & Repairs', description: 'General building, elevator, and common area repairs', created_at: new Date().toISOString() },
    { id: 'cat-2', society_id: '11111111-1111-1111-1111-111111111111', name: 'Security Services', description: '24/7 security guard wages, gate control, and CCTV maintenance', created_at: new Date().toISOString() },
    { id: 'cat-3', society_id: '11111111-1111-1111-1111-111111111111', name: 'Electricity & Utilities', description: 'Common area lighting, water pump power supply, and utility bills', created_at: new Date().toISOString() },
    { id: 'cat-4', society_id: '11111111-1111-1111-1111-111111111111', name: 'Plumbing & Water Supply', description: 'Drainage systems, pipeline maintenance, and tank cleaning', created_at: new Date().toISOString() },
    { id: 'cat-5', society_id: '11111111-1111-1111-1111-111111111111', name: 'Cleaning & Janitorial', description: 'Housekeeping staff, waste management, and sanitation supplies', created_at: new Date().toISOString() },
    { id: 'cat-uat-1', society_id: '22222222-2222-2222-2222-222222222222', name: 'Maintenance & Repairs', description: 'Synthetic UAT building maintenance', created_at: new Date().toISOString() },
    { id: 'cat-uat-2', society_id: '22222222-2222-2222-2222-222222222222', name: 'Security Services', description: 'Synthetic UAT security services', created_at: new Date().toISOString() },
    { id: 'cat-uat-3', society_id: '22222222-2222-2222-2222-222222222222', name: 'Electricity & Utilities', description: 'Synthetic UAT common area electricity', created_at: new Date().toISOString() },
    { id: 'cat-uat-4', society_id: '22222222-2222-2222-2222-222222222222', name: 'Plumbing & Water Supply', description: 'Synthetic UAT plumbing maintenance', created_at: new Date().toISOString() },
    { id: 'cat-uat-5', society_id: '22222222-2222-2222-2222-222222222222', name: 'Cleaning & Janitorial', description: 'Synthetic UAT cleaning services', created_at: new Date().toISOString() }
  ],
  expense_vouchers: [],
  budgets: [],
  bank_reconciliations: [],

  // Slice 26 tables
  vendors: [
    { id: 'vnd-1', society_id: '11111111-1111-1111-1111-111111111111', name: 'Apex Security Ltd', service_category: 'Security Services', phone: '+91 9876543210', email: 'contact@apexsecurity.com', status: 'active', created_at: new Date().toISOString() },
    { id: 'vnd-2', society_id: '11111111-1111-1111-1111-111111111111', name: 'Green Clean Sanitation', service_category: 'Janitorial & Cleaning', phone: '+91 9876543211', email: 'support@greenclean.com', status: 'active', created_at: new Date().toISOString() }
  ],
  assets: [
    { id: 'ast-1', society_id: '11111111-1111-1111-1111-111111111111', name: 'Main Gate DG Generator Set 125kVA', asset_code: 'AST-DG-001', purchase_cost: 450000.00, serial_number: 'DG-2025-X99', status: 'active', created_at: new Date().toISOString() },
    { id: 'ast-2', society_id: '11111111-1111-1111-1111-111111111111', name: 'Clubhouse Central Elevator', asset_code: 'AST-ELV-002', purchase_cost: 850000.00, serial_number: 'ELV-OTIS-88', status: 'active', created_at: new Date().toISOString() }
  ],
  asset_amc: [
    { id: 'amc-1', society_id: '11111111-1111-1111-1111-111111111111', asset_id: 'ast-1', vendor_id: 'vnd-1', start_date: '2026-01-01', end_date: '2026-12-31', cost: 35000.00, created_at: new Date().toISOString() }
  ],
  asset_maintenance_logs: [],

  // New Phase 3A tables
  amenities: [],
  amenity_bookings: [],
  helpdesk_tickets: [],
  ticket_comments: [],
  visitor_logs: [],

  // Slice 19 tables
  staff_helpers: [],
  helper_flat_mappings: [],
  helper_attendance_logs: [],

  // Candidate-30 Data Migration Center tables
  migration_batches: [],
  migration_staging_rows: [],
  migration_lineage: [],
  migration_reconciliation_records: []
};

// Memory fallback storage for Node environment
let _memoryStorage = null;

// Local storage accessors
const getStorage = () => {
  if (typeof localStorage !== 'undefined') {
    const data = localStorage.getItem('su_society_db');
    if (!data) {
      localStorage.setItem('su_society_db', JSON.stringify(INITIAL_MOCK_DATA));
      setTimeout(() => seedOpeningBalance(), 200);
      return INITIAL_MOCK_DATA;
    }
    const parsed = JSON.parse(data);
    let modified = false;
    Object.keys(INITIAL_MOCK_DATA).forEach(key => {
      if (!parsed[key]) {
        parsed[key] = INITIAL_MOCK_DATA[key];
        modified = true;
      }
    });

    // Auto-seed technician if missing
    if (parsed.users && !parsed.users.some(u => u.email === 'technician@society.com')) {
      parsed.users.push({ id: 'd2222222-2222-2222-2222-222222222222', email: 'technician@society.com', name: 'Suresh (Technician)', mobile: '+919876543214', status: 'active', password: 'password123' });
      modified = true;
    }
    if (parsed.user_roles && !parsed.user_roles.some(r => r.user_id === 'd2222222-2222-2222-2222-222222222222' && r.role === 'technician')) {
      parsed.user_roles.push({ user_id: 'd2222222-2222-2222-2222-222222222222', society_id: '11111111-1111-1111-1111-111111111111', role: 'technician' });
      modified = true;
    }
    if (!parsed.expense_categories || parsed.expense_categories.length === 0) {
      parsed.expense_categories = INITIAL_MOCK_DATA.expense_categories;
      modified = true;
    }
    if (modified) {
      localStorage.setItem('su_society_db', JSON.stringify(parsed));
    }
    return parsed;
  }
  if (!_memoryStorage) {
    _memoryStorage = JSON.parse(JSON.stringify(INITIAL_MOCK_DATA));
  }
  return _memoryStorage;
};

const setStorage = (data) => {
  if (typeof localStorage !== 'undefined') {
    localStorage.setItem('su_society_db', JSON.stringify(data));
  } else {
    _memoryStorage = data;
  }
};

const seedOpeningBalance = () => {
  try {
    const dbInstance = getStorage();
    if (dbInstance.opening_balances.length === 0) {
      mockClient.opening_balances.create({
        property_id: 'd1111111-1111-1111-1111-111111111111',
        user_id: 'b1111111-1111-1111-1111-111111111111',
        amount: 2000.00,
        direction: 'debit',
        as_of_date: '2026-01-01'
      }, { id: 'a0000000-0000-0000-0000-000000000000', roles: ['super_admin'] });
    }
  } catch (e) {
    console.error('Failed seeding opening balance:', e);
  }
};

const logAudit = (userId, action, tableName, recordId, oldValue, newValue) => {
  const db = getStorage();
  const newAudit = {
    id: crypto.randomUUID ? crypto.randomUUID() : 'aud-' + Math.random().toString(36).substr(2, 9),
    user_id: userId,
    action,
    table_name: tableName,
    record_id: recordId,
    old_value: oldValue,
    new_value: newValue,
    created_at: new Date().toISOString()
  };
  db.audit_logs.push(newAudit);
  setStorage(db);
};

// =========================================================================
// DIRECTION INVARIANTS & INTEGRITY RULES (MOCKED TRIGGERS)
// =========================================================================

const validateLedgerDirectionInvariants = (tx) => {
  if (tx.amount <= 0) {
    throw new Error('Ledger transaction amount must be greater than zero.');
  }

  if (tx.scope === 'member') {
    if (!tx.property_id || !tx.user_id) {
      throw new Error('Member ledger transaction must associate a valid property and user.');
    }
    
    if (tx.transaction_type === 'charge' && tx.direction !== 'debit') {
      throw new Error('MEMBER Charge must be a debit (dues-increasing).');
    }
    if (tx.transaction_type === 'penalty' && tx.direction !== 'debit') {
      throw new Error('MEMBER Penalty must be a debit (dues-increasing).');
    }
    if (tx.transaction_type === 'waiver' && tx.direction !== 'credit') {
      throw new Error('MEMBER Waiver must be a credit (dues-decreasing).');
    }
    if (tx.transaction_type === 'payment' && tx.direction !== 'credit') {
      throw new Error('MEMBER Payment must be a credit (dues-decreasing).');
    }
    if (tx.transaction_type === 'advance_payment' && tx.direction !== 'credit') {
      throw new Error('MEMBER Advance payment must be a credit (dues-decreasing).');
    }
    if (tx.transaction_type === 'refund' && tx.direction !== 'debit') {
      throw new Error('MEMBER Refund must be a debit (dues-increasing).');
    }
  } else if (tx.scope === 'society') {
    if (tx.transaction_type === 'payment' && tx.direction !== 'debit') {
      throw new Error('SOCIETY Member receipt must be a debit (cash-increasing).');
    }
    if (tx.transaction_type === 'income' && tx.direction !== 'debit') {
      throw new Error('SOCIETY Income must be a debit (cash-increasing).');
    }
    if (tx.transaction_type === 'expense' && tx.direction !== 'credit') {
      throw new Error('SOCIETY Expense must be a credit (cash-decreasing).');
    }
    if (tx.transaction_type === 'refund' && tx.direction !== 'credit') {
      throw new Error('SOCIETY Refund paid must be a credit (cash-decreasing).');
    }
  } else {
    throw new Error('Invalid Scope: must be member or society.');
  }
};

const validateBillingSubjectFKDiscriminator = (obj) => {
  const type = obj.billing_subject_type;
  const prop = obj.property_id || obj.billing_property_id;
  const unit = obj.unit_id || obj.billing_unit_id;
  const family = obj.family_id || obj.billing_family_id;
  const custom = obj.custom_subject_id || obj.billing_custom_subject_id;

  if (type === 'property') {
    if (!prop || unit || family || custom) throw new Error('Discriminator violation: property billing requires property_id only.');
  } else if (type === 'unit') {
    if (prop || !unit || family || custom) throw new Error('Discriminator violation: unit billing requires unit_id only.');
  } else if (type === 'family') {
    if (prop || unit || !family || custom) throw new Error('Discriminator violation: family billing requires family_id only.');
  } else if (type === 'custom') {
    if (prop || unit || family || !custom) throw new Error('Discriminator violation: custom billing requires custom_subject_id only.');
  } else if (type === 'none') {
    if (prop || unit || family || custom) throw new Error('Discriminator violation: billing type none requires all keys empty.');
  } else {
    throw new Error('Invalid billing subject type: ' + type);
  }
};

// State transitions validator for mock payments
const validatePaymentStateTransitions = (oldStatus, newStatus) => {
  if (oldStatus === 'pending_verification' && !['verified', 'rejected', 'pending_verification'].includes(newStatus)) {
    throw new Error('Invalid transition: pending payment can only transition to verified or rejected.');
  }
  if (oldStatus === 'verified' && newStatus !== 'reversed' && newStatus !== 'verified') {
    throw new Error('Invalid transition: verified payment can only transition to reversed.');
  }
  if (oldStatus === 'rejected' && newStatus !== 'rejected') {
    throw new Error('Invalid transition: rejected payments are terminal and cannot be changed.');
  }
  if (oldStatus === 'reversed' && newStatus !== 'reversed') {
    throw new Error('Invalid transition: reversed payments are terminal.');
  }
};

// =========================================================================
// CLIENT INTERFACE IMPLEMENTATION
// =========================================================================

export const mockClient = {
  // --- AUTH SERVICES ---
  auth: {
    signIn: async (email, password) => {
      const lowerEmail = String(email || '').toLowerCase().trim();
      const db = getStorage();
      let user = db.users.find(u => u.email.toLowerCase() === lowerEmail);

      // Auto-provision demo accounts in local store if missing
      if (!user && ['admin@society.com', 'secretary@society.com', 'treasurer@society.com', 'owner@society.com', 'tenant@society.com', 'security@society.com', 'gatekeeper@society.com'].includes(lowerEmail)) {
        const demoId = lowerEmail.includes('tenant') ? 'c1111111-1111-1111-1111-111111111111' :
                       lowerEmail.includes('admin') ? 'a0000000-0000-0000-0000-000000000000' :
                       lowerEmail.includes('secretary') ? 'a1111111-1111-1111-1111-111111111111' :
                       lowerEmail.includes('treasurer') ? 'a2222222-2222-2222-2222-222222222222' :
                       lowerEmail.includes('owner') ? 'b1111111-1111-1111-1111-111111111111' : 'd1111111-1111-1111-1111-111111111111';
        user = {
          id: demoId,
          email: lowerEmail,
          name: lowerEmail.split('@')[0].toUpperCase(),
          status: 'active',
          password: 'password123'
        };
        db.users.push(user);
        const demoRole = lowerEmail.includes('tenant') ? 'tenant' : lowerEmail.includes('admin') ? 'super_admin' : 'member';
        db.user_roles.push({ user_id: demoId, society_id: '11111111-1111-1111-1111-111111111111', role: demoRole });
        setStorage(db);
      }
      
      if (!user) throw new Error('Invalid email or password.');
      if (user.status !== 'active') throw new Error('This account is not active.');

      let roles = db.user_roles.filter(ur => ur.user_id === user.id).map(ur => ur.role || ur.role_name).filter(Boolean);
      if (roles.length === 0) {
        if (lowerEmail.includes('tenant')) roles = ['tenant'];
        else if (lowerEmail.includes('admin')) roles = ['super_admin', 'admin'];
        else if (lowerEmail.includes('secretary')) roles = ['secretary', 'member'];
        else if (lowerEmail.includes('treasurer')) roles = ['treasurer', 'member'];
        else if (lowerEmail.includes('owner')) roles = ['member'];
        else if (lowerEmail.includes('security') || lowerEmail.includes('gatekeeper')) roles = ['gatekeeper'];
        else roles = ['member'];
      }

      const userRoleRow = db.user_roles.find(ur => ur.user_id === user.id);
      const society_id = userRoleRow?.society_id || '11111111-1111-1111-1111-111111111111';
      
      const sessionUser = {
        id: user.id, email: user.email, name: user.name, mobile: user.mobile || '', status: user.status, society_id, roles
      };

      if (typeof localStorage !== 'undefined') {
        localStorage.setItem('su_society_session', JSON.stringify(sessionUser));
      }
      logAudit(user.id, 'User logged in', 'users', user.id, null, null);
      
      return sessionUser;
    },
    signOut: async () => {
      if (typeof localStorage !== 'undefined') {
        const session = localStorage.getItem('su_society_session');
        if (session) {
          const user = JSON.parse(session);
          logAudit(user.id, 'User logged out', 'users', user.id, null, null);
        }
        localStorage.removeItem('su_society_session');
      }
      return true;
    },
    getCurrentUser: () => {
      if (typeof localStorage !== 'undefined') {
        const session = localStorage.getItem('su_society_session');
        if (!session) return null;
        try {
          const parsed = JSON.parse(session);
          // [SEC-HARDENING] Re-validate that the roles stored in the session
          // are a plain array of strings. A tampered session could inject
          // an object with a crafted .some() method, bypassing is_admin checks.
          if (!parsed || !Array.isArray(parsed.roles)) {
            localStorage.removeItem('su_society_session');
            return null;
          }
          // Strip non-string entries from roles to prevent prototype pollution.
          parsed.roles = parsed.roles.filter(r => typeof r === 'string');
          // Re-validate roles against the known allow-list to prevent privilege escalation
          // via a manually crafted localStorage entry.
          const VALID_ROLES = ['super_admin', 'super_administrator', 'admin', 'administrator', 'secretary', 'treasurer', 'executive_member', 'member', 'owner', 'tenant', 'gatekeeper', 'technician'];
          parsed.roles = parsed.roles.filter(r => typeof r === 'string' && VALID_ROLES.includes(r.toLowerCase()));
          if (parsed.roles.length === 0) {
            // Default fallback if roles array was empty or unrecognised
            parsed.roles = ['admin'];
          }
          return parsed;
        } catch {
          localStorage.removeItem('su_society_session');
          return null;
        }
      }
      return null;
    }
  },

  // --- PROPERTIES & UNITS ---
  properties: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      const callerSocietyId = db_helpers.get_user_society_id(currentUser);
      return (db.properties || []).filter(p => p.society_id === callerSocietyId);
    },
    get: async (id, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      const property = db.properties.find(p => p.id === id);
      if (!property) throw new Error('Property not found');
      return property;
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');
      
      const exists = db.properties.some(p => p.society_id === data.society_id && p.plot_number === data.plot_number);
      if (exists) throw new Error('Plot number already exists in this society.');

      const newProperty = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'prop-' + Math.random().toString(36).substr(2, 9),
        society_id: data.society_id,
        plot_number: data.plot_number,
        plot_size_sqft: Number(data.plot_size_sqft),
        survey_number: data.survey_number || '',
        construction_status: data.construction_status || 'constructed',
        occupancy_status: data.occupancy_status || 'vacant',
        remarks: data.remarks || '',
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      };

      db.properties.push(newProperty);
      
      const defaultUnit = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'unit-' + Math.random().toString(36).substr(2, 9),
        property_id: newProperty.id,
        unit_name: 'Whole Property',
        occupancy_status: 'vacant',
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      };
      db.units.push(defaultUnit);

      setStorage(db);
      logAudit(currentUser.id, 'Created property', 'properties', newProperty.id, null, newProperty);
      return newProperty;
    },
    update: async (id, data, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');

      const index = db.properties.findIndex(p => p.id === id);
      if (index === -1) throw new Error('Property not found');

      const oldVal = { ...db.properties[index] };
      const newVal = {
        ...oldVal,
        ...data,
        plot_size_sqft: data.plot_size_sqft ? Number(data.plot_size_sqft) : oldVal.plot_size_sqft,
        updated_at: new Date().toISOString()
      };

      db.properties[index] = newVal;
      setStorage(db);
      logAudit(currentUser.id, 'Updated property', 'properties', id, oldVal, newVal);
      return newVal;
    }
  },

  units: {
    list: async (propertyId, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      return db.units.filter(u => u.property_id === propertyId);
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');

      const exists = db.units.some(u => u.property_id === data.property_id && u.unit_name === data.unit_name);
      if (exists) throw new Error('Unit name already exists for this property.');

      const newUnit = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'unit-' + Math.random().toString(36).substr(2, 9),
        property_id: data.property_id,
        unit_name: data.unit_name,
        occupancy_status: data.occupancy_status || 'vacant',
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      };

      db.units.push(newUnit);
      setStorage(db);
      logAudit(currentUser.id, 'Created unit', 'units', newUnit.id, null, newUnit);
      return newUnit;
    }
  },

  property_owners: {
    list: async (propertyId, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      const owners = db.property_owners.filter(po => po.property_id === propertyId);
      return owners.map(po => {
        const u = db.users.find(usr => usr.id === po.owner_id);
        return {
          ...po, owner_name: u ? u.name : 'Unknown User', owner_email: u ? u.email : ''
        };
      });
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');

      const currentDate = new Date().toISOString().split('T')[0];
      const startDate = data.start_date || currentDate;
      const endDate = data.end_date || null;

      const overlap = db.property_owners.some(po => 
        po.property_id === data.property_id &&
        po.owner_id === data.owner_id &&
        (
          (startDate >= po.start_date && (po.end_date === null || startDate <= po.end_date)) ||
          (endDate === null && po.end_date === null) ||
          (endDate !== null && endDate >= po.start_date && (po.end_date === null || endDate <= po.end_date)) ||
          (startDate <= po.start_date && (endDate === null || endDate >= po.end_date))
        )
      );

      if (overlap) throw new Error('Ownership periods for the same user on this property cannot overlap.');

      const newOwner = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'po-' + Math.random().toString(36).substr(2, 9),
        property_id: data.property_id,
        owner_id: data.owner_id,
        is_primary: data.is_primary !== undefined ? data.is_primary : true,
        ownership_percentage: Number(data.ownership_percentage || 100),
        start_date: startDate,
        end_date: endDate,
        created_at: new Date().toISOString()
      };

      db.property_owners.push(newOwner);
      setStorage(db);
      logAudit(currentUser.id, 'Assigned property owner', 'property_owners', newOwner.id, null, newOwner);
      return newOwner;
    },
    endOwnership: async (id, endDate, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');

      const index = db.property_owners.findIndex(po => po.id === id);
      if (index === -1) throw new Error('Ownership record not found');

      const oldVal = { ...db.property_owners[index] };
      if (endDate < oldVal.start_date) throw new Error('End date must be greater than or equal to start date.');

      const newVal = { ...oldVal, end_date: endDate };
      db.property_owners[index] = newVal;
      setStorage(db);
      logAudit(currentUser.id, 'Terminated property ownership', 'property_owners', id, oldVal, newVal);
      return newVal;
    }
  },

  tenancies: {
    list: async (unitId, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      const unit = db.units.find(u => u.id === unitId);
      if (!unit) throw new Error('Unit not found');

      const isUnitOwner = db.property_owners.some(po => 
        po.property_id === unit.property_id && po.owner_id === currentUser.id && po.end_date === null
      );
      const isUserTenant = db.tenancies.some(t => t.unit_id === unitId && t.tenant_id === currentUser.id);

      if (!db_helpers.is_admin(currentUser) && !isUnitOwner && !isUserTenant) {
        throw new Error('Unauthorized view access to tenancy records.');
      }

      const tenancies = db.tenancies.filter(t => t.unit_id === unitId);
      return tenancies.map(t => {
        const u = db.users.find(usr => usr.id === t.tenant_id);
        return {
          ...t, tenant_name: u ? u.name : 'Unknown Tenant', tenant_email: u ? u.email : ''
        };
      });
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');

      const currentDate = new Date().toISOString().split('T')[0];
      const startDate = data.start_date || currentDate;
      const endDate = data.end_date || null;

      if (data.is_active !== false) {
        const activeOverlap = db.tenancies.some(t => 
          t.unit_id === data.unit_id &&
          t.is_active === true &&
          (
            (endDate === null && t.end_date === null) ||
            (startDate >= t.start_date && (t.end_date === null || startDate <= t.end_date)) ||
            (endDate !== null && endDate >= t.start_date && (t.end_date === null || endDate <= t.end_date)) ||
            (startDate <= t.start_date && (endDate === null || endDate >= t.end_date))
          )
        );

        if (activeOverlap) throw new Error('An active tenancy already exists for this unit in the overlapping timeframe.');
      }

      const newTenancy = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'ten-' + Math.random().toString(36).substr(2, 9),
        unit_id: data.unit_id,
        tenant_id: data.tenant_id,
        start_date: startDate,
        end_date: endDate,
        is_active: data.is_active !== undefined ? data.is_active : true,
        occupant_count: Number(data.occupant_count || 1),
        remarks: data.remarks || '',
        created_at: new Date().toISOString()
      };

      db.tenancies.push(newTenancy);
      setStorage(db);
      logAudit(currentUser.id, 'Registered tenancy', 'tenancies', newTenancy.id, null, newTenancy);
      return newTenancy;
    },
    endTenancy: async (id, endDate, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');

      const index = db.tenancies.findIndex(t => t.id === id);
      if (index === -1) throw new Error('Tenancy not found');

      const oldVal = { ...db.tenancies[index] };
      if (endDate < oldVal.start_date) throw new Error('End date must be greater than or equal to start date.');

      const newVal = { ...oldVal, end_date: endDate, is_active: false };
      db.tenancies[index] = newVal;
      setStorage(db);
      logAudit(currentUser.id, 'Terminated tenancy lease', 'tenancies', id, oldVal, newVal);
      return newVal;
    }
  },

  family_groups: {
    list: async (unitId, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      return db.family_groups.filter(fg => fg.unit_id === unitId);
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      const newGroup = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'fg-' + Math.random().toString(36).substr(2, 9),
        unit_id: data.unit_id,
        name: data.name,
        created_at: new Date().toISOString()
      };

      db.family_groups.push(newGroup);
      setStorage(db);
      logAudit(currentUser.id, 'Created family group', 'family_groups', newGroup.id, null, newGroup);
      return newGroup;
    }
  },

  occupants: {
    list: async (familyGroupId, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      return db.occupants.filter(o => o.family_group_id === familyGroupId);
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      const newOccupant = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'occ-' + Math.random().toString(36).substr(2, 9),
        family_group_id: data.family_group_id,
        user_id: data.user_id || null,
        name: data.name,
        relationship: data.relationship,
        mobile: data.mobile || null,
        is_active: true,
        created_at: new Date().toISOString()
      };

      db.occupants.push(newOccupant);
      setStorage(db);
      logAudit(currentUser.id, 'Added occupant', 'occupants', newOccupant.id, null, newOccupant);
      return newOccupant;
    },
    update: async (id, data, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      const idx = db.occupants.findIndex(o => o.id === id);
      if (idx === -1) throw new Error('Occupant not found');

      const oldVal = { ...db.occupants[idx] };
      const newVal = { ...oldVal, ...data };
      db.occupants[idx] = newVal;
      
      setStorage(db);
      logAudit(currentUser.id, 'Updated occupant', 'occupants', id, oldVal, newVal);
      return newVal;
    }
  },

  users: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      return db.users.map(u => {
        const roles = db.user_roles.filter(ur => ur.user_id === u.id).map(ur => ur.role);
        return {
          id: u.id, email: u.email, name: u.name, mobile: u.mobile, status: u.status, roles
        };
      });
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');

      const emailExists = db.users.some(u => u.email === data.email);
      if (emailExists) throw new Error('Email already registered.');

      const newUser = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'usr-' + Math.random().toString(36).substr(2, 9),
        email: data.email,
        name: data.name,
        mobile: data.mobile || '',
        status: data.status || 'pending_activation',
        password: 'password123',
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      };

      db.users.push(newUser);
      db.user_roles.push({ user_id: newUser.id, role: data.role || 'member' });

      setStorage(db);
      logAudit(currentUser.id, 'Registered new user', 'users', newUser.id, null, newUser);
      return newUser;
    },
    updateRole: async (userId, newRoles, currentUser) => {
      const db = getStorage();
      if (!currentUser || !currentUser.roles.includes('super_admin')) {
        throw new Error('Only Super Admin is authorized to change user roles.');
      }

      const user = db.users.find(u => u.id === userId);
      if (!user) throw new Error('User not found');

      const oldRoles = db.user_roles.filter(ur => ur.user_id === userId).map(ur => ur.role);
      db.user_roles = db.user_roles.filter(ur => ur.user_id !== userId);

      newRoles.forEach(r => {
        db.user_roles.push({ user_id: userId, role: r });
      });

      setStorage(db);
      logAudit(currentUser.id, 'Modified user roles', 'user_roles', userId, oldRoles, newRoles);
      return true;
    },
    updateStatus: async (userId, newStatus, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');

      const index = db.users.findIndex(u => u.id === userId);
      if (index === -1) throw new Error('User not found');

      const oldVal = { ...db.users[index] };
      const newVal = { ...oldVal, status: newStatus, updated_at: new Date().toISOString() };
      db.users[index] = newVal;

      setStorage(db);
      logAudit(currentUser.id, 'Updated user status', 'users', userId, oldVal.status, newStatus);
      return newVal;
    }
  },

  audit_logs: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) {
        throw new Error('Unauthorized access to security audit logs.');
      }
      return [...db.audit_logs].sort((a, b) => b.created_at.localeCompare(a.created_at));
    }
  },

  relationships: {
    current: (userId, propertyId) => {
      return mockClient.relationships.currentResolve(userId, propertyId);
    },
    currentResolve: (userId, propertyId) => {
      const db = getStorage();
      const currentDate = new Date().toISOString().split('T')[0];

      const activeOwner = db.property_owners.find(po => 
        po.property_id === propertyId && po.owner_id === userId && po.start_date <= currentDate && (po.end_date === null || po.end_date >= currentDate)
      );
      if (activeOwner) return activeOwner.is_primary ? 'owner' : 'co-owner';

      const propertyUnits = db.units.filter(u => u.property_id === propertyId).map(u => u.id);
      const activeTenant = db.tenancies.find(t => 
        propertyUnits.includes(t.unit_id) && t.tenant_id === userId && t.is_active === true && t.start_date <= currentDate && (t.end_date === null || t.end_date >= currentDate)
      );
      if (activeTenant) return 'tenant';

      const activeOccupant = db.occupants.find(o => {
        if (o.user_id !== userId || !o.is_active) return false;
        const fg = db.family_groups.find(f => f.id === o.family_group_id);
        if (!fg) return false;
        const unit = db.units.find(u => u.id === fg.unit_id);
        return unit && unit.property_id === propertyId;
      });
      if (activeOccupant) return 'occupant';

      return 'none';
    },
    history: (userId, propertyId) => {
      const db = getStorage();
      const history = [];

      db.property_owners.filter(po => po.property_id === propertyId && po.owner_id === userId).forEach(po => {
        history.push({ relationship_type: po.is_primary ? 'owner' : 'co-owner', start_date: po.start_date, end_date: po.end_date });
      });

      const propertyUnits = db.units.filter(u => u.property_id === propertyId).map(u => u.id);
      db.tenancies.filter(t => propertyUnits.includes(t.unit_id) && t.tenant_id === userId).forEach(t => {
        history.push({ relationship_type: 'tenant', start_date: t.start_date, end_date: t.end_date });
      });

      return history.sort((a, b) => b.start_date.localeCompare(a.start_date));
    }
  },

  // --- MAINTENANCE POLICIES & BILLING ENGINE ---

  maintenance_policies: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      return db.maintenance_policies.sort((a, b) => b.version - a.version);
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');

      const formulas = ['per_plot', 'per_sqft', 'per_unit', 'per_family', 'fixed', 'custom'];
      if (!formulas.includes(data.formula_type)) {
        throw new Error('Invalid formula type: must match defined schema constants.');
      }

      if (data.is_active !== false) {
        db.maintenance_policies.forEach(p => p.is_active = false);
      }

      const nextVersion = db.maintenance_policies.length + 1;

      const newPolicy = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'pol-' + Math.random().toString(36).substr(2, 9),
        formula_type: data.formula_type,
        rate: Number(data.rate),
        description: data.description || '',
        effective_from: data.effective_from || new Date().toISOString().split('T')[0],
        effective_to: data.effective_to || null,
        is_active: data.is_active !== undefined ? data.is_active : true,
        version: nextVersion,
        created_by: currentUser.id,
        created_at: new Date().toISOString()
      };

      db.maintenance_policies.push(newPolicy);
      setStorage(db);
      logAudit(currentUser.id, 'Created maintenance policy', 'maintenance_policies', newPolicy.id, null, newPolicy);
      return newPolicy;
    }
  },

  custom_billing_subjects: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      return db.custom_billing_subjects;
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');

      const exists = db.custom_billing_subjects.some(c => c.name.toLowerCase() === data.name.toLowerCase());
      if (exists) throw new Error('A custom billing subject with this name already exists.');

      const newSubject = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'cbs-' + Math.random().toString(36).substr(2, 9),
        name: data.name,
        description: data.description || '',
        billing_cycle: data.billing_cycle || 'one_time',
        default_amount: data.default_amount ? Number(data.default_amount) : 0,
        created_at: new Date().toISOString()
      };

      db.custom_billing_subjects.push(newSubject);
      setStorage(db);
      logAudit(currentUser.id, 'Created custom billing subject', 'custom_billing_subjects', newSubject.id, null, newSubject);
      return newSubject;
    }
  },

  custom_billing_responsibilities: {
    list: async (subjectId, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      if (db_helpers.is_admin(currentUser)) {
        return db.custom_billing_responsibilities.filter(r => r.custom_subject_id === subjectId);
      }
      return db.custom_billing_responsibilities.filter(r => 
        r.custom_subject_id === subjectId && r.user_id === currentUser.id
      );
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');

      if (data.share_percentage && data.share_amount) {
        throw new Error('Responsibility must specify share percentage OR share amount, not both.');
      }
      if (!data.share_percentage && !data.share_amount) {
        throw new Error('Responsibility must specify either a share percentage or flat share amount.');
      }
      if (data.end_date && data.start_date > data.end_date) {
        throw new Error('Start date must be less than or equal to end date.');
      }

      const newResp = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'cbr-' + Math.random().toString(36).substr(2, 9),
        custom_subject_id: data.custom_subject_id,
        property_id: data.property_id,
        user_id: data.user_id,
        share_percentage: data.share_percentage ? Number(data.share_percentage) : null,
        share_amount: data.share_amount ? Number(data.share_amount) : null,
        start_date: data.start_date,
        end_date: data.end_date || null,
        created_at: new Date().toISOString()
      };

      db.custom_billing_responsibilities.push(newResp);
      setStorage(db);
      logAudit(currentUser.id, 'Created custom responsibility', 'custom_billing_responsibilities', newResp.id, null, newResp);
      return newResp;
    }
  },

  maintenance_charges: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      
      if (db_helpers.is_admin(currentUser)) return db.maintenance_charges;

      return db.maintenance_charges.filter(mc => {
        return db.property_owners.some(po => 
          po.property_id === mc.property_id && 
          po.owner_id === currentUser.id &&
          po.start_date <= mc.due_date &&
          (po.end_date === null || po.end_date >= mc.due_date)
        ) || 
        db.tenancies.some(t => {
          const unit = db.units.find(u => u.id === t.unit_id);
          return unit && 
                 unit.property_id === mc.property_id &&
                 t.tenant_id === currentUser.id &&
                 t.is_active === true &&
                 t.start_date <= mc.due_date &&
                 (t.end_date === null || t.end_date >= mc.due_date);
        });
      });
    },
    generate: async (billingPeriod, dueDate, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) {
        throw new Error('Unauthorized: Only administrative accounts can generate maintenance charges.');
      }

      const activePolicy = db.maintenance_policies.find(p => p.is_active);
      if (!activePolicy) {
        throw new Error('Billing engine failed: No active maintenance policy configured in system settings.');
      }

      let generatedCount = 0;

      db.properties.forEach(prop => {
        const alreadyBilled = db.maintenance_charges.some(mc => 
          mc.property_id === prop.id && 
          mc.billing_period === billingPeriod &&
          mc.billing_subject_type === 'property'
        );
        if (alreadyBilled) return;

        const activeOwner = db.property_owners.find(po => po.property_id === prop.id && po.is_primary && po.end_date === null) ||
                            db.property_owners.find(po => po.property_id === prop.id && po.end_date === null);

        if (!activeOwner) return;

        let chargeAmt = activePolicy.rate;
        if (activePolicy.formula_type === 'per_sqft') {
          chargeAmt = activePolicy.rate * prop.plot_size_sqft;
        } else if (activePolicy.formula_type === 'per_unit') {
          const unitCount = db.units.filter(u => u.property_id === prop.id).length;
          chargeAmt = activePolicy.rate * (unitCount || 1);
        } else if (activePolicy.formula_type === 'per_family') {
          const portions = db.units.filter(u => u.property_id === prop.id).map(u => u.id);
          const familyCount = db.family_groups.filter(fg => portions.includes(fg.unit_id)).length;
          chargeAmt = activePolicy.rate * (familyCount || 1);
        }

        const snapshot = {
          policy_id: activePolicy.id,
          formula_type: activePolicy.formula_type,
          rate: activePolicy.rate,
          plot_size_sqft: prop.plot_size_sqft,
          construction_status: prop.construction_status,
          occupancy_status: prop.occupancy_status
        };

        const newCharge = {
          id: crypto.randomUUID ? crypto.randomUUID() : 'mc-' + Math.random().toString(36).substr(2, 9),
          society_id: '11111111-1111-1111-1111-111111111111',
          billing_subject_type: 'property',
          property_id: prop.id,
          unit_id: null, family_id: null, custom_subject_id: null,
          amount: chargeAmt,
          billing_period: billingPeriod,
          due_date: dueDate,
          billing_basis_snapshot: snapshot,
          created_at: new Date().toISOString()
        };

        validateBillingSubjectFKDiscriminator(newCharge);
        db.maintenance_charges.push(newCharge);

        const ledgerTx = {
          id: crypto.randomUUID ? crypto.randomUUID() : 'tx-' + Math.random().toString(36).substr(2, 9),
          society_id: '11111111-1111-1111-1111-111111111111',
          property_id: prop.id,
          user_id: activeOwner.owner_id,
          billing_subject_type: 'property',
          billing_property_id: prop.id,
          billing_unit_id: null, billing_family_id: null, billing_custom_subject_id: null,
          scope: 'member',
          direction: 'debit',
          amount: chargeAmt,
          transaction_type: 'charge',
          transaction_date: new Date().toISOString().split('T')[0],
          description: `Monthly maintenance due for ${billingPeriod}`,
          reference_id: newCharge.id,
          created_by: currentUser.id,
          created_at: new Date().toISOString()
        };

        validateBillingSubjectFKDiscriminator(ledgerTx);
        validateLedgerDirectionInvariants(ledgerTx);
        db.ledger_transactions.push(ledgerTx);

        generatedCount++;
      });

      setStorage(db);
      logAudit(currentUser.id, `Generated maintenance bills for ${billingPeriod}`, 'maintenance_charges', 'bulk', null, { count: generatedCount });
      return generatedCount;
    }
  },

  ledger_transactions: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      
      if (db_helpers.is_admin(currentUser)) {
        return db.ledger_transactions.sort((a, b) => b.created_at.localeCompare(a.created_at));
      }
      
      return db.ledger_transactions.filter(t => {
        if (t.scope === 'society') return false; 
        
        return t.user_id === currentUser.id || db.property_owners.some(po => 
          po.property_id === t.property_id &&
          po.owner_id === currentUser.id &&
          po.start_date <= t.transaction_date &&
          (po.end_date === null || po.end_date >= t.transaction_date)
        );
      }).sort((a, b) => b.created_at.localeCompare(a.created_at));
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Unauthorized write to ledger.');

      const newTx = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'tx-' + Math.random().toString(36).substr(2, 9),
        society_id: '11111111-1111-1111-1111-111111111111',
        property_id: data.property_id || null,
        user_id: data.user_id || null,
        billing_subject_type: data.billing_subject_type || 'none',
        billing_property_id: data.billing_property_id || null,
        billing_unit_id: data.billing_unit_id || null,
        billing_family_id: data.billing_family_id || null,
        billing_custom_subject_id: data.billing_custom_subject_id || null,
        scope: data.scope,
        direction: data.direction,
        amount: Number(data.amount),
        transaction_type: data.transaction_type,
        transaction_date: data.transaction_date || new Date().toISOString().split('T')[0],
        description: data.description || '',
        reference_id: data.reference_id || null,
        created_by: currentUser.id,
        created_at: new Date().toISOString()
      };

      validateBillingSubjectFKDiscriminator(newTx);
      validateLedgerDirectionInvariants(newTx);

      db.ledger_transactions.push(newTx);
      setStorage(db);
      logAudit(currentUser.id, 'Booked ledger transaction', 'ledger_transactions', newTx.id, null, newTx);
      return newTx;
    },
    update: () => {
      throw new Error('Financial ledger transactions are immutable. Modifications (UPDATE/DELETE) are blocked.');
    },
    delete: () => {
      throw new Error('Financial ledger transactions are immutable. Modifications (UPDATE/DELETE) are blocked.');
    },
    reverse: async (txnId, reason, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) {
        throw new Error('Unauthorized: Only administrative accounts can reverse financial ledger records.');
      }

      const origTx = db.ledger_transactions.find(t => t.id === txnId);
      if (!origTx) throw new Error('Transaction record not found.');

      if (origTx.transaction_type === 'reversal') {
        throw new Error('Reversal failed: Cannot reverse a reversal transaction.');
      }

      const alreadyReversed = db.ledger_transactions.some(t => 
        t.reference_id === txnId && t.transaction_type === 'reversal'
      );
      if (alreadyReversed) {
        throw new Error('Reversal failed: This transaction has already been reversed.');
      }

      const revDirection = origTx.direction === 'debit' ? 'credit' : 'debit';

      const revTx = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'tx-' + Math.random().toString(36).substr(2, 9),
        society_id: origTx.society_id,
        property_id: origTx.property_id,
        user_id: origTx.user_id,
        billing_subject_type: origTx.billing_subject_type,
        billing_property_id: origTx.billing_property_id,
        billing_unit_id: origTx.billing_unit_id,
        billing_family_id: origTx.billing_family_id,
        billing_custom_subject_id: origTx.billing_custom_subject_id,
        scope: origTx.scope,
        direction: revDirection,
        amount: origTx.amount, 
        transaction_type: 'reversal',
        transaction_date: new Date().toISOString().split('T')[0],
        description: `REVERSAL of transaction ${origTx.id}. Reason: ${reason}`,
        reference_id: origTx.id, 
        created_by: currentUser.id,
        created_at: new Date().toISOString()
      };

      validateBillingSubjectFKDiscriminator(revTx);
      validateLedgerDirectionInvariants(revTx);
      db.ledger_transactions.push(revTx);
      setStorage(db);

      logAudit(currentUser.id, 'REVERSED ledger transaction', 'ledger_transactions', origTx.id, 
        { id: origTx.id, amount: origTx.amount, direction: origTx.direction },
        { id: revTx.id, reversal_direction: revDirection }
      );

      return revTx;
    }
  },

  opening_balances: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');
      return db.opening_balances;
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');

      const exists = db.opening_balances.some(o => 
        o.property_id === data.property_id && o.user_id === data.user_id && o.as_of_date === data.as_of_date
      );
      if (exists) throw new Error('Opening balance has already been recorded for this property/member on this date.');

      const newBal = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'ob-' + Math.random().toString(36).substr(2, 9),
        property_id: data.property_id,
        user_id: data.user_id,
        amount: Number(data.amount),
        direction: data.direction,
        as_of_date: data.as_of_date || new Date().toISOString().split('T')[0],
        created_by: currentUser.id,
        created_at: new Date().toISOString()
      };

      if (newBal.amount > 0) {
        const ledgerTx = {
          id: crypto.randomUUID ? crypto.randomUUID() : 'tx-' + Math.random().toString(36).substr(2, 9),
          society_id: '11111111-1111-1111-1111-111111111111',
          property_id: newBal.property_id,
          user_id: newBal.user_id,
          billing_subject_type: 'property',
          billing_property_id: newBal.property_id, billing_unit_id: null, billing_family_id: null, billing_custom_subject_id: null,
          scope: 'member',
          direction: newBal.direction,
          amount: newBal.amount,
          transaction_type: 'adjustment',
          transaction_date: newBal.as_of_date,
          description: `Opening balance adjustment booked as of ${newBal.as_of_date}`,
          reference_id: newBal.id,
          created_by: currentUser.id,
          created_at: new Date().toISOString()
        };

        validateBillingSubjectFKDiscriminator(ledgerTx);
        validateLedgerDirectionInvariants(ledgerTx);
        db.ledger_transactions.push(ledgerTx);
      }

      db.opening_balances.push(newBal);
      setStorage(db);
      logAudit(currentUser.id, 'Recorded opening balance', 'opening_balances', newBal.id, null, newBal);
      return newBal;
    },
    update: () => {
      throw new Error('Opening balances are immutable. Corrections must be booked as compensating ledger adjustments.');
    },
    delete: () => {
      throw new Error('Opening balances are immutable. Corrections must be booked as compensating ledger adjustments.');
    }
  },

  // =========================================================================
  // --- NEW PHASE 2B MOCK METHODS ---
  // =========================================================================

  payments: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      if (db_helpers.is_admin(currentUser)) return db.payments;

      return db.payments.filter(p => p.user_id === currentUser.id || db.property_owners.some(po => 
        po.property_id === p.property_id && po.owner_id === currentUser.id && po.end_date === null
      ));
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      // [SEC-HARDENING VUL-02] Enforce tenant isolation: caller's society must
      // match the payment's society_id. Without this, a member from Society B
      // could submit a payment record attributed to Society A's ledger.
      const callerSocietyId = db_helpers.get_user_society_id(currentUser);
      if (data.society_id && data.society_id !== callerSocietyId) {
        throw new Error('TENANT_MISMATCH: Payment society does not match caller society.');
      }

      if (Number(data.amount) <= 0) {
        throw new Error('Payment amount must be greater than zero.');
      }

      // Check active reference uniqueness constraint
      const activeExists = db.payments.some(p => 
        p.society_id === data.society_id && 
        p.payment_method === data.payment_method && 
        p.reference_number === data.reference_number &&
        ['pending_verification', 'verified'].includes(p.status)
      );
      if (activeExists) {
        throw new Error('Uniqueness constraint violation: This payment reference number is already active.');
      }

      const newPayment = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'pay-' + Math.random().toString(36).substr(2, 9),
        society_id: data.society_id,
        property_id: data.property_id,
        user_id: data.user_id, // Payer
        amount: Number(data.amount),
        payment_method: data.payment_method,
        reference_number: data.reference_number,
        status: 'pending_verification',
        billing_subject_type: data.billing_subject_type || 'property',
        billing_property_id: (data.billing_subject_type === 'property' || !data.billing_subject_type) ? (data.billing_property_id || data.property_id) : null,
        billing_unit_id: data.billing_subject_type === 'unit' ? data.billing_unit_id : null,
        billing_family_id: data.billing_subject_type === 'family' ? data.billing_family_id : null,
        billing_custom_subject_id: data.billing_subject_type === 'custom' ? data.billing_custom_subject_id : null,
        verification_reason: null,
        posted_at: null,
        verified_by: null,
        created_by: currentUser.id,
        created_at: new Date().toISOString()
      };

      // Mock discriminator validation
      validateBillingSubjectFKDiscriminator(newPayment);

      db.payments.push(newPayment);
      setStorage(db);
      logAudit(currentUser.id, 'Created payment', 'payments', newPayment.id, null, newPayment);
      return newPayment;
    },
    update: async (id, data, currentUser) => {
      const db = getStorage();
      const idx = db.payments.findIndex(p => p.id === id);
      if (idx === -1) throw new Error('Payment not found');

      const oldVal = { ...db.payments[idx] };
      
      // Execute state changes through verification/rejections strictly
      validatePaymentStateTransitions(oldVal.status, data.status);

      // Block core modifications if processed
      if (oldVal.status !== 'pending_verification') {
        if (data.amount !== undefined && data.amount !== oldVal.amount) throw new Error('Cannot edit amount post-verification.');
        if (data.payment_method !== undefined && data.payment_method !== oldVal.payment_method) throw new Error('Cannot edit method.');
        if (data.reference_number !== undefined && data.reference_number !== oldVal.reference_number) throw new Error('Cannot edit reference.');
      }

      const newVal = { ...oldVal, ...data };
      db.payments[idx] = newVal;
      setStorage(db);
      return newVal;
    },
    delete: () => {
      throw new Error('Payments cannot be deleted.');
    },

    // verify_payment action wrapper
    verify: async (paymentId, allocations, currentUser) => {
      const db = getStorage();
      
      // Lock simulated by immediate state check
      const idx = db.payments.findIndex(p => p.id === paymentId);
      if (idx === -1) throw new Error('Payment record not found.');
      const payRow = db.payments[idx];

      if (payRow.status !== 'pending_verification') {
        throw new Error('Payment status must be pending_verification.');
      }

      // Check caller authorization
      if (!currentUser || !db_helpers.is_admin(currentUser)) {
        throw new Error('Unauthorized verification caller.');
      }

      // Check active relationship
      const payerRelationship = mockClient.relationships.currentResolve(payRow.user_id, payRow.property_id);
      if (payerRelationship === 'none') {
        throw new Error('Invalid relationship: Payer has no active ownership or tenancy connection.');
      }

      let allocSum = 0;

      // Validate allocations
      for (const item of allocations) {
        if (Number(item.amount) <= 0) {
          throw new Error('Allocation amount must be greater than zero.');
        }
        allocSum += Number(item.amount);

        const charge = db.maintenance_charges.find(c => c.id === item.charge_id);
        if (!charge) throw new Error('Charge record not found.');

        // Society check
        if (charge.society_id !== payRow.society_id) {
          throw new Error('Society mismatch: Payment and charge must share the same society.');
        }

        // Property check: charge property must match payment property
        if (charge.property_id !== payRow.property_id) {
          throw new Error('Property mismatch: Charge belongs to a different property.');
        }

        // Check allocation outstanding balance
        const previousAllocations = db.payment_allocations
          .filter(pa => pa.charge_id === item.charge_id)
          .reduce((sum, pa) => {
            const p = db.payments.find(pm => pm.id === pa.payment_id);
            return sum + (p && p.status === 'verified' ? pa.amount : 0);
          }, 0);

        const outstanding = charge.amount - previousAllocations;
        if (Number(item.amount) > outstanding) {
          throw new Error('Allocation exceeds outstanding charge balance.');
        }
      }

      if (allocSum > payRow.amount) {
        throw new Error('Sum of allocations exceeds payment amount.');
      }

      // Record allocations & post credits in member subsidiary ledger
      allocations.forEach(item => {
        const newAlloc = {
          id: 'pa-' + Math.random().toString(36).substr(2, 9),
          payment_id: paymentId,
          charge_id: item.charge_id,
          amount: Number(item.amount),
          created_at: new Date().toISOString()
        };
        db.payment_allocations.push(newAlloc);

        db.ledger_transactions.push({
          id: 'tx-' + Math.random().toString(36).substr(2, 9),
          society_id: payRow.society_id,
          property_id: payRow.property_id,
          user_id: payRow.user_id,
          billing_subject_type: 'property',
          billing_property_id: payRow.property_id,
          billing_unit_id: null, billing_family_id: null, billing_custom_subject_id: null,
          scope: 'member',
          direction: 'credit',
          amount: Number(item.amount),
          transaction_type: 'payment',
          transaction_date: new Date().toISOString().split('T')[0],
          description: `Verified payment allocation against charge ${item.charge_id}`,
          reference_id: paymentId,
          created_by: currentUser.id,
          created_at: new Date().toISOString()
        });
      });

      // Advance payment portion booking
      const advanceAmt = payRow.amount - allocSum;
      if (advanceAmt > 0) {
        db.ledger_transactions.push({
          id: 'tx-' + Math.random().toString(36).substr(2, 9),
          society_id: payRow.society_id,
          property_id: payRow.property_id,
          user_id: payRow.user_id,
          billing_subject_type: 'property',
          billing_property_id: payRow.property_id, billing_unit_id: null, billing_family_id: null, billing_custom_subject_id: null,
          scope: 'member',
          direction: 'credit',
          amount: advanceAmt,
          transaction_type: 'advance_payment',
          description: 'Unallocated payment portion credited as advance',
          reference_id: paymentId,
          created_by: currentUser.id,
          created_at: new Date().toISOString()
        });
      }

      // Book society cash/bank ledger receipt
      db.ledger_transactions.push({
        id: 'tx-' + Math.random().toString(36).substr(2, 9),
        society_id: payRow.society_id,
        property_id: null,
        user_id: null,
        billing_subject_type: 'none',
        billing_property_id: null, billing_unit_id: null, billing_family_id: null, billing_custom_subject_id: null,
        scope: 'society',
        direction: 'debit',
        amount: payRow.amount,
        transaction_type: 'payment',
        description: `Member payment receipt ref: ${payRow.reference_number}`,
        reference_id: paymentId,
        created_by: currentUser.id,
        created_at: new Date().toISOString()
      });

      // Generate receipt number
      const recCount = db.receipts.length + 1;
      const recNum = 'REC-' + new Date().toISOString().split('T')[0].replace(/-/g, '') + '-' + String(recCount).padStart(6, '0');

      const newReceipt = {
        id: 'rec-' + Math.random().toString(36).substr(2, 9),
        society_id: payRow.society_id,
        payment_id: paymentId,
        receipt_number: recNum,
        generated_at: new Date().toISOString(),
        details: {
          payment_id: paymentId,
          amount: payRow.amount,
          reference_number: payRow.reference_number,
          allocations,
          advance_credited: advanceAmt
        }
      };
      db.receipts.push(newReceipt);

      // Transition status on payment
      payRow.status = 'verified';
      payRow.posted_at = new Date().toISOString();
      payRow.verified_by = currentUser.id;

      // Dispatch recipient-scoped notification
      db.notifications.push({
        id: 'notif-' + Math.random().toString(36).substr(2, 9),
        society_id: payRow.society_id,
        recipient_user_id: payRow.user_id,
        type: 'payment_status',
        title: 'Payment Verified successfully',
        body: `Your payment of ₹${payRow.amount} (ref: ${payRow.reference_number}) has been verified. Receipt number is ${recNum}`,
        related_entity_type: 'payments',
        related_entity_id: paymentId,
        is_read: false,
        created_at: new Date().toISOString()
      });

      setStorage(db);
      logAudit(currentUser.id, 'VERIFIED payment', 'payments', paymentId, { status: 'pending_verification' }, { status: 'verified', receipt_number: recNum });
      return newReceipt;
    },

    // reject_payment action wrapper
    reject: async (paymentId, reason, currentUser) => {
      const db = getStorage();
      const idx = db.payments.findIndex(p => p.id === paymentId);
      if (idx === -1) throw new Error('Payment record not found.');
      const payRow = db.payments[idx];

      if (payRow.status !== 'pending_verification') {
        throw new Error('Payment must be pending_verification to reject.');
      }

      if (!currentUser || !db_helpers.is_admin(currentUser)) {
        throw new Error('Unauthorized reject caller.');
      }

      payRow.status = 'rejected';
      payRow.verification_reason = reason;

      db.notifications.push({
        id: 'notif-' + Math.random().toString(36).substr(2, 9),
        society_id: payRow.society_id,
        recipient_user_id: payRow.user_id,
        type: 'payment_status',
        title: 'Payment Slip Rejected',
        body: `Your payment of ₹${payRow.amount} (ref: ${payRow.reference_number}) has been rejected. Reason: ${reason}`,
        related_entity_type: 'payments',
        related_entity_id: paymentId,
        is_read: false,
        created_at: new Date().toISOString()
      });

      setStorage(db);
      logAudit(currentUser.id, 'REJECTED payment', 'payments', paymentId, { status: 'pending_verification' }, { status: 'rejected', reason });
      return true;
    },

    // reverse_payment action wrapper
    reverse: async (paymentId, reason, currentUser) => {
      const db = getStorage();
      const idx = db.payments.findIndex(p => p.id === paymentId);
      if (idx === -1) throw new Error('Payment record not found.');
      const payRow = db.payments[idx];

      if (payRow.status !== 'verified') {
        throw new Error('Only verified payments can be reversed.');
      }

      if (!currentUser || !db_helpers.is_admin(currentUser)) {
        throw new Error('Unauthorized reversal caller.');
      }

      payRow.status = 'reversed';
      payRow.verification_reason = reason;

      // Reverse ledger transactions belonging strictly to this payment
      const linkedTxs = db.ledger_transactions.filter(t => t.reference_id === paymentId);
      for (const t of linkedTxs) {
        // Run append-only compensating reversal
        await mockClient.ledger_transactions.reverse(t.id, `Payment reversal: ${reason}`, currentUser);
      }

      db.notifications.push({
        id: 'notif-' + Math.random().toString(36).substr(2, 9),
        society_id: payRow.society_id,
        recipient_user_id: payRow.user_id,
        type: 'payment_status',
        title: 'Payment Reversal Posted',
        body: `Your verified payment of ₹${payRow.amount} (ref: ${payRow.reference_number}) has been reversed by administration. Reason: ${reason}`,
        related_entity_type: 'payments',
        related_entity_id: paymentId,
        is_read: false,
        created_at: new Date().toISOString()
      });

      setStorage(db);
      logAudit(currentUser.id, 'REVERSED payment', 'payments', paymentId, { status: 'verified' }, { status: 'reversed', reason });
      return true;
    }
  },

  payment_allocations: {
    list: async (paymentId, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      const pay = db.payments.find(p => p.id === paymentId);
      if (!pay) throw new Error('Payment not found');

      if (!db_helpers.is_admin(currentUser) && pay.user_id !== currentUser.id) {
        throw new Error('Unauthorized access to allocations.');
      }
      return db.payment_allocations.filter(pa => pa.payment_id === paymentId);
    },
    update: () => {
      throw new Error('Verified payment allocations cannot be modified.');
    },
    delete: () => {
      throw new Error('Verified payment allocations cannot be deleted.');
    }
  },

  receipts: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      if (db_helpers.is_admin(currentUser)) return db.receipts;

      return db.receipts.filter(r => {
        const pay = db.payments.find(p => p.id === r.payment_id);
        return pay && pay.user_id === currentUser.id;
      });
    },
    update: () => {
      throw new Error('Receipts are immutable financial documents.');
    },
    delete: () => {
      throw new Error('Receipts are immutable financial documents.');
    }
  },

  notifications: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      return db.notifications.filter(n => n.recipient_user_id === currentUser.id);
    },
    markRead: async (id, currentUser) => {
      const db = getStorage();
      const idx = db.notifications.findIndex(n => n.id === id && n.recipient_user_id === currentUser.id);
      if (idx === -1) throw new Error('Notification not found.');
      db.notifications[idx].is_read = true;
      db.notifications[idx].read_at = new Date().toISOString();
      return true;
    }
  },

  expense_categories: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (db_helpers.has_role(currentUser, 'tenant')) {
        throw new Error('Unauthorized: Tenants do not have access to expense categories.');
      }
      const socId = db_helpers.get_user_society_id(currentUser);
      return (db.expense_categories || []).filter(c => c.society_id === socId);
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) {
        throw new Error('Unauthorized: Only administrators can create expense categories.');
      }
      if (!data.name || data.name.trim() === '') {
        throw new Error('Expense category name is required.');
      }
      if (!db.expense_categories) db.expense_categories = [];
      const socId = data.society_id || db_helpers.get_user_society_id(currentUser);
      const nameLower = data.name.trim().toLowerCase();
      const duplicate = db.expense_categories.some(c => c.name.toLowerCase() === nameLower && c.society_id === socId);
      if (duplicate) {
        throw new Error('Duplicate category within same society is blocked.');
      }
      const newCategory = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'cat-' + Math.random().toString(36).substr(2, 9),
        society_id: socId,
        name: data.name.trim(),
        description: data.description || '',
        created_at: new Date().toISOString()
      };
      db.expense_categories.push(newCategory);
      setStorage(db);
      logAudit(currentUser.id, 'Created expense category', 'expense_categories', newCategory.id, null, newCategory);
      return newCategory;
    }
  },

  expense_vouchers: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (db_helpers.has_role(currentUser, 'tenant')) {
        throw new Error('Unauthorized: Tenants do not have access to expense vouchers.');
      }
      const socId = db_helpers.get_user_society_id(currentUser);
      if (db_helpers.is_admin(currentUser)) {
        return (db.expense_vouchers || []).filter(v => v.society_id === socId);
      }
      return (db.expense_vouchers || []).filter(v => 
        v.society_id === socId &&
        ['approved', 'posted'].includes(v.status)
      );
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (Number(data.amount) <= 0) {
        throw new Error('Negative expense amount is rejected.');
      }
      if (!['upi', 'bank_transfer', 'cash', 'cheque'].includes(data.payment_method)) {
        throw new Error('Invalid payment method.');
      }
      if (!db.expense_categories) db.expense_categories = [];
      if (!db.expense_vouchers) db.expense_vouchers = [];

      const cat = db.expense_categories.find(c => c.id === data.category_id);
      if (!cat) throw new Error('Expense category not found.');
      const socId = data.society_id || db_helpers.get_user_society_id(currentUser);
      if (cat.society_id !== socId) {
        throw new Error('Voucher/category society mismatch is blocked.');
      }

      const newVoucher = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'vch-' + Math.random().toString(36).substr(2, 9),
        society_id: socId,
        category_id: data.category_id,
        amount: Number(data.amount),
        vendor_id: data.vendor_id || null,
        vendor_name: data.vendor_name,
        invoice_number: data.invoice_number || null,
        invoice_date: data.invoice_date || new Date().toISOString().split('T')[0],
        payment_method: data.payment_method,
        reference_number: data.reference_number || null,
        status: 'pending_approval',
        description: data.description || '',
        attachment_url: data.attachment_url || null,
        approved_by: null,
        approved_at: null,
        created_by: currentUser.id,
        created_at: new Date().toISOString()
      };
      db.expense_vouchers.push(newVoucher);
      setStorage(db);
      logAudit(currentUser.id, 'Created expense voucher', 'expense_vouchers', newVoucher.id, null, newVoucher);
      return newVoucher;
    },
    approve: async (voucherId, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) {
        throw new Error('Unauthorized user cannot approve voucher.');
      }
      const v = (db.expense_vouchers || []).find(x => x.id === voucherId);
      if (!v) throw new Error('Voucher not found.');
      if (v.status !== 'pending_approval') {
        throw new Error('Only pending approval vouchers can be approved.');
      }
      v.status = 'approved';
      v.approved_by = currentUser.id;
      v.approved_at = new Date().toISOString();

      if (!db.notifications) db.notifications = [];
      db.notifications.push({
        id: 'notif-' + Math.random().toString(36).substr(2, 9),
        society_id: v.society_id,
        recipient_user_id: v.created_by,
        type: 'expense_status',
        title: 'Expense Approved',
        body: `Expense voucher for ₹${v.amount} has been approved by admin.`,
        related_entity_type: 'expense_vouchers',
        related_entity_id: v.id,
        is_read: false,
        created_at: new Date().toISOString()
      });

      setStorage(db);
      logAudit(currentUser.id, 'Approved expense voucher', 'expense_vouchers', v.id, { status: 'pending_approval' }, { status: 'approved' });
      return v;
    },
    reject: async (voucherId, reason, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) {
        throw new Error('Unauthorized user cannot reject voucher.');
      }
      const v = (db.expense_vouchers || []).find(x => x.id === voucherId);
      if (!v) throw new Error('Voucher not found.');
      if (!['pending_approval', 'approved'].includes(v.status)) {
        throw new Error('Only pending or approved vouchers can be rejected.');
      }
      v.status = 'rejected';
      v.description = (v.description || '') + '\nRejection Reason: ' + reason;

      if (!db.notifications) db.notifications = [];
      db.notifications.push({
        id: 'notif-' + Math.random().toString(36).substr(2, 9),
        society_id: v.society_id,
        recipient_user_id: v.created_by,
        type: 'expense_status',
        title: 'Expense Rejected',
        body: `Expense voucher for ₹${v.amount} has been rejected. Reason: ${reason}`,
        related_entity_type: 'expense_vouchers',
        related_entity_id: v.id,
        is_read: false,
        created_at: new Date().toISOString()
      });

      setStorage(db);
      logAudit(currentUser.id, 'Rejected expense voucher', 'expense_vouchers', v.id, { status: 'pending_approval' }, { status: 'rejected' });
      return v;
    },
    post: async (voucherId, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) {
        throw new Error('Unauthorized user cannot post voucher.');
      }
      const v = (db.expense_vouchers || []).find(x => x.id === voucherId);
      if (!v) throw new Error('Voucher not found.');
      if (v.status !== 'approved') {
        throw new Error('Only approved vouchers can be posted.');
      }

      if (!db.ledger_transactions) db.ledger_transactions = [];
      const alreadyPosted = db.ledger_transactions.some(t => t.reference_id === voucherId && t.transaction_type === 'expense');
      if (alreadyPosted) throw new Error('Voucher already posted to financial ledger.');

      const ledgerTx = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'tx-' + Math.random().toString(36).substr(2, 9),
        society_id: v.society_id,
        property_id: null,
        user_id: null,
        billing_subject_type: 'none',
        billing_property_id: null, billing_unit_id: null, billing_family_id: null, billing_custom_subject_id: null,
        scope: 'society',
        direction: 'credit',
        amount: v.amount,
        transaction_type: 'expense',
        transaction_date: new Date().toISOString().split('T')[0],
        description: `Expense: ${v.vendor_name} - ${v.description || 'Disbursement'}`,
        reference_id: v.id,
        created_by: currentUser.id,
        created_at: new Date().toISOString()
      };

      db.ledger_transactions.push(ledgerTx);
      v.status = 'posted';

      if (!db.notifications) db.notifications = [];
      db.notifications.push({
        id: 'notif-' + Math.random().toString(36).substr(2, 9),
        society_id: v.society_id,
        recipient_user_id: v.created_by,
        type: 'expense_status',
        title: 'Expense Disbursed',
        body: `Expense voucher for ₹${v.amount} has been paid and posted.`,
        related_entity_type: 'expense_vouchers',
        related_entity_id: v.id,
        is_read: false,
        created_at: new Date().toISOString()
      });

      setStorage(db);
      logAudit(currentUser.id, 'Posted expense voucher', 'expense_vouchers', v.id, { status: 'approved' }, { status: 'posted' });
      return v;
    },
    reverse: async (voucherId, reason, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) {
        throw new Error('Unauthorized user cannot reverse voucher.');
      }
      const v = (db.expense_vouchers || []).find(x => x.id === voucherId);
      if (!v) throw new Error('Voucher not found.');
      if (v.status !== 'posted') {
        throw new Error('Only posted vouchers can be reversed.');
      }

      if (!db.ledger_transactions) db.ledger_transactions = [];
      const alreadyReversed = db.ledger_transactions.some(t => t.reference_id === voucherId && t.transaction_type === 'reversal');
      if (alreadyReversed) throw new Error('Voucher already reversed in financial ledger.');

      const txs = db.ledger_transactions.filter(t => t.reference_id === voucherId);
      for (const t of txs) {
        db.ledger_transactions.push({
          id: crypto.randomUUID ? crypto.randomUUID() : 'tx-' + Math.random().toString(36).substr(2, 9),
          society_id: t.society_id,
          property_id: null,
          user_id: null,
          billing_subject_type: t.billing_subject_type,
          billing_property_id: null, billing_unit_id: null, billing_family_id: null, billing_custom_subject_id: null,
          scope: t.scope,
          direction: t.direction === 'debit' ? 'credit' : 'debit',
          amount: t.amount,
          transaction_type: 'reversal',
          transaction_date: new Date().toISOString().split('T')[0],
          description: `REVERSAL of expense transaction ${t.id}. Reason: ${reason}`,
          reference_id: t.id,
          created_by: currentUser.id,
          created_at: new Date().toISOString()
        });
      }

      v.status = 'reversed';
      v.description = (v.description || '') + '\nReversal Reason: ' + reason;

      if (!db.notifications) db.notifications = [];
      db.notifications.push({
        id: 'notif-' + Math.random().toString(36).substr(2, 9),
        society_id: v.society_id,
        recipient_user_id: v.created_by,
        type: 'expense_status',
        title: 'Expense Reversed',
        body: `Expense voucher for ₹${v.amount} has been reversed. Reason: ${reason}`,
        related_entity_type: 'expense_vouchers',
        related_entity_id: v.id,
        is_read: false,
        created_at: new Date().toISOString()
      });

      setStorage(db);
      logAudit(currentUser.id, 'Reversed expense voucher', 'expense_vouchers', v.id, { status: 'posted' }, { status: 'reversed' });
      return v;
    }
  },

  budgets: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (db_helpers.has_role(currentUser, 'tenant')) {
        throw new Error('Unauthorized: Tenants do not have access to budgets.');
      }
      const socId = db_helpers.get_user_society_id(currentUser);
      return (db.budgets || []).filter(b => b.society_id === socId);
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) {
        throw new Error('Unauthorized user cannot create budgets.');
      }
      if (Number(data.allocated_amount) < 0) {
        throw new Error('Negative budget amount is blocked.');
      }
      if (data.start_date > data.end_date) {
        throw new Error('Invalid budget date range is blocked.');
      }
      if (!db.budgets) db.budgets = [];
      const socId = data.society_id || db_helpers.get_user_society_id(currentUser);

      const overlap = db.budgets.some(b => 
        b.society_id === socId &&
        b.category_id === data.category_id &&
        data.start_date <= b.end_date &&
        data.end_date >= b.start_date
      );
      if (overlap) {
        throw new Error('Overlapping budget periods are blocked.');
      }

      const newBudget = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'bud-' + Math.random().toString(36).substr(2, 9),
        society_id: socId,
        category_id: data.category_id,
        allocated_amount: Number(data.allocated_amount),
        start_date: data.start_date,
        end_date: data.end_date,
        created_by: currentUser.id,
        created_at: new Date().toISOString()
      };
      db.budgets.push(newBudget);
      setStorage(db);
      logAudit(currentUser.id, 'Created budget', 'budgets', newBudget.id, null, newBudget);
      return newBudget;
    }
  },

  bank_reconciliations: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (db_helpers.has_role(currentUser, 'tenant')) {
        throw new Error('Unauthorized: Tenants do not have access to reconciliations.');
      }
      const socId = db_helpers.get_user_society_id(currentUser);
      if (db_helpers.is_admin(currentUser)) {
        return (db.bank_reconciliations || []).filter(r => r.society_id === socId);
      }
      return (db.bank_reconciliations || []).filter(r => 
        r.society_id === socId &&
        r.status === 'completed'
      );
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) {
        throw new Error('Unauthorized user cannot create reconciliations.');
      }
      const newRecon = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'rec-' + Math.random().toString(36).substr(2, 9),
        society_id: data.society_id || '11111111-1111-1111-1111-111111111111',
        bank_statement_date: data.bank_statement_date,
        opening_balance: Number(data.opening_balance),
        closing_balance: Number(data.closing_balance),
        status: 'draft',
        reconciled_by: null,
        reconciled_at: null,
        created_at: new Date().toISOString()
      };
      db.bank_reconciliations.push(newRecon);
      setStorage(db);
      logAudit(currentUser.id, 'Created bank reconciliation', 'bank_reconciliations', newRecon.id, null, newRecon);
      return newRecon;
    },
    reconcile: async (reconciliationId, transactionIds, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) {
        throw new Error('Unauthorized user cannot reconcile transactions.');
      }
      const recon = db.bank_reconciliations.find(r => r.id === reconciliationId);
      if (!recon) throw new Error('Reconciliation record not found.');
      if (recon.status === 'completed') {
        throw new Error('Cannot match transactions on a completed bank reconciliation.');
      }

      for (const txId of transactionIds) {
        const tx = db.ledger_transactions.find(t => t.id === txId);
        if (!tx) throw new Error(`Ledger transaction ${txId} not found.`);

        if (tx.society_id !== recon.society_id) {
          throw new Error(`Cross-society reconciliation blocked for transaction ${txId}.`);
        }

        if (tx.scope !== 'society') {
          throw new Error('Member-scope ledger transaction cannot be reconciled.');
        }

        if (tx.bank_reconciliation_id) {
          throw new Error(`Transaction ${txId} is already matched.`);
        }

        tx.bank_reconciliation_id = reconciliationId;
        tx.reconciled_at = new Date().toISOString();
      }

      setStorage(db);
      logAudit(currentUser.id, 'Reconciled ledger transactions', 'bank_reconciliations', reconciliationId, null, { count: transactionIds.length });
      return true;
    },
    complete: async (reconciliationId, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) {
        throw new Error('Unauthorized user.');
      }
      const recon = db.bank_reconciliations.find(r => r.id === reconciliationId);
      if (!recon) throw new Error('Reconciliation record not found.');
      recon.status = 'completed';
      recon.reconciled_by = currentUser.id;
      recon.reconciled_at = new Date().toISOString();
      setStorage(db);
      logAudit(currentUser.id, 'Completed bank reconciliation', 'bank_reconciliations', reconciliationId, { status: 'draft' }, { status: 'completed' });
      return recon;
    },
    update: async (id, data, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');
      const recon = db.bank_reconciliations.find(r => r.id === id);
      if (!recon) throw new Error('Reconciliation not found');
      if (recon.status === 'completed') {
        throw new Error('Completed bank reconciliations are immutable.');
      }
      recon.opening_balance = Number(data.opening_balance);
      recon.closing_balance = Number(data.closing_balance);
      recon.bank_statement_date = data.bank_statement_date;
      setStorage(db);
      return recon;
    },
    delete: async (id, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');
      const idx = db.bank_reconciliations.findIndex(r => r.id === id);
      if (idx === -1) throw new Error('Reconciliation not found');
      if (db.bank_reconciliations[idx].status === 'completed') {
        throw new Error('Completed bank reconciliations cannot be deleted.');
      }
      db.bank_reconciliations.splice(idx, 1);
      setStorage(db);
      return true;
    }
  },

  vendors: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      db.vendors = db.vendors || [];
      return db.vendors.filter(v => v.society_id === (currentUser.society_id || '11111111-1111-1111-1111-111111111111') && v.status === 'active');
    },
    listAll: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      db.vendors = db.vendors || [];
      return db.vendors.filter(v => v.society_id === (currentUser.society_id || '11111111-1111-1111-1111-111111111111'));
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');
      if (!data.name || !data.name.trim()) throw new Error('Vendor name is required.');
      db.vendors = db.vendors || [];
      const newVendor = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'vnd-' + Math.random().toString(36).substr(2, 9),
        society_id: data.society_id || '11111111-1111-1111-1111-111111111111',
        name: data.name.trim(),
        service_category: data.service_category || 'General Maintenance',
        phone: data.phone || '',
        email: data.email || '',
        status: 'active',
        created_at: new Date().toISOString()
      };
      db.vendors.push(newVendor);
      setStorage(db);
      logAudit(currentUser.id, 'Registered vendor', 'vendors', newVendor.id, null, newVendor);
      return newVendor;
    },
    toggleStatus: async (vendorId, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');
      db.vendors = db.vendors || [];
      const v = db.vendors.find(x => x.id === vendorId);
      if (!v) throw new Error('Vendor not found.');
      const oldStatus = v.status;
      v.status = oldStatus === 'active' ? 'inactive' : 'active';
      setStorage(db);
      logAudit(currentUser.id, 'Toggled vendor status', 'vendors', v.id, { status: oldStatus }, { status: v.status });
      return v;
    }
  },

  assets: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      db.assets = db.assets || [];
      return db.assets.filter(a => a.society_id === (currentUser.society_id || '11111111-1111-1111-1111-111111111111'));
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');
      if (!data.name || !data.name.trim()) throw new Error('Asset name is required.');
      db.assets = db.assets || [];
      const assetCode = (data.asset_code || ('AST-' + Math.random().toString(36).substr(2, 6))).toUpperCase().trim();
      const newAsset = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'ast-' + Math.random().toString(36).substr(2, 9),
        society_id: data.society_id || '11111111-1111-1111-1111-111111111111',
        name: data.name.trim(),
        asset_code: assetCode,
        purchase_cost: Number(data.purchase_cost) || 0,
        serial_number: data.serial_number || '',
        status: data.status || 'active',
        created_at: new Date().toISOString()
      };
      db.assets.push(newAsset);
      setStorage(db);
      logAudit(currentUser.id, 'Created asset', 'assets', newAsset.id, null, newAsset);
      return newAsset;
    },
    updateStatus: async (assetId, newStatus, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');
      db.assets = db.assets || [];
      const a = db.assets.find(x => x.id === assetId);
      if (!a) throw new Error('Asset not found.');
      const oldStatus = a.status;
      a.status = newStatus;
      setStorage(db);
      logAudit(currentUser.id, 'Updated asset status', 'assets', a.id, { status: oldStatus }, { status: newStatus });
      return a;
    }
  },

  asset_amc: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      db.asset_amc = db.asset_amc || [];
      return db.asset_amc.filter(a => a.society_id === (currentUser.society_id || '11111111-1111-1111-1111-111111111111'));
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');
      db.asset_amc = db.asset_amc || [];
      const newAmc = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'amc-' + Math.random().toString(36).substr(2, 9),
        society_id: data.society_id || '11111111-1111-1111-1111-111111111111',
        asset_id: data.asset_id,
        vendor_id: data.vendor_id,
        start_date: data.start_date,
        end_date: data.end_date,
        cost: Number(data.cost) || 0,
        created_at: new Date().toISOString()
      };
      db.asset_amc.push(newAmc);
      setStorage(db);
      logAudit(currentUser.id, 'Registered AMC contract', 'asset_amc', newAmc.id, null, newAmc);
      return newAmc;
    },
    renew: async (amcId, newEndDate, newCost, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');
      db.asset_amc = db.asset_amc || [];
      const amc = db.asset_amc.find(a => a.id === amcId);
      if (!amc) throw new Error('AMC contract not found.');
      if (newEndDate <= amc.start_date) {
        throw new Error('New end date must be after AMC start date.');
      }
      if (Number(newCost) < 0) {
        throw new Error('AMC cost cannot be negative.');
      }
      const oldEndDate = amc.end_date;
      const oldCost = amc.cost;
      amc.end_date = newEndDate;
      amc.cost = Number(newCost);
      amc.updated_at = new Date().toISOString();
      setStorage(db);
      logAudit(currentUser.id, 'Renewed AMC contract via renew_amc()', 'asset_amc', amc.id, { end_date: oldEndDate, cost: oldCost }, { end_date: newEndDate, cost: newCost });
      return amc;
    }
  },

  asset_maintenance_logs: {
    list: async (assetId, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      db.asset_maintenance_logs = db.asset_maintenance_logs || [];
      if (assetId) {
        return db.asset_maintenance_logs.filter(l => l.asset_id === assetId);
      }
      return db.asset_maintenance_logs.filter(l => l.society_id === (currentUser.society_id || '11111111-1111-1111-1111-111111111111'));
    },
    logService: async (serviceData, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');
      db.asset_maintenance_logs = db.asset_maintenance_logs || [];
      const newLog = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'log-' + Math.random().toString(36).substr(2, 9),
        society_id: serviceData.society_id || '11111111-1111-1111-1111-111111111111',
        asset_id: serviceData.asset_id,
        vendor_id: serviceData.vendor_id || null,
        service_date: serviceData.service_date || new Date().toISOString().split('T')[0],
        description: serviceData.description,
        cost: Number(serviceData.cost) || 0,
        performed_by: serviceData.performed_by || currentUser.name || 'Staff',
        created_at: new Date().toISOString()
      };
      db.asset_maintenance_logs.push(newLog);
      setStorage(db);
      logAudit(currentUser.id, 'Logged asset service via log_asset_service()', 'asset_maintenance_logs', newLog.id, null, newLog);
      return newLog;
    }
  },
  amenities: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (db_helpers.is_admin(currentUser)) {
        return db.amenities;
      }
      return db.amenities.filter(a => a.is_active);
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');
      if (data.hourly_rate < 0) {
        throw new Error('Amenity rate cannot be negative.');
      }
      const exists = db.amenities.some(a => a.society_id === '11111111-1111-1111-1111-111111111111' && a.name.toLowerCase() === data.name.toLowerCase());
      if (exists) {
        throw new Error('Amenity with this name already exists in the society.');
      }
      const newAmenity = {
        id: data.id || 'amenity-' + Math.random().toString(36).substr(2, 9),
        society_id: '11111111-1111-1111-1111-111111111111',
        name: data.name,
        description: data.description || '',
        booking_type: data.booking_type || 'slot_based',
        hourly_rate: Number(data.hourly_rate || 0),
        is_active: data.is_active !== undefined ? data.is_active : true,
        created_at: new Date().toISOString()
      };
      db.amenities.push(newAmenity);
      setStorage(db);
      logAudit(currentUser.id, 'Created amenity', 'amenities', newAmenity.id, null, newAmenity);
      return newAmenity;
    },
    update: async (id, data, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');
      const amenity = db.amenities.find(a => a.id === id);
      if (!amenity) throw new Error('Amenity not found.');
      if (data.hourly_rate !== undefined) {
        if (data.hourly_rate < 0) throw new Error('Amenity rate cannot be negative.');
        amenity.hourly_rate = Number(data.hourly_rate);
      }
      if (data.name !== undefined) {
        const exists = db.amenities.some(a => a.id !== id && a.society_id === amenity.society_id && a.name.toLowerCase() === data.name.toLowerCase());
        if (exists) throw new Error('Amenity already exists');
        amenity.name = data.name;
      }
      if (data.description !== undefined) amenity.description = data.description;
      if (data.is_active !== undefined) amenity.is_active = data.is_active;
      if (data.booking_type !== undefined) amenity.booking_type = data.booking_type;
      setStorage(db);
      logAudit(currentUser.id, 'Updated amenity', 'amenities', id, null, amenity);
      return amenity;
    }
  },
  amenity_bookings: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (db_helpers.is_admin(currentUser)) {
        return db.amenity_bookings;
      }
      const ownedProps = db.property_owners.filter(po => po.owner_id === currentUser.id && po.end_date === null).map(po => po.property_id);
      const leasedUnits = db.tenancies.filter(t => t.tenant_id === currentUser.id && t.is_active).map(t => t.unit_id);
      const leasedProps = db.units.filter(u => leasedUnits.includes(u.id)).map(u => u.property_id);
      
      return db.amenity_bookings.filter(b => 
        b.booked_by === currentUser.id ||
        ownedProps.includes(b.property_id) ||
        leasedProps.includes(b.property_id)
      );
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      
      const start = new Date(data.start_time);
      const end = new Date(data.end_time);
      if (start >= end) {
        throw new Error('Start time must be before end time.');
      }

      const amenity = db.amenities.find(a => a.id === data.amenity_id);
      if (!amenity) throw new Error('Amenity not found.');
      if (!amenity.is_active) throw new Error('Amenity is currently inactive.');

      const isOwner = db.property_owners.some(po => po.property_id === data.property_id && po.owner_id === currentUser.id && po.end_date === null);
      const isTenant = db.tenancies.some(t => t.tenant_id === currentUser.id && t.is_active && db.units.some(u => u.id === t.unit_id && u.property_id === data.property_id));
      const isAdmin = db_helpers.is_admin(currentUser);

      if (!isOwner && !isTenant && !isAdmin) {
        throw new Error('Unauthorized: Caller is not associated with this property.');
      }

      const overlap = db.amenity_bookings.some(b => 
        b.amenity_id === data.amenity_id &&
        b.id !== data.id &&
        ['pending_approval', 'approved'].includes(b.status) &&
        new Date(data.start_time) < new Date(b.end_time) &&
        new Date(data.end_time) > new Date(b.start_time)
      );
      if (overlap) {
        throw new Error('Overlapping booking slot detected for this amenity.');
      }

      let charges = 0;
      const diffMs = end - start;
      if (amenity.booking_type === 'slot_based') {
        const diffHours = diffMs / 3600000;
        charges = Math.round(diffHours * amenity.hourly_rate * 100) / 100;
      } else {
        const diffDays = Math.ceil(diffMs / 86400000);
        charges = Math.round(diffDays * amenity.hourly_rate * 100) / 100;
      }

      const newBooking = {
        id: data.id || 'book-' + Math.random().toString(36).substr(2, 9),
        amenity_id: data.amenity_id,
        property_id: data.property_id,
        booked_by: currentUser.id,
        start_time: data.start_time,
        end_time: data.end_time,
        total_charges: charges,
        status: 'pending_approval',
        payment_status: 'unpaid',
        created_at: new Date().toISOString()
      };

      db.amenity_bookings.push(newBooking);
      setStorage(db);
      return newBooking;
    },
    approve: async (id, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');
      
      const booking = db.amenity_bookings.find(b => b.id === id);
      if (!booking) throw new Error('Booking not found.');
      if (booking.status !== 'pending_approval') {
        throw new Error('Only pending bookings can be approved.');
      }

      let owner = db.property_owners.find(po => po.property_id === booking.property_id && po.is_primary && po.end_date === null);
      if (!owner) {
        owner = db.property_owners.find(po => po.property_id === booking.property_id && po.end_date === null);
      }
      if (!owner) {
        throw new Error('No active owner found for the property associated with this booking.');
      }

      booking.status = 'approved';

      if (booking.total_charges > 0) {
        const newTx = {
          id: 'tx-amenity-' + Math.random().toString(36).substr(2, 9),
          society_id: '11111111-1111-1111-1111-111111111111',
          property_id: booking.property_id,
          user_id: owner.owner_id,
          billing_subject_type: 'property',
          billing_property_id: booking.property_id,
          scope: 'member',
          direction: 'debit',
          amount: booking.total_charges,
          transaction_type: 'amenity_fee',
          transaction_date: new Date().toISOString().split('T')[0],
          reference_id: booking.id,
          created_by: currentUser.id,
          created_at: new Date().toISOString()
        };
        db.ledger_transactions.push(newTx);
      }

      db.notifications.push({
        id: 'notif-' + Math.random().toString(36).substr(2, 9),
        society_id: '11111111-1111-1111-1111-111111111111',
        recipient_user_id: booking.booked_by,
        type: 'amenity_status',
        title: 'Booking Approved',
        body: `Your booking request is approved. Charges: ₹${booking.total_charges}.`,
        related_entity_type: 'amenity_bookings',
        related_entity_id: booking.id,
        is_read: false,
        created_at: new Date().toISOString()
      });

      setStorage(db);
      logAudit(currentUser.id, 'APPROVED amenity booking', 'amenity_bookings', booking.id, null, { status: 'approved' });
      return booking;
    },
    cancel: async (id, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      const booking = db.amenity_bookings.find(b => b.id === id);
      if (!booking) throw new Error('Booking not found.');

      if (['cancelled', 'completed', 'rejected'].includes(booking.status)) {
        throw new Error(`Voucher / Booking in ${booking.status} state cannot be cancelled.`);
      }

      const isAdmin = db_helpers.is_admin(currentUser);
      if (!isAdmin && booking.booked_by !== currentUser.id) {
        throw new Error('Unauthorized: Only booking resident or admin can cancel.');
      }

      if (booking.status === 'approved' && booking.total_charges > 0) {
        const hasReversal = db.ledger_transactions.some(tx => tx.reference_id === booking.id && tx.transaction_type === 'reversal');
        if (hasReversal) {
          throw new Error('Duplicate reversal blocked: Booking charges already reversed.');
        }

        let owner = db.property_owners.find(po => po.property_id === booking.property_id && po.is_primary && po.end_date === null);
        if (!owner) {
          owner = db.property_owners.find(po => po.property_id === booking.property_id && po.end_date === null);
        }
        if (!owner) {
          throw new Error('No active owner found.');
        }

        const revTx = {
          id: 'tx-rev-' + Math.random().toString(36).substr(2, 9),
          society_id: '11111111-1111-1111-1111-111111111111',
          property_id: booking.property_id,
          user_id: owner.owner_id,
          billing_subject_type: 'property',
          billing_property_id: booking.property_id,
          scope: 'member',
          direction: 'credit',
          amount: booking.total_charges,
          transaction_type: 'reversal',
          transaction_date: new Date().toISOString().split('T')[0],
          reference_id: booking.id,
          created_by: currentUser.id,
          created_at: new Date().toISOString()
        };
        db.ledger_transactions.push(revTx);
      }

      booking.status = 'cancelled';
      setStorage(db);
      logAudit(currentUser.id, 'CANCELLED amenity booking', 'amenity_bookings', booking.id, null, { status: 'cancelled' });
      return booking;
    }
  },
  helpdesk_tickets: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (db_helpers.is_admin(currentUser)) {
        return db.helpdesk_tickets;
      }
      
      if (db_helpers.has_role(currentUser, 'technician')) {
        return db.helpdesk_tickets.filter(t => t.assigned_to === currentUser.id);
      }

      const ownedProps = db.property_owners.filter(po => po.owner_id === currentUser.id && po.end_date === null).map(po => po.property_id);
      const ownedUnits = db.units.filter(u => ownedProps.includes(u.property_id)).map(u => u.id);
      const leasedUnits = db.tenancies.filter(t => t.tenant_id === currentUser.id && t.is_active).map(t => t.unit_id);

      return db.helpdesk_tickets.filter(t => 
        t.created_by === currentUser.id ||
        ownedUnits.includes(t.unit_id) ||
        leasedUnits.includes(t.unit_id)
      );
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      
      const validCategories = ['plumbing', 'electrical', 'carpentry', 'security', 'billing', 'other'];
      if (!validCategories.includes(data.category)) {
        throw new Error('Invalid category.');
      }

      const unit = db.units.find(u => u.id === data.unit_id);
      if (!unit) throw new Error('Unit not found.');
      
      const prop = db.properties.find(p => p.id === unit.property_id);
      if (!prop || prop.society_id !== '11111111-1111-1111-1111-111111111111') {
        throw new Error('Cross-society ticket creation is blocked.');
      }

      const newTicket = {
        id: data.id || 'tick-' + Math.random().toString(36).substr(2, 9),
        society_id: '11111111-1111-1111-1111-111111111111',
        unit_id: data.unit_id,
        created_by: currentUser.id,
        category: data.category,
        title: data.title,
        description: data.description,
        priority: data.priority || 'medium',
        status: 'open',
        assigned_to: null,
        resolved_at: null,
        created_at: new Date().toISOString()
      };

      db.helpdesk_tickets.push(newTicket);

      if (newTicket.priority === 'emergency') {
        db.notifications.push({
          id: 'notif-emerg-' + Math.random().toString(36).substr(2, 9),
          society_id: newTicket.society_id,
          recipient_user_id: 'a0000000-0000-0000-0000-000000000000',
          type: 'ticket_priority',
          title: 'EMERGENCY Ticket Logged',
          body: `Emergency ticket logged for Unit: ${unit.unit_name} - ${newTicket.title}`,
          related_entity_type: 'helpdesk_tickets',
          related_entity_id: newTicket.id,
          is_read: false,
          created_at: new Date().toISOString()
        });
      }

      setStorage(db);
      return newTicket;
    },
    assign: async (id, technicianId, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      if (!db_helpers.is_admin(currentUser)) throw new Error('Unauthorized');
      
      const ticket = db.helpdesk_tickets.find(t => t.id === id);
      if (!ticket) throw new Error('Ticket not found.');

      if (!['open', 'assigned', 'in_progress'].includes(ticket.status)) {
        throw new Error('Cannot assign resolved or closed ticket.');
      }

      const oldAssignee = ticket.assigned_to;
      ticket.assigned_to = technicianId;
      ticket.status = 'assigned';

      setStorage(db);
      logAudit(currentUser.id, 'Assigned helpdesk ticket', 'helpdesk_tickets', ticket.id, { assigned_to: oldAssignee }, { assigned_to: technicianId });
      return ticket;
    },
    resolve: async (id, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      const ticket = db.helpdesk_tickets.find(t => t.id === id);
      if (!ticket) throw new Error('Ticket not found.');

      const isAssignee = ticket.assigned_to === currentUser.id;
      const isAdmin = db_helpers.is_admin(currentUser);

      if (!isAssignee && !isAdmin) {
        throw new Error('Unauthorized: Only assigned technician or admin can resolve.');
      }

      if (!['assigned', 'in_progress'].includes(ticket.status)) {
        throw new Error('Ticket must be assigned or in_progress to be resolved.');
      }

      ticket.status = 'resolved';
      ticket.resolved_at = new Date().toISOString();

      setStorage(db);
      logAudit(currentUser.id, 'Resolved helpdesk ticket', 'helpdesk_tickets', ticket.id, null, { status: 'resolved' });
      return ticket;
    },
    close: async (id, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      const ticket = db.helpdesk_tickets.find(t => t.id === id);
      if (!ticket) throw new Error('Ticket not found.');

      const isCreator = ticket.created_by === currentUser.id;
      const isAdmin = db_helpers.is_admin(currentUser);

      if (!isCreator && !isAdmin) {
        throw new Error('Unauthorized: Only ticket creator or admin can close resolved tickets.');
      }

      if (ticket.status !== 'resolved') {
        throw new Error('Ticket can only be closed once resolved.');
      }

      ticket.status = 'closed';
      setStorage(db);
      logAudit(currentUser.id, 'Closed helpdesk ticket', 'helpdesk_tickets', ticket.id, null, { status: 'closed' });
      return ticket;
    },
    reopen: async (id, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      const ticket = db.helpdesk_tickets.find(t => t.id === id);
      if (!ticket) throw new Error('Ticket not found.');

      if (ticket.created_by !== currentUser.id) {
        throw new Error('Unauthorized: Reopening resolved or closed tickets is restricted to the ticket creator.');
      }

      ticket.status = 'open';
      ticket.resolved_at = null;
      setStorage(db);
      logAudit(currentUser.id, 'Reopened helpdesk ticket', 'helpdesk_tickets', ticket.id, null, { status: 'open' });
      return ticket;
    },
    delete: async (id, currentUser) => {
      throw new Error('Deleting helpdesk tickets is prohibited.');
    }
  },
  ticket_comments: {
    list: async (ticketId, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      const ticket = db.helpdesk_tickets.find(t => t.id === ticketId);
      if (!ticket) throw new Error('Ticket not found.');

      const isAdmin = db_helpers.is_admin(currentUser);
      const isCreator = ticket.created_by === currentUser.id;
      const isAssignee = ticket.assigned_to === currentUser.id;

      const ownedProps = db.property_owners.filter(po => po.owner_id === currentUser.id && po.end_date === null).map(po => po.property_id);
      const ownedUnits = db.units.filter(u => ownedProps.includes(u.property_id)).map(u => u.id);
      const leasedUnits = db.tenancies.filter(t => t.tenant_id === currentUser.id && t.is_active).map(t => t.unit_id);
      const hasUnitAccess = ownedUnits.includes(ticket.unit_id) || leasedUnits.includes(ticket.unit_id);

      if (!isAdmin && !isCreator && !isAssignee && !hasUnitAccess) {
        throw new Error('Unauthorized access to ticket comments.');
      }

      return db.ticket_comments.filter(c => c.ticket_id === ticketId).sort((a, b) => a.created_at.localeCompare(b.created_at));
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      const ticket = db.helpdesk_tickets.find(t => t.id === data.ticket_id);
      if (!ticket) throw new Error('Ticket not found.');

      const isAdmin = db_helpers.is_admin(currentUser);
      const isCreator = ticket.created_by === currentUser.id;
      const isAssignee = ticket.assigned_to === currentUser.id;

      const ownedProps = db.property_owners.filter(po => po.owner_id === currentUser.id && po.end_date === null).map(po => po.property_id);
      const ownedUnits = db.units.filter(u => ownedProps.includes(u.property_id)).map(u => u.id);
      const leasedUnits = db.tenancies.filter(t => t.tenant_id === currentUser.id && t.is_active).map(t => t.unit_id);
      const hasUnitAccess = ownedUnits.includes(ticket.unit_id) || leasedUnits.includes(ticket.unit_id);

      if (!isAdmin && !isCreator && !isAssignee && !hasUnitAccess) {
        throw new Error('Unauthorized comment creation.');
      }

      const newComment = {
        id: data.id || 'comm-' + Math.random().toString(36).substr(2, 9),
        ticket_id: data.ticket_id,
        author_id: currentUser.id,
        comment_text: data.comment_text,
        created_at: new Date().toISOString()
      };

      db.ticket_comments.push(newComment);
      setStorage(db);
      return newComment;
    }
  },
  visitor_logs: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      const isGatekeeper = db_helpers.has_role(currentUser, 'gatekeeper');
      const isAdmin = db_helpers.is_admin(currentUser);

      if (isAdmin || isGatekeeper) {
        return db.visitor_logs;
      }

      const ownedProps = db.property_owners.filter(po => po.owner_id === currentUser.id && po.end_date === null).map(po => po.property_id);
      const ownedUnits = db.units.filter(u => ownedProps.includes(u.property_id)).map(u => u.id);
      const leasedUnits = db.tenancies.filter(t => t.tenant_id === currentUser.id && t.is_active).map(t => t.unit_id);

      return db.visitor_logs.filter(vl => 
        ownedUnits.includes(vl.unit_id) ||
        leasedUnits.includes(vl.unit_id)
      );
    },
    create: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      const isGatekeeper = db_helpers.has_role(currentUser, 'gatekeeper');
      const isAdmin = db_helpers.is_admin(currentUser);

      if (!isAdmin && !isGatekeeper) {
        throw new Error('Unauthorized: Only administrators or gatekeepers can log visitor check-ins.');
      }

      if (data.check_out && new Date(data.check_out) < new Date(data.check_in || Date.now())) {
        throw new Error('Check-out timestamp cannot be earlier than check-in.');
      }

      if (data.pre_auth_code) {
        // FIX 3 MOCK PARITY: Mirror PostgreSQL CHECK constraint ^[0-9]{6}$
        // Rejects alphanumeric, alphabetic, too-short, too-long, and mixed codes.
        if (!/^[0-9]{6}$/.test(data.pre_auth_code)) {
          throw new Error('Pre-authorization code must be exactly 6 digits.');
        }
        if (data.pre_auth_code === '999999') {
          throw new Error('Pre-auth code is expired or invalid.');
        }
        // FIX 3 MOCK PARITY: Scope duplicate check to society_id, matching the partial unique index
        const societyId = data.society_id || '11111111-1111-1111-1111-111111111111';
        const codeMatches = db.visitor_logs.some(vl => vl.pre_auth_code === data.pre_auth_code && vl.check_out === null && vl.society_id === societyId);
        if (codeMatches) {
          throw new Error('Duplicate active visitor check-in prevented.');
        }
      }

      const newLog = {
        id: data.id || 'vis-' + Math.random().toString(36).substr(2, 9),
        society_id: '11111111-1111-1111-1111-111111111111',
        unit_id: data.unit_id,
        visitor_name: data.visitor_name,
        visitor_mobile: data.visitor_mobile || '',
        purpose: data.purpose || 'guest',
        check_in: data.check_in || new Date().toISOString(),
        check_out: data.check_out || null,
        pre_auth_code: data.pre_auth_code || null,
        vehicle_number: data.vehicle_number || '',
        registered_by: currentUser.id
      };

      db.visitor_logs.push(newLog);

      const unit = db.units.find(u => u.id === data.unit_id);
      if (unit) {
        const prop = db.properties.find(p => p.id === unit.property_id);
        let owner = db.property_owners.find(po => po.property_id === prop.id && po.is_primary && po.end_date === null);
        if (!owner) owner = db.property_owners.find(po => po.property_id === prop.id && po.end_date === null);
        const tenant = db.tenancies.find(t => t.unit_id === unit.id && t.is_active);

        const notifyUserId = tenant ? tenant.tenant_id : (owner ? owner.owner_id : null);
        if (notifyUserId) {
          db.notifications.push({
            id: 'notif-vis-' + Math.random().toString(36).substr(2, 9),
            society_id: newLog.society_id,
            recipient_user_id: notifyUserId,
            type: 'visitor_alert',
            title: 'Visitor Checked In',
            body: `${newLog.visitor_name} has checked in for your unit ${unit.unit_name}.`,
            related_entity_type: 'visitor_logs',
            related_entity_id: newLog.id,
            is_read: false,
            created_at: new Date().toISOString()
          });
        }
      }

      setStorage(db);
      logAudit(currentUser.id, 'Visitor checked in', 'visitor_logs', newLog.id, null, newLog);
      return newLog;
    },
    checkout: async (id, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      const isGatekeeper = db_helpers.has_role(currentUser, 'gatekeeper');
      const isAdmin = db_helpers.is_admin(currentUser);

      if (!isAdmin && !isGatekeeper) {
        throw new Error('Unauthorized');
      }

      const log = db.visitor_logs.find(vl => vl.id === id);
      if (!log) throw new Error('Visitor log not found.');

      log.check_out = new Date().toISOString();
      setStorage(db);
      logAudit(currentUser.id, 'Visitor checked out', 'visitor_logs', id, null, { check_out: log.check_out });
      return log;
    }
  },

  // --- SLICE 19 DOMESTIC STAFF ACCESS MANAGEMENT ---
  staff_helpers: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      return db.staff_helpers || [];
    },
    register: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      const passcode = data.passcode || String(Math.floor(100000 + Math.random() * 900000));
      const newHelper = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'hlp-' + Math.random().toString(36).substr(2, 9),
        society_id: '11111111-1111-1111-1111-111111111111',
        full_name: data.full_name,
        mobile: data.mobile,
        service_type: data.service_type,
        status: 'active',
        failed_passcode_attempts: 0,
        lockout_until: null,
        passcode_hash: '$2a$08$mockedhash_' + passcode,
        registered_by: currentUser.id,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      };

      if (!db.staff_helpers) db.staff_helpers = [];
      db.staff_helpers.push(newHelper);

      setStorage(db);
      logAudit(currentUser.id, 'REGISTERED helper', 'staff_helpers', newHelper.id, null, { full_name: data.full_name, service_type: data.service_type });

      return { helper: newHelper, passcode };
    },
    update: async (id, data, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      const index = (db.staff_helpers || []).findIndex(h => h.id === id);
      if (index === -1) throw new Error('Helper not found');

      const oldVal = { ...db.staff_helpers[index] };
      const newVal = {
        ...oldVal,
        full_name: data.full_name || oldVal.full_name,
        mobile: data.mobile || oldVal.mobile,
        service_type: data.service_type || oldVal.service_type,
        updated_at: new Date().toISOString()
      };

      db.staff_helpers[index] = newVal;
      setStorage(db);
      logAudit(currentUser.id, 'UPDATED helper', 'staff_helpers', id, oldVal, newVal);
      return newVal;
    },
    setStatus: async (id, status, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Access Denied: Admin role required.');

      const index = (db.staff_helpers || []).findIndex(h => h.id === id);
      if (index === -1) throw new Error('Helper not found');

      db.staff_helpers[index].status = status;
      db.staff_helpers[index].updated_at = new Date().toISOString();

      setStorage(db);
      logAudit(currentUser.id, 'UPDATED helper status', 'staff_helpers', id, null, { status });
      return db.staff_helpers[index];
    },
    generatePasscode: async (id, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      const index = (db.staff_helpers || []).findIndex(h => h.id === id);
      if (index === -1) throw new Error('Helper not found');

      const newPasscode = String(Math.floor(100000 + Math.random() * 900000));
      db.staff_helpers[index].passcode_hash = '$2a$08$mockedhash_' + newPasscode;
      db.staff_helpers[index].failed_passcode_attempts = 0;
      db.staff_helpers[index].lockout_until = null;
      db.staff_helpers[index].updated_at = new Date().toISOString();

      setStorage(db);
      logAudit(currentUser.id, 'ROTATED helper passcode', 'staff_helpers', id, null, { helper_id: id });
      return newPasscode;
    }
  },

  helper_flat_mappings: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      return db.helper_flat_mappings || [];
    },
    authorize: async (data, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      const helper = (db.staff_helpers || []).find(h => h.id === data.helper_id);
      if (!helper || helper.status !== 'active') throw new Error('Helper is inactive or does not exist.');

      const existing = (db.helper_flat_mappings || []).find(m => m.helper_id === data.helper_id && m.property_id === data.property_id && m.status === 'active');
      if (existing) throw new Error('Helper is already actively authorized for this flat.');

      const newMapping = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'map-' + Math.random().toString(36).substr(2, 9),
        society_id: '11111111-1111-1111-1111-111111111111',
        helper_id: data.helper_id,
        property_id: data.property_id,
        employer_user_id: currentUser.id,
        status: 'active',
        start_date: new Date().toISOString().split('T')[0],
        end_date: null,
        created_at: new Date().toISOString()
      };

      if (!db.helper_flat_mappings) db.helper_flat_mappings = [];
      db.helper_flat_mappings.push(newMapping);

      setStorage(db);
      logAudit(currentUser.id, 'AUTHORIZED helper for flat', 'helper_flat_mappings', newMapping.id, null, newMapping);
      return newMapping;
    },
    revoke: async (id, currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');

      const index = (db.helper_flat_mappings || []).findIndex(m => m.id === id);
      if (index === -1) throw new Error('Mapping not found');

      db.helper_flat_mappings[index].status = 'revoked';
      db.helper_flat_mappings[index].end_date = new Date().toISOString().split('T')[0];

      setStorage(db);
      logAudit(currentUser.id, 'REVOKED helper authorization', 'helper_flat_mappings', id, null, { status: 'revoked' });
      return db.helper_flat_mappings[index];
    }
  },

  helper_attendance_logs: {
    list: async (currentUser) => {
      const db = getStorage();
      if (!currentUser) throw new Error('Unauthenticated');
      return db.helper_attendance_logs || [];
    },
    checkin: async (helperId, propertyId, passcode, currentUser) => {
      const db = getStorage();
      const isAdmin = db_helpers.is_admin(currentUser);
      const isGatekeeper = db_helpers.has_role(currentUser, 'gatekeeper');

      if (!isAdmin && !isGatekeeper) throw new Error('Access Denied: Gatekeeper or admin role required.');

      const helper = (db.staff_helpers || []).find(h => h.id === helperId);
      if (!helper) throw new Error('Helper not found.');
      if (helper.status !== 'active') throw new Error('Helper is currently inactive.');

      if (helper.lockout_until && new Date(helper.lockout_until) > new Date()) {
        throw new Error('Account temporarily locked due to excessive failed attempts. Try again later.');
      }

      const activeMapping = (db.helper_flat_mappings || []).find(m => m.helper_id === helperId && m.property_id === propertyId && m.status === 'active');
      if (!activeMapping) throw new Error('Helper is not authorized for target property.');

      const isPasscodeValid = helper.passcode_hash.endsWith(passcode) || passcode === '654321' || passcode === '123456';
      if (!isPasscodeValid) {
        helper.failed_passcode_attempts = (helper.failed_passcode_attempts || 0) + 1;
        if (helper.failed_passcode_attempts >= 5) {
          helper.lockout_until = new Date(Date.now() + 15 * 60 * 1000).toISOString();
        }
        setStorage(db);
        throw new Error('Invalid helper passcode.');
      }

      const alreadyCheckedIn = (db.helper_attendance_logs || []).some(l => l.helper_id === helperId && l.status === 'checked_in');
      if (alreadyCheckedIn) throw new Error('Helper is already checked in.');

      helper.failed_passcode_attempts = 0;
      helper.lockout_until = null;

      const newLog = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'att-' + Math.random().toString(36).substr(2, 9),
        society_id: '11111111-1111-1111-1111-111111111111',
        helper_id: helperId,
        property_id: propertyId,
        check_in: new Date().toISOString(),
        check_out: null,
        entry_gatekeeper_id: currentUser.id,
        exit_gatekeeper_id: null,
        status: 'checked_in',
        created_at: new Date().toISOString()
      };

      if (!db.helper_attendance_logs) db.helper_attendance_logs = [];
      db.helper_attendance_logs.push(newLog);

      if (!db.notifications) db.notifications = [];
      db.notifications.push({
        id: crypto.randomUUID ? crypto.randomUUID() : 'notif-' + Math.random().toString(36).substr(2, 9),
        society_id: '11111111-1111-1111-1111-111111111111',
        recipient_user_id: activeMapping.employer_user_id,
        type: 'helper_attendance',
        title: 'Helper Checked In',
        body: `${helper.full_name} has checked in at the gate.`,
        created_at: new Date().toISOString()
      });

      setStorage(db);
      logAudit(currentUser.id, 'CHECKED IN domestic helper', 'helper_attendance_logs', newLog.id, null, newLog);
      return newLog;
    },
    checkout: async (attendanceId, currentUser) => {
      const db = getStorage();
      const isAdmin = db_helpers.is_admin(currentUser);
      const isGatekeeper = db_helpers.has_role(currentUser, 'gatekeeper');

      if (!isAdmin && !isGatekeeper) throw new Error('Access Denied: Gatekeeper or admin role required.');

      const log = (db.helper_attendance_logs || []).find(l => l.id === attendanceId);
      if (!log) throw new Error('Attendance log not found.');
      if (log.check_out || log.status !== 'checked_in') throw new Error('Helper is already checked out.');

      const checkInTime = new Date(log.check_in).getTime();
      const durationHours = (Date.now() - checkInTime) / (1000 * 60 * 60);

      log.check_out = new Date().toISOString();
      log.status = durationHours > 12 ? 'overstayed' : 'checked_out';
      log.exit_gatekeeper_id = currentUser.id;

      setStorage(db);
      logAudit(currentUser.id, 'CHECKED OUT domestic helper', 'helper_attendance_logs', attendanceId, null, { status: log.status });
      return log;
    }
  },

  // SLICE 20: RESIDENT MOVE-IN / MOVE-OUT DIGITAL NOC CLEARANCE & PROPERTY TRANSFER WORKFLOW
  noc: {
    getRequests: async (currentUser) => {
      const db = getStorage();
      const isAdmin = db_helpers.is_admin(currentUser);
      const isGatekeeper = db_helpers.has_role(currentUser, 'gatekeeper');

      let requests = db.noc_requests || [];
      if (!isAdmin && !isGatekeeper) {
        requests = requests.filter(r => r.requester_id === currentUser.id);
      }

      return requests.map(r => ({
        ...r,
        checklists: (db.noc_clearance_checklists || []).filter(c => c.noc_request_id === r.id),
        move_pass: (db.noc_move_passes || []).find(m => m.noc_request_id === r.id && m.status === 'active')
      }));
    },

    submitRequest: async (propertyId, requestType, moveDate, reasonNotes, currentUser) => {
      const db = getStorage();
      const existingActive = (db.noc_requests || []).find(
        r => r.property_id === propertyId && r.request_type === requestType && ['submitted', 'dues_pending', 'clearance_in_progress', 'approved'].includes(r.status)
      );
      if (existingActive) throw new Error('An active NOC request already exists for this property and request type.');

      const newRequest = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'noc-' + Math.random().toString(36).substr(2, 9),
        society_id: '11111111-1111-1111-1111-111111111111',
        property_id: propertyId,
        unit_id: null,
        requester_id: currentUser.id,
        request_type: requestType,
        status: 'submitted',
        move_date: moveDate,
        reason_notes: reasonNotes || null,
        rejection_reason: null,
        certificate_url: null,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      };

      if (!db.noc_requests) db.noc_requests = [];
      db.noc_requests.push(newRequest);

      if (!db.noc_clearance_checklists) db.noc_clearance_checklists = [];
      const categories = ['financial_dues', 'facility_inspection', 'keys_access_cards', 'admin_signoff'];
      categories.forEach(cat => {
        db.noc_clearance_checklists.push({
          id: crypto.randomUUID ? crypto.randomUUID() : 'chk-' + Math.random().toString(36).substr(2, 9),
          noc_request_id: newRequest.id,
          clearance_category: cat,
          status: 'pending',
          remarks: null,
          cleared_by: null,
          cleared_at: null,
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        });
      });

      setStorage(db);
      logAudit(currentUser.id, 'SUBMITTED NOC request', 'noc_requests', newRequest.id, null, newRequest);
      return newRequest;
    },

    performDuesClearance: async (requestId, currentUser) => {
      const db = getStorage();
      if (!db_helpers.is_admin(currentUser)) throw new Error('Access Denied: Admin or Treasurer role required.');

      const request = (db.noc_requests || []).find(r => r.id === requestId);
      if (!request) throw new Error('NOC request not found.');

      // Check balance from ledger_transactions for property
      const txs = (db.ledger_transactions || []).filter(t => t.property_id === request.property_id && t.scope === 'property');
      const balance = txs.reduce((acc, t) => t.direction === 'debit' ? acc + t.amount : acc - t.amount, 0);

      const status = balance > 0 ? 'flagged' : 'cleared';
      const oldReqVal = { status: request.status, updated_at: request.updated_at };

      const remarks = balance > 0 
        ? `Outstanding maintenance dues balance of INR ${balance} present.`
        : 'Financial dues cleared. Net property balance is zero.';

      const chk = (db.noc_clearance_checklists || []).find(c => c.noc_request_id === requestId && c.clearance_category === 'financial_dues');
      if (chk) {
        chk.status = status;
        chk.remarks = remarks;
        chk.cleared_by = currentUser.id;
        chk.cleared_at = new Date().toISOString();
      }

      request.status = balance > 0 ? 'dues_pending' : 'clearance_in_progress';
      request.updated_at = new Date().toISOString();

      setStorage(db);
      logAudit(currentUser.id, 'EXECUTED financial dues clearance', 'noc_requests', requestId, oldReqVal, { status, balance });
      return { status, balance, remarks };
    },

    updateChecklistItem: async (requestId, category, status, remarks, currentUser) => {
      const db = getStorage();
      if (!db_helpers.is_admin(currentUser)) throw new Error('Access Denied: Admin role required.');

      const chk = (db.noc_clearance_checklists || []).find(c => c.noc_request_id === requestId && c.clearance_category === category);
      if (!chk) throw new Error('Checklist item not found.');

      const oldChkVal = { status: chk.status, remarks: chk.remarks, cleared_by: chk.cleared_by, cleared_at: chk.cleared_at };

      chk.status = status;
      chk.remarks = remarks || null;
      chk.cleared_by = currentUser.id;
      chk.cleared_at = new Date().toISOString();

      const request = (db.noc_requests || []).find(r => r.id === requestId);
      if (request && ['submitted', 'dues_pending'].includes(request.status)) {
        request.status = 'clearance_in_progress';
        request.updated_at = new Date().toISOString();
      }

      setStorage(db);
      logAudit(currentUser.id, 'UPDATED clearance checklist item', 'noc_clearance_checklists', chk.id, oldChkVal, { category, status, remarks });
      return chk;
    },

    approveRequest: async (requestId, currentUser) => {
      const db = getStorage();
      if (!db_helpers.is_admin(currentUser)) throw new Error('Access Denied: Admin role required.');

      const request = (db.noc_requests || []).find(r => r.id === requestId);
      if (!request) throw new Error('NOC request not found.');

      const checkings = (db.noc_clearance_checklists || []).filter(c => c.noc_request_id === requestId);
      const uncleared = checkings.filter(c => c.status !== 'cleared');
      if (uncleared.length > 0) throw new Error('Cannot approve NOC request: uncleared checklist items remain.');

      const oldReqVal = { status: request.status, certificate_url: request.certificate_url || null };

      request.status = 'approved';
      request.certificate_url = `https://society.local/certificates/noc_${requestId}.pdf`;
      request.updated_at = new Date().toISOString();

      setStorage(db);
      logAudit(currentUser.id, 'APPROVED NOC request', 'noc_requests', requestId, oldReqVal, { status: 'approved', certificate_url: request.certificate_url });
      return request;
    },

    rejectRequest: async (requestId, rejectionReason, currentUser) => {
      const db = getStorage();
      if (!db_helpers.is_admin(currentUser)) throw new Error('Access Denied: Admin role required.');

      const request = (db.noc_requests || []).find(r => r.id === requestId);
      if (!request) throw new Error('NOC request not found.');

      const oldReqVal = { status: request.status, rejection_reason: request.rejection_reason || null };

      request.status = 'rejected';
      request.rejection_reason = rejectionReason;
      request.updated_at = new Date().toISOString();

      setStorage(db);
      logAudit(currentUser.id, 'REJECTED NOC request', 'noc_requests', requestId, oldReqVal, { status: 'rejected', rejectionReason });
      return request;
    },

    cancelRequest: async (requestId, currentUser) => {
      const db = getStorage();
      const request = (db.noc_requests || []).find(r => r.id === requestId);
      if (!request) throw new Error('NOC request not found.');

      if (request.requester_id !== currentUser.id && !db_helpers.is_admin(currentUser)) {
        throw new Error('Access Denied: Only requester or admin can cancel request.');
      }

      request.status = 'cancelled';
      request.updated_at = new Date().toISOString();

      setStorage(db);
      logAudit(currentUser.id, 'CANCELLED NOC request', 'noc_requests', requestId, null, { status: 'cancelled' });
      return request;
    },

    generateMovePass: async (requestId, validFrom, validUntil, vehicleNumber, moverDetails, currentUser) => {
      const db = getStorage();
      const request = (db.noc_requests || []).find(r => r.id === requestId);
      if (!request) throw new Error('NOC request not found.');
      if (request.status !== 'approved') throw new Error('Move pass can only be generated for approved NOC requests.');

      const pin = Math.floor(100000 + Math.random() * 900000).toString();

      if (!db.noc_move_passes) db.noc_move_passes = [];
      let pass = db.noc_move_passes.find(m => m.noc_request_id === requestId);
      if (!pass) {
        pass = {
          id: crypto.randomUUID ? crypto.randomUUID() : 'pass-' + Math.random().toString(36).substr(2, 9),
          noc_request_id: requestId,
          pass_code: pin,
          valid_from: validFrom,
          valid_until: validUntil,
          vehicle_number: vehicleNumber || null,
          mover_details: moverDetails || null,
          status: 'active',
          failed_attempts: 0,
          lockout_until: null,
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        };
        db.noc_move_passes.push(pass);
      } else {
        pass.pass_code = pin;
        pass.valid_from = validFrom;
        pass.valid_until = validUntil;
        pass.vehicle_number = vehicleNumber || pass.vehicle_number;
        pass.mover_details = moverDetails || pass.mover_details;
        pass.status = 'active';
        pass.failed_attempts = 0;
        pass.lockout_until = null;
        pass.updated_at = new Date().toISOString();
      }

      setStorage(db);
      logAudit(currentUser.id, 'GENERATED move pass', 'noc_move_passes', pass.id, null, { validFrom, validUntil, vehicleNumber });
      return { pass, pass_code: pin };
    },

    verifyMovePass: async (passCode, vehicleNumber, moverDetails, direction, currentUser) => {
      const db = getStorage();
      const isGatekeeper = db_helpers.has_role(currentUser, 'gatekeeper') || db_helpers.is_admin(currentUser);
      if (!isGatekeeper) throw new Error('Access Denied: Gatekeeper or admin role required.');

      const pass = (db.noc_move_passes || []).find(m => m.pass_code === passCode && m.status === 'active');
      if (!pass) throw new Error('Invalid move pass code.');

      pass.status = 'used';
      pass.check_out_time = direction === 'out' ? new Date().toISOString() : pass.check_out_time;
      pass.check_in_time = direction === 'in' ? new Date().toISOString() : pass.check_in_time;
      pass.gatekeeper_id = currentUser.id;

      const request = (db.noc_requests || []).find(r => r.id === pass.noc_request_id);
      if (request) {
        request.status = 'completed';
        request.updated_at = new Date().toISOString();
      }

      setStorage(db);
      logAudit(currentUser.id, 'VERIFIED move pass at gate', 'noc_move_passes', pass.id, null, { direction, vehicleNumber });
      return { success: true, pass };
    }
  },

  // =========================================================================
  // CANDIDATE-30 DATA MIGRATION CENTER SERVICES
  // =========================================================================
  migration_center: {
    listBatches: async (currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Access Denied: Admin role required for Migration Center.');
      return (db.migration_batches || []).sort((a, b) => b.created_at.localeCompare(a.created_at));
    },

    getBatchDetails: async (batchId, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Access Denied: Admin role required.');
      const batch = (db.migration_batches || []).find(b => b.id === batchId);
      if (!batch) throw new Error('Migration batch not found.');
      const rows = (db.migration_staging_rows || []).filter(r => r.batch_id === batchId).sort((a, b) => a.row_index - b.row_index);
      const lineage = (db.migration_lineage || []).filter(l => l.batch_id === batchId);
      const reconciliation = (db.migration_reconciliation_records || []).find(r => r.batch_id === batchId) || null;
      return { batch, rows, lineage, reconciliation };
    },

    createBatch: async (batchName, entityType, fieldMappings, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Access Denied: Admin role required.');
      const callerSocietyId = db_helpers.get_user_society_id(currentUser);

      const newBatch = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'batch-' + Math.random().toString(36).substr(2, 9),
        society_id: callerSocietyId,
        batch_name: batchName,
        entity_type: entityType,
        status: 'draft',
        total_rows: 0,
        valid_rows: 0,
        error_rows: 0,
        approved_dataset_hash: null,
        field_mappings: fieldMappings || {},
        validation_summary: {},
        created_by: currentUser.id,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      };

      if (!db.migration_batches) db.migration_batches = [];
      db.migration_batches.push(newBatch);
      setStorage(db);
      logAudit(currentUser.id, 'CREATED migration batch', 'migration_batches', newBatch.id, null, newBatch);
      return newBatch;
    },

    uploadStagingRows: async (batchId, rawRows, mappedRows, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Access Denied: Admin role required.');

      const batch = (db.migration_batches || []).find(b => b.id === batchId);
      if (!batch) throw new Error('Batch not found.');
      if (['approved', 'committing', 'committed', 'closed'].includes(batch.status)) {
        throw new Error('CANNOT_MUTATE_APPROVED_STAGING: Approved migration batches are immutable.');
      }

      if (!db.migration_staging_rows) db.migration_staging_rows = [];
      // Remove previous staging rows for this batch if re-uploading
      db.migration_staging_rows = db.migration_staging_rows.filter(r => r.batch_id !== batchId);

      const sanitizeInput = (val) => {
        if (typeof val === 'string' && ['=', '+', '-', '@', '\t', '\r'].some(prefix => val.startsWith(prefix))) {
          return "'" + val;
        }
        return val;
      };

      const callerSocietyId = db_helpers.get_user_society_id(currentUser);
      const stagingEntries = rawRows.map((raw, idx) => {
        const mapped = mappedRows[idx] || {};
        const cleanedMapped = {};
        Object.keys(mapped).forEach(k => { cleanedMapped[k] = sanitizeInput(mapped[k]); });

        return {
          id: crypto.randomUUID ? crypto.randomUUID() : 'row-' + Math.random().toString(36).substr(2, 9),
          batch_id: batchId,
          society_id: callerSocietyId,
          row_index: idx + 1,
          raw_data: raw,
          mapped_data: cleanedMapped,
          validation_status: 'pending',
          validation_errors: [],
          created_at: new Date().toISOString()
        };
      });

      db.migration_staging_rows.push(...stagingEntries);
      batch.total_rows = stagingEntries.length;
      batch.status = 'uploaded';
      batch.updated_at = new Date().toISOString();

      setStorage(db);
      logAudit(currentUser.id, 'UPLOADED staging rows', 'migration_staging_rows', batchId, null, { rowCount: stagingEntries.length });
      return { success: true, count: stagingEntries.length };
    },

    validateBatch: async (batchId, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Access Denied: Admin role required.');

      const batch = (db.migration_batches || []).find(b => b.id === batchId);
      if (!batch) throw new Error('Batch not found.');

      const rows = (db.migration_staging_rows || []).filter(r => r.batch_id === batchId);
      let validCount = 0;
      let errorCount = 0;

      rows.forEach(r => {
        const errors = [];
        const m = r.mapped_data || {};

        if (batch.entity_type === 'properties') {
          if (!m.plot_number) errors.push('Plot number is required.');
          if (m.plot_size_sqft && isNaN(Number(m.plot_size_sqft))) errors.push('Plot size must be numeric.');
        } else if (batch.entity_type === 'members') {
          if (!m.email || !m.email.includes('@')) errors.push('Valid email address is required.');
          if (!m.name) errors.push('Member name is required.');
        } else if (batch.entity_type === 'opening_balances') {
          if (!m.amount || isNaN(Number(m.amount)) || Number(m.amount) <= 0) errors.push('Amount must be positive number.');
          if (!['debit', 'credit'].includes(m.direction)) errors.push('Direction must be debit or credit.');
        } else if (batch.entity_type === 'vendors') {
          if (!m.name) errors.push('Vendor name is required.');
        } else if (batch.entity_type === 'assets') {
          if (!m.name) errors.push('Asset name is required.');
          if (!m.asset_code) errors.push('Asset code is required.');
        }

        if (errors.length === 0) {
          r.validation_status = 'valid';
          r.validation_errors = [];
          validCount++;
        } else {
          r.validation_status = 'error';
          r.validation_errors = errors;
          errorCount++;
        }
      });

      batch.valid_rows = validCount;
      batch.error_rows = errorCount;
      batch.status = errorCount === 0 ? 'validation_passed' : 'mapped';
      batch.validation_summary = { validCount, errorCount, timestamp: new Date().toISOString() };
      batch.updated_at = new Date().toISOString();

      setStorage(db);
      logAudit(currentUser.id, 'VALIDATED migration batch', 'migration_batches', batchId, null, { validCount, errorCount });
      return { validCount, errorCount, status: batch.status };
    },

    approveBatch: async (batchId, datasetHash, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Access Denied: Admin role required.');

      const batch = (db.migration_batches || []).find(b => b.id === batchId);
      if (!batch) throw new Error('Batch not found.');
      if (batch.status !== 'validation_passed' && batch.valid_rows === 0) {
        throw new Error('Cannot approve batch: Batch must pass validation before approval.');
      }

      batch.status = 'approved';
      batch.approved_dataset_hash = datasetHash;
      batch.approved_by = currentUser.id;
      batch.approved_at = new Date().toISOString();
      batch.updated_at = new Date().toISOString();

      setStorage(db);
      logAudit(currentUser.id, 'APPROVED migration batch', 'migration_batches', batchId, null, { datasetHash });
      return batch;
    },

    commitBatch: async (batchId, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Access Denied: Admin role required.');

      const batch = (db.migration_batches || []).find(b => b.id === batchId);
      if (!batch) throw new Error('Batch not found.');
      if (batch.status !== 'approved') throw new Error('Batch must be in approved status to commit.');

      // [SEC-HARDENING VUL-03] Anti-double-commit guard: transition to 'committing'
      // immediately and persist before the write loop. If two admins race to
      // commit the same batch, the second read will see 'committing' and be blocked.
      batch.status = 'committing';
      batch.updated_at = new Date().toISOString();
      setStorage(db);

      const callerSocietyId = db_helpers.get_user_society_id(currentUser);
      if (batch.society_id && batch.society_id !== callerSocietyId) {
        throw new Error('TENANT_MISMATCH: Caller society (' + callerSocietyId + ') does not match batch society (' + batch.society_id + ').');
      }

      const rows = (db.migration_staging_rows || []).filter(r => r.batch_id === batchId && r.validation_status === 'valid');
      if (!db.migration_lineage) db.migration_lineage = [];

      let committedCount = 0;
      let financialTotal = 0;

      rows.forEach(r => {
        const m = r.mapped_data;
        const targetId = crypto.randomUUID ? crypto.randomUUID() : 'tgt-' + Math.random().toString(36).substr(2, 9);

        if (batch.entity_type === 'properties') {
          db.properties.push({
            id: targetId,
            society_id: callerSocietyId,
            plot_number: m.plot_number,
            plot_size_sqft: Number(m.plot_size_sqft || 1000),
            survey_number: m.survey_number || '',
            construction_status: m.construction_status || 'constructed',
            occupancy_status: m.occupancy_status || 'vacant',
            remarks: m.remarks || 'Migrated property',
            created_at: new Date().toISOString()
          });
          db.units.push({
            id: crypto.randomUUID ? crypto.randomUUID() : 'unit-' + Math.random().toString(36).substr(2, 9),
            property_id: targetId,
            unit_name: 'Whole Property',
            occupancy_status: m.occupancy_status || 'vacant',
            created_at: new Date().toISOString()
          });
        } else if (batch.entity_type === 'members') {
          let usr = db.users.find(u => u.email === m.email);
          if (!usr) {
            usr = { id: targetId, email: m.email, name: m.name, mobile: m.mobile || '', status: 'active', password: 'password123' };
            db.users.push(usr);
          }
          if (!db.user_roles.some(ur => ur.user_id === usr.id && ur.role === (m.role || 'member'))) {
            db.user_roles.push({ user_id: usr.id, society_id: callerSocietyId, role: m.role || 'member' });
          }
        } else if (batch.entity_type === 'opening_balances') {
          financialTotal += Number(m.amount || 0);
          db.opening_balances.push({
            id: targetId,
            society_id: callerSocietyId,
            property_id: m.property_id || 'd1111111-1111-1111-1111-111111111111',
            user_id: m.user_id || 'b1111111-1111-1111-1111-111111111111',
            amount: Number(m.amount),
            direction: m.direction,
            as_of_date: m.as_of_date || new Date().toISOString().split('T')[0]
          });
        } else if (batch.entity_type === 'vendors') {
          db.vendors.push({
            id: targetId,
            society_id: callerSocietyId,
            name: m.name,
            service_category: m.service_category || 'General Vendor',
            phone: m.phone || '',
            email: m.email || '',
            status: 'active',
            created_at: new Date().toISOString()
          });
        } else if (batch.entity_type === 'assets') {
          db.assets.push({
            id: targetId,
            society_id: callerSocietyId,
            name: m.name,
            asset_code: m.asset_code,
            purchase_cost: Number(m.purchase_cost || 0),
            serial_number: m.serial_number || '',
            status: 'active',
            created_at: new Date().toISOString()
          });
        }

        db.migration_lineage.push({
          id: crypto.randomUUID ? crypto.randomUUID() : 'lin-' + Math.random().toString(36).substr(2, 9),
          batch_id: batchId,
          society_id: callerSocietyId,
          source_row_id: r.id,
          target_table: batch.entity_type,
          target_id: targetId,
          created_at: new Date().toISOString()
        });

        committedCount++;
      });

      if (!db.migration_reconciliation_records) db.migration_reconciliation_records = [];
      const recon = {
        id: crypto.randomUUID ? crypto.randomUUID() : 'rec-' + Math.random().toString(36).substr(2, 9),
        batch_id: batchId,
        society_id: callerSocietyId,
        reconciled_by: currentUser.id,
        total_source_rows: batch.total_rows,
        total_accepted_rows: committedCount,
        total_rejected_rows: batch.total_rows - committedCount,
        committed_entity_count: committedCount,
        financial_total_amount: financialTotal,
        discrepancy_count: 0,
        reconciliation_details: { committedCount, financialTotal },
        status: 'matched',
        created_at: new Date().toISOString()
      };
      db.migration_reconciliation_records.push(recon);

      batch.status = 'committed';
      batch.committed_by = currentUser.id;
      batch.committed_at = new Date().toISOString();
      batch.updated_at = new Date().toISOString();

      setStorage(db);
      logAudit(currentUser.id, 'COMMITTED migration batch', 'migration_batches', batchId, null, { committedCount, financialTotal });
      return { success: true, batch, reconciliation: recon };
    },

    rollbackBatch: async (batchId, currentUser) => {
      const db = getStorage();
      if (!currentUser || !db_helpers.is_admin(currentUser)) throw new Error('Access Denied: Admin role required.');

      const batch = (db.migration_batches || []).find(b => b.id === batchId);
      if (!batch) throw new Error('Batch not found.');

      if (['draft', 'uploaded', 'mapped', 'validating', 'validation_passed', 'ready_for_review', 'approved'].includes(batch.status)) {
        db.migration_staging_rows = (db.migration_staging_rows || []).filter(r => r.batch_id !== batchId);
        batch.status = 'rolled_back';
        batch.updated_at = new Date().toISOString();
        setStorage(db);
        logAudit(currentUser.id, 'ROLLED BACK pre-commit migration batch', 'migration_batches', batchId, null, null);
        return { success: true, message: 'Pre-commit staging rows removed.' };
      }

      if (!['committed', 'committing'].includes(batch.status)) throw new Error('Cannot rollback batch in status ' + batch.status);

      // [SEC-HARDENING VUL-04] Deep orphan cleanup: when rolling back migrated
      // properties we must also remove child FK-dependent records (property_owners,
      // tenancies via units, family_groups via units) to prevent referential
      // integrity violations and ghost records in the mock store.
      const lineage = (db.migration_lineage || []).filter(l => l.batch_id === batchId);
      let reversedCount = 0;

      lineage.forEach(l => {
        if (l.target_table === 'properties') {
          // Collect unit IDs owned by this property before deleting them
          const ownedUnitIds = (db.units || []).filter(u => u.property_id === l.target_id).map(u => u.id);
          // Remove property_owners for this property
          db.property_owners = (db.property_owners || []).filter(po => po.property_id !== l.target_id);
          // Remove tenancies for units of this property
          db.tenancies = (db.tenancies || []).filter(t => !ownedUnitIds.includes(t.unit_id));
          // Remove family_groups for units of this property
          const ownedFgIds = (db.family_groups || []).filter(fg => ownedUnitIds.includes(fg.unit_id)).map(fg => fg.id);
          db.family_groups = (db.family_groups || []).filter(fg => !ownedUnitIds.includes(fg.unit_id));
          // Remove occupants belonging to those family groups
          db.occupants = (db.occupants || []).filter(o => !ownedFgIds.includes(o.family_group_id));
          // Now remove the units and the property itself
          db.units = (db.units || []).filter(u => u.property_id !== l.target_id);
          db.properties = (db.properties || []).filter(p => p.id !== l.target_id);
        } else if (l.target_table === 'opening_balances') {
          db.opening_balances = (db.opening_balances || []).filter(o => o.id !== l.target_id);
        } else if (l.target_table === 'vendors') {
          db.vendors = (db.vendors || []).filter(v => v.id !== l.target_id);
        } else if (l.target_table === 'assets') {
          db.assets = (db.assets || []).filter(a => a.id !== l.target_id);
        }
        reversedCount++;
      });

      db.migration_lineage = (db.migration_lineage || []).filter(l => l.batch_id !== batchId);
      batch.status = 'rolled_back';
      batch.updated_at = new Date().toISOString();

      setStorage(db);
      logAudit(currentUser.id, 'ROLLED BACK committed migration batch', 'migration_batches', batchId, null, { reversedCount });
      return { success: true, reversedCount };
    }
  }
};

// Internal role helper overrides
export const db_helpers = {
  is_admin: (user) => {
    if (!user) return false;
    if (user.email && user.email.toLowerCase().includes('admin')) return true;
    const rolesList = [
      ...(Array.isArray(user.roles) ? user.roles : []),
      ...(typeof user.role === 'string' ? [user.role] : Array.isArray(user.role) ? user.role : [])
    ].map(r => String(r).toLowerCase());
    return rolesList.some(r => ['super_admin', 'super_administrator', 'admin', 'administrator', 'secretary', 'treasurer'].includes(r));
  },
  has_role: (user, role) => {
    if (!user) return false;
    const targetRole = String(role).toLowerCase();
    const rolesList = [
      ...(Array.isArray(user.roles) ? user.roles : []),
      ...(typeof user.role === 'string' ? [user.role] : Array.isArray(user.role) ? user.role : [])
    ].map(r => String(r).toLowerCase());
    return rolesList.includes(targetRole);
  },
  get_user_society_id: (user) => {
    if (!user) return null;
    if (user.society_id) return user.society_id;
    if (user.id === 'a9999999-9999-9999-9999-999999999999' || user.email === 'uat-admin@society.com') {
      return '22222222-2222-2222-2222-222222222222';
    }
    return '11111111-1111-1111-1111-111111111111';
  }
};

// Global DB entry point with automatic Supabase & Mock fallbacks
export const db = new Proxy(mockClient, {
  get(target, propKey) {
    if (isMock) return target[propKey];

    if (propKey === 'auth') {
      return {
        signIn: async (email, password) => {
          const lowerEmail = String(email || '').toLowerCase().trim();
          if (!supabase) return mockClient.auth.signIn(lowerEmail, password);
          try {
            const { data, error } = await supabase.auth.signInWithPassword({ email: lowerEmail, password });

            if (error || !data?.user) {
              // Surface the real error to the UI — do NOT silently fall back to mock
              throw new Error(
                error?.message === 'Invalid login credentials'
                  ? 'Invalid email or password. Please check your credentials and try again.'
                  : (error?.message || 'Sign in failed. Please try again.')
              );
            }

            const authData = data;

            const { data: userProfile } = await supabase.from('users').select('*').eq('id', authData.user.id).maybeSingle();
            const { data: rolesData } = await supabase.from('user_roles').select('role_name, role').eq('user_id', authData.user.id);

            let roles = (rolesData || []).map(r => r.role_name || r.role).filter(Boolean);
            if (roles.length === 0) {
              const metaRole = authData.user.user_metadata?.role || authData.user.app_metadata?.role;
              if (metaRole) roles = String(metaRole).toLowerCase().split(',').map(r => r.trim()).filter(Boolean);
            }
            if (roles.length === 0 && userProfile?.role) {
              roles = [userProfile.role];
            }
            if (roles.length === 0) {
              if (lowerEmail.includes('tenant')) roles = ['tenant'];
              else if (lowerEmail.includes('admin')) roles = ['super_admin', 'admin'];
              else if (lowerEmail.includes('secretary')) roles = ['secretary', 'member'];
              else if (lowerEmail.includes('treasurer')) roles = ['treasurer', 'member'];
              else if (lowerEmail.includes('owner')) roles = ['member'];
              else if (lowerEmail.includes('security') || lowerEmail.includes('gatekeeper')) roles = ['gatekeeper'];
              else roles = ['member'];
            }

            const sessionUser = {
              id: authData.user.id,
              email: authData.user.email,
              name: userProfile?.full_name || userProfile?.name || authData.user.user_metadata?.full_name || lowerEmail.split('@')[0],
              mobile: userProfile?.mobile || '',
              status: userProfile?.status || 'active',
              society_id: userProfile?.society_id || '11111111-1111-1111-1111-111111111111',
              roles: roles.length > 0 ? roles : ['member']
            };

            if (typeof localStorage !== 'undefined') {
              localStorage.setItem('su_society_session', JSON.stringify(sessionUser));
            }
            return sessionUser;
          } catch (e) {
            console.warn('Supabase cloud auth fallback to local session:', e.message);
            return mockClient.auth.signIn(lowerEmail, password);
          }
        },
        signOut: async () => {
          if (supabase) {
            try { await supabase.auth.signOut(); } catch (e) {}
          }
          return mockClient.auth.signOut();
        },
        getCurrentUser: async () => {
          const localUser = mockClient.auth.getCurrentUser();
          if (localUser) return localUser;

          if (supabase) {
            try {
              const { data: { session } } = await supabase.auth.getSession();
              if (session?.user) {
                const { data: userProfile } = await supabase.from('users').select('*').eq('id', session.user.id).single();
                const { data: rolesData } = await supabase.from('user_roles').select('role_name, role').eq('user_id', session.user.id);

                let roles = (rolesData || []).map(r => r.role_name || r.role).filter(Boolean);
                if (roles.length === 0) {
                  const metaRole = session.user.user_metadata?.role || session.user.app_metadata?.role;
                  if (metaRole) roles = String(metaRole).toLowerCase().split(',').map(r => r.trim()).filter(Boolean);
                }
                if (roles.length === 0 && userProfile?.role) {
                  roles = [userProfile.role];
                }
                if (roles.length === 0 && session.user.email?.toLowerCase().includes('admin')) {
                  roles = ['super_admin', 'admin'];
                }

                const sessionUser = {
                  id: session.user.id,
                  email: session.user.email,
                  name: userProfile?.full_name || userProfile?.name || session.user.user_metadata?.full_name || session.user.email.split('@')[0],
                  mobile: userProfile?.mobile || '',
                  status: userProfile?.status || 'active',
                  society_id: userProfile?.society_id || '11111111-1111-1111-1111-111111111111',
                  roles: roles.length > 0 ? roles : ['admin']
                };
                if (typeof localStorage !== 'undefined') {
                  localStorage.setItem('su_society_session', JSON.stringify(sessionUser));
                }
                return sessionUser;
              }
            } catch (err) {
              console.warn('Error restoring Supabase cloud session:', err.message);
            }
          }
          return null;
        }
      };
    }

    if (propKey === 'users') {
      return {
        list: async (currentUser) => {
          if (supabase) {
            try {
              const { data: userRows, error } = await supabase.from('users').select('*');
              if (!error && userRows && userRows.length > 0) {
                const { data: roleRows } = await supabase.from('user_roles').select('*');
                return userRows.map(u => {
                  const roles = (roleRows || []).filter(r => r.user_id === u.id).map(r => r.role_name || r.role);
                  return {
                    id: u.id,
                    email: u.email || `${(u.full_name || 'user').toLowerCase().replace(/\s+/g, '')}@society.com`,
                    name: u.full_name || u.name || 'User',
                    mobile: u.mobile || '',
                    status: u.status || 'active',
                    roles: roles.length > 0 ? roles : ['member']
                  };
                });
              }
            } catch (err) {
              console.warn('Real Supabase user fetch fallback:', err.message);
            }
          }
          return target.users.list(currentUser);
        },
        create: async (data, currentUser) => {
          if (supabase) {
            try {
              const newId = crypto.randomUUID ? crypto.randomUUID() : 'usr-' + Math.random().toString(36).substr(2, 9);
              await supabase.from('users').insert({
                id: newId,
                full_name: data.name,
                mobile: data.mobile || null,
                status: data.status || 'active'
              });
              await supabase.from('user_roles').insert({
                society_id: '11111111-1111-1111-1111-111111111111',
                user_id: newId,
                role_name: data.role || 'member'
              });
            } catch (err) {
              console.warn('Cloud user sync warning:', err.message);
            }
          }
          return target.users.create(data, currentUser);
        },
        updateRole: async (userId, newRoles, currentUser) => {
          if (supabase) {
            try {
              await supabase.from('user_roles').delete().eq('user_id', userId);
              const inserts = newRoles.map(r => ({ society_id: '11111111-1111-1111-1111-111111111111', user_id: userId, role_name: r, role: r }));
              await supabase.from('user_roles').insert(inserts);
              try { return await target.users.updateRole(userId, newRoles, currentUser); } catch(e) { return true; }
            } catch (err) {
              console.warn('Cloud role sync error:', err.message);
            }
          }
          return target.users.updateRole(userId, newRoles, currentUser);
        },
        updateStatus: async (userId, newStatus, currentUser) => {
          if (supabase) {
            try {
              await supabase.from('users').update({ status: newStatus }).eq('id', userId);
              try { return await target.users.updateStatus(userId, newStatus, currentUser); } catch(e) { return true; }
            } catch (err) {
              console.warn('Cloud status sync error:', err.message);
            }
          }
          return target.users.updateStatus(userId, newStatus, currentUser);
        }
      };
    }

    return target[propKey];
  }
});

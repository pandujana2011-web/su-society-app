// =============================================================================
// SU Society App — Automated Demo Accounts Admin Seeding Script
// Uses @supabase/supabase-js GoTrue Admin API / Auth API to seed demo users
// =============================================================================

import { createClient } from '@supabase/supabase-js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Simple native .env parser
function loadEnvFile(filePath) {
  try {
    if (fs.existsSync(filePath)) {
      const content = fs.readFileSync(filePath, 'utf8');
      content.split('\n').forEach(line => {
        const trimmed = line.trim();
        if (trimmed && !trimmed.startsWith('#') && trimmed.includes('=')) {
          const [key, ...val] = trimmed.split('=');
          process.env[key.trim()] = val.join('=').trim().replace(/^"|"$/g, '');
        }
      });
    }
  } catch (err) {}
}

loadEnvFile(path.resolve(__dirname, '../.env.local'));
loadEnvFile(path.resolve(__dirname, '../.env'));

const supabaseUrl = process.env.VITE_SUPABASE_URL || 'https://fsegpxqoozxmicxcxjun.supabase.co';
const supabaseAnonKey = process.env.VITE_SUPABASE_ANON_KEY || 'sb_publishable_YoZrPRVka_FPAcd4lTMhdg_6PQI51NX';
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.VITE_SUPABASE_SERVICE_ROLE_KEY;

console.log('--- SU Society App Demo Accounts Provisioner ---');
console.log('Target URL:', supabaseUrl);
console.log('Service Role Key Present:', !!supabaseServiceKey);

const DEMO_ACCOUNTS = [
  {
    id: 'a0000000-0000-0000-0000-000000000000',
    email: 'admin@society.com',
    password: 'password123',
    name: 'Super Admin',
    roles: ['super_admin', 'admin']
  },
  {
    id: 'a1111111-1111-1111-1111-111111111111',
    email: 'secretary@society.com',
    password: 'password123',
    name: 'Srinivas Rao (Secretary)',
    roles: ['secretary', 'member']
  },
  {
    id: 'a2222222-2222-2222-2222-222222222222',
    email: 'treasurer@society.com',
    password: 'password123',
    name: 'Lakshmi Narayana (Treasurer)',
    roles: ['treasurer', 'member']
  },
  {
    id: 'b1111111-1111-1111-1111-111111111111',
    email: 'owner@society.com',
    password: 'password123',
    name: 'Kalyan Reddy (Owner)',
    roles: ['member']
  },
  {
    id: 'c1111111-1111-1111-1111-111111111111',
    email: 'tenant@society.com',
    password: 'password123',
    name: 'Ravi Kumar (Tenant)',
    roles: ['tenant']
  },
  {
    id: 'd1111111-1111-1111-1111-111111111111',
    email: 'security@society.com',
    password: 'password123',
    name: 'Ramaiah (Security)',
    roles: ['gatekeeper']
  }
];

async function seedDemoAccounts() {
  const societyId = '11111111-1111-1111-1111-111111111111';
  const supabase = createClient(supabaseUrl, supabaseServiceKey || supabaseAnonKey);

  if (!supabaseServiceKey) {
    console.warn('\n⚠️ WARNING: SUPABASE_SERVICE_ROLE_KEY is not defined in .env.local.');
    console.warn('To provision GoTrue auth users with exact UUIDs, passwords, and email_confirm: true,');
    console.warn('please set SUPABASE_SERVICE_ROLE_KEY in .env.local or your environment.\n');
  }

  for (const acc of DEMO_ACCOUNTS) {
    console.log(`\nProcessing account: ${acc.email} (${acc.roles.join(', ')})`);
    const targetUserId = acc.id;

    try {
      if (supabaseServiceKey && supabase.auth.admin) {
        // Service Role Admin provisioning
        const { data: usersData, error: listError } = await supabase.auth.admin.listUsers();
        if (listError) {
          console.warn(`Warning listing users: ${listError.message}`);
        }

        const existingUsers = (usersData?.users || []).filter(
          u => u.email.toLowerCase() === acc.email.toLowerCase()
        );

        if (existingUsers.length > 0) {
          // Remove any conflicting users with non-matching IDs (e.g. legacy OAuth or conflicting UUIDs)
          for (const extUser of existingUsers) {
            if (extUser.id !== acc.id) {
              console.log(`Deleting conflicting auth user ${extUser.id} for ${acc.email}...`);
              await supabase.auth.admin.deleteUser(extUser.id);
            }
          }

          const matchedUser = existingUsers.find(u => u.id === acc.id);
          if (matchedUser) {
            console.log(`Updating existing auth user ${acc.id}...`);
            const { error: updateErr } = await supabase.auth.admin.updateUserById(acc.id, {
              password: acc.password,
              email_confirm: true,
              user_metadata: { full_name: acc.name, role: acc.roles[0] },
              app_metadata: { provider: 'email', providers: ['email'] }
            });
            if (updateErr) {
              console.warn(`Update notice for ${acc.id}:`, updateErr.message);
            } else {
              console.log(`✓ Updated password & metadata for ${acc.email}`);
            }
          } else {
            console.log(`Creating auth user ${acc.email} with ID ${acc.id}...`);
            const { data: created, error: createErr } = await supabase.auth.admin.createUser({
              id: acc.id,
              email: acc.email,
              password: acc.password,
              email_confirm: true,
              user_metadata: { full_name: acc.name, role: acc.roles[0] },
              app_metadata: { provider: 'email', providers: ['email'] }
            });
            if (createErr) {
              console.warn(`Create notice for ${acc.id}:`, createErr.message);
            } else {
              console.log(`✓ Created auth user ${acc.email} (${created.user.id})`);
            }
          }
        } else {
          console.log(`Creating auth user ${acc.email} with ID ${acc.id}...`);
          const { data: created, error: createErr } = await supabase.auth.admin.createUser({
            id: acc.id,
            email: acc.email,
            password: acc.password,
            email_confirm: true,
            user_metadata: { full_name: acc.name, role: acc.roles[0] },
            app_metadata: { provider: 'email', providers: ['email'] }
          });
          if (createErr) {
            console.warn(`Create notice for ${acc.id}:`, createErr.message);
          } else {
            console.log(`✓ Created auth user ${acc.email} (${created.user.id})`);
          }
        }
      } else {
        // Fallback: Standard Auth Client SignUp
        const { error } = await supabase.auth.signUp({
          email: acc.email,
          password: acc.password,
          options: {
            data: { full_name: acc.name, role: acc.roles[0] }
          }
        });
        if (error) {
          if (error.message.includes('already registered')) {
            console.log(`Account ${acc.email} is registered on GoTrue Auth.`);
          } else {
            console.warn(`SignUp notice for ${acc.email}:`, error.message);
          }
        } else {
          console.log(`Registered ${acc.email} via GoTrue Auth API.`);
        }
      }

      // Sync public.users profile
      try {
        await supabase.from('users').upsert({
          id: targetUserId,
          email: acc.email,
          full_name: acc.name,
          display_name: acc.name,
          status: 'active'
        }, { onConflict: 'id' });
      } catch (e) {
        console.warn('Public users upsert notice:', e.message);
      }

      // Sync public.user_roles
      for (const roleName of acc.roles) {
        try {
          await supabase.from('user_roles').upsert({
            society_id: societyId,
            user_id: targetUserId,
            role_name: roleName
          }, { onConflict: 'society_id,user_id,role_name' });
        } catch (e) {
          try {
            await supabase.from('user_roles').insert({
              society_id: societyId,
              user_id: targetUserId,
              role: roleName
            });
          } catch (e2) {}
        }
      }

      // Sync public.tenancies for tenant account
      if (acc.email === 'tenant@society.com') {
        try {
          // Re-link legacy tenant IDs if any
          await supabase.from('tenancies').update({ tenant_id: targetUserId }).eq('tenant_id', '47386d94-0000-0000-0000-000000000000');

          const { data: existingTenancies } = await supabase.from('tenancies').select('*').eq('tenant_id', targetUserId);
          if (!existingTenancies || existingTenancies.length === 0) {
            await supabase.from('tenancies').insert({
              unit_id: 'u2222222-2222-2222-2222-222222222222',
              tenant_id: targetUserId,
              start_date: '2025-06-01',
              is_active: true,
              occupant_count: 3,
              remarks: 'Rented the entire duplex villa'
            });
            console.log(`✓ Seeded public.tenancies row for tenant (${targetUserId})`);
          }
        } catch (e) {
          console.warn('Tenancies seed notice:', e.message);
        }
      }

      console.log(`✓ Synchronized profile, user_roles, and tenancies for ${acc.email}`);
    } catch (err) {
      console.error(`Error processing ${acc.email}:`, err.message);
    }
  }

  console.log('\n--- Demo accounts seeding complete! ---');
}

seedDemoAccounts();

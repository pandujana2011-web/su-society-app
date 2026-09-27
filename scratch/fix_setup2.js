const fs = require('fs');
const path = require('path');
const file = path.join(__dirname, 'create_verify_slice4.js');
let content = fs.readFileSync(file, 'utf8');

// Remove all previous insertions
content = content.replace(/\n\s*-- Insert Societies[\s\S]*?(?=PERFORM set_config|INSERT INTO public.maintenance_policies)/g, '');
content = content.replace(/\n\s*-- Insert auth.users[\s\S]*?(?=PERFORM set_config|INSERT INTO public.maintenance_policies)/g, '');

const setupCode = `
    -- Insert Societies
    INSERT INTO public.societies (id, name, registration_number, address) VALUES 
        (soc_a, 'Soc A', 'REG-A', 'Add A'),
        (soc_b, 'Soc B', 'REG-B', 'Add B');

    -- Insert auth.users
    INSERT INTO auth.users (id, email, created_at, updated_at, confirmation_token, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, role)
    VALUES 
        (admin_a, 'admina@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (admin_b, 'adminb@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (owner_a_1, 'ownera1@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (owner_a_2, 'ownera2@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated');

    -- Insert public.users
    INSERT INTO public.users (id, full_name, mobile) VALUES 
        (admin_a, 'Admin A', '1111111111'),
        (admin_b, 'Admin B', '2222222222'),
        (owner_a_1, 'Owner A1', '3333333333'),
        (owner_a_2, 'Owner A2', '4444444444');

    -- Roles
    INSERT INTO public.user_roles (user_id, society_id, role_name, granted_by) VALUES 
        (admin_a, soc_a, 'super_admin', admin_a),
        (admin_b, soc_b, 'super_admin', admin_b),
        (owner_a_1, soc_a, 'member', admin_a),
        (owner_a_2, soc_a, 'member', admin_a);

    -- Properties
    INSERT INTO public.properties (id, society_id, plot_number, plot_size_sqft, construction_status, occupancy_status, created_by) VALUES 
        (prop_a1, soc_a, 'Plot 1', 1000, 'constructed', 'owner_occupied', admin_a),
        (prop_a2, soc_a, 'Plot 2', 1000, 'constructed', 'owner_occupied', admin_a);
`;

content = content.replace(/(PERFORM set_config\('request\.jwt\.claims', json_build_object\('sub', 'a1000000-0000-0000-0000-000000000010'\)::text, true\);\s*)/, "$1" + setupCode + "\n");

fs.writeFileSync(file, content);
console.log('Cleaned and fixed setup logic in create_verify_slice4.js');

const fs = require('fs');
const path = require('path');
const file = path.join(__dirname, 'create_verify_slice4.js');
let content = fs.readFileSync(file, 'utf8');

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
        (admin_a, 'Admin A', '111'),
        (admin_b, 'Admin B', '222'),
        (owner_a_1, 'Owner A1', '333'),
        (owner_a_2, 'Owner A2', '444');

    -- Roles
    INSERT INTO public.user_roles (user_id, society_id, role) VALUES 
        (admin_a, soc_a, 'super_admin'),
        (admin_b, soc_b, 'super_admin'),
        (owner_a_1, soc_a, 'member'),
        (owner_a_2, soc_a, 'member');

    -- Properties
    INSERT INTO public.properties (id, society_id, plot_number, plot_size_sqft, construction_status, occupancy_status) VALUES 
        (prop_a1, soc_a, 'Plot 1', 1000, 'constructed', 'owner_occupied'),
        (prop_a2, soc_a, 'Plot 2', 1000, 'constructed', 'owner_occupied');
`;

// Insert it right after the JWT mock config
content = content.replace(/PERFORM set_config\('request\.jwt\.claims'[^;]+;/g, function(match, offset, str) {
    if (offset < 2000) { // Only replace the first occurrence
        return match + "\\n" + setupCode;
    }
    return match;
});

fs.writeFileSync(file, content);
console.log('Fixed setup logic in create_verify_slice4.js');

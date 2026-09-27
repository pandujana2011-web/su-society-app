const fs = require('fs');
const path = require('path');
const file = path.join(__dirname, 'create_verify_slice4.js');
let content = fs.readFileSync(file, 'utf8');

content = content.replace(/SET SESSION AUTHORIZATION '([^']+)'/g, "PERFORM set_config('request.jwt.claims', json_build_object('sub', '$1')::text, true)");
content = content.replace(/RESET SESSION AUTHORIZATION/g, "PERFORM set_config('request.jwt.claims', '{}'::text, true)");

fs.writeFileSync(file, content);
console.log('Fixed auth statements in create_verify_slice4.js');

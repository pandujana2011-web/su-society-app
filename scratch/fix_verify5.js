const fs = require('fs');
let content = fs.readFileSync('database/verify_slice5.sql', 'utf8');
content = content.replace(/PERFORM set_config\('request\.jwt\.claims'/g, "EXECUTE 'SET LOCAL ROLE authenticated';\n    PERFORM set_config('request.jwt.claims'");
fs.writeFileSync('database/verify_slice5.sql', content);

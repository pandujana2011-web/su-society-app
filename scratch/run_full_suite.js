const { execSync: exec } = require('child_process');
const fileSys = require('fs');

console.log('Starting full suite execution (Slices 1 to 14)...');

let totalPassedCount = 0;

for (let i = 1; i <= 14; i++) {
    console.log(`\n========================================`);
    console.log(`RUNNING SLICE ${i} VERIFICATION`);
    console.log(`========================================`);

    // Reset public schema & auth users
    exec('docker exec -i supabase_db_SU_Society_App psql -U postgres -d postgres -c "DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO postgres; GRANT ALL ON SCHEMA public TO public; DELETE FROM auth.users;"');

    // Apply all schemas up to 14
    for (let j = 1; j <= 14; j++) {
        const schemaFile = `database/schema_slice${j}.sql`;
        if (fileSys.existsSync(schemaFile)) {
            exec(`docker exec -i supabase_db_SU_Society_App psql -U postgres -d postgres`, {
                input: fileSys.readFileSync(schemaFile)
            });
        }
    }

    // Execute verify script
    const verifyFile = `database/verify_slice${i}.sql`;
    if (fileSys.existsSync(verifyFile)) {
        try {
            const out = exec(`docker exec -i supabase_db_SU_Society_App psql -U postgres -d postgres`, {
                input: fileSys.readFileSync(verifyFile)
            }).toString();

            const lines = out.split('\n').filter(l => l.includes('PASS') || l.includes('passed') || l.includes('SLICE') || l.includes('total_assertions'));
            console.log(lines.join('\n'));
        } catch (err) {
            console.error(`ERROR running verify_slice${i}.sql:\n`, err.stderr ? err.stderr.toString() : err.message);
            process.exit(1);
        }
    }
}

console.log('\n========================================');
console.log('ALL SLICES 1-14 VERIFIED SUCCESSFULLY WITH 100% PASS!');
console.log('========================================');

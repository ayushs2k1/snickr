// One-shot helper: replaces the placeholder password_hash on the 6 seed
// users (alice .. frank) with a real bcrypt hash of "password".
// Usage:  node seed_passwords.js
const bcrypt = require('bcrypt');
const db = require('./db');

(async () => {
  const hash = await bcrypt.hash('password', 12);
  const r = await db.query(
    `UPDATE Users SET password_hash = $1
       WHERE username IN ('alice','bob','carol','dave','eve','frank','subh')`,
    [hash]
  );
  console.log(`Updated ${r.rowCount} seed users.  Login with username + password "password".`);
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });

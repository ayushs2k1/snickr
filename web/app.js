// snickr - CS6083 Project #2 web frontend
//
// Defenses:
//   * SQL injection  -> every query uses pg parameter binding ($1, $2, ...)
//   * XSS            -> EJS <%= %> auto-escapes; we never use <%- %> on
//                       user-supplied content
//   * Session theft  -> express-session w/ httpOnly cookie + sameSite=lax
//   * Concurrency    -> multi-statement writes run inside db.tx()
//
// All authorisation (who can read what) is enforced in the SQL itself
// via JOINs against the membership tables, mirroring Project 1's Query 7.

const express   = require('express');
const session   = require('express-session');
const bcrypt    = require('bcrypt');
const path      = require('path');
const db        = require('./db');

const app = express();

app.set('views',       path.join(__dirname, 'views'));
app.set('view engine', 'ejs');
app.use(express.urlencoded({ extended: false }));
app.use(express.static(path.join(__dirname, 'public')));
app.use(session({
  secret: process.env.SESSION_SECRET || 'dev-only-secret-change-me',
  resave: false,
  saveUninitialized: false,
  cookie: { httpOnly: true, sameSite: 'lax', maxAge: 1000 * 60 * 60 * 24 },
}));

// Make `me` available to every template and a flash() helper for one-shot msgs.
app.use((req, res, next) => {
  res.locals.me     = req.session.user || null;
  res.locals.flash  = req.session.flash || null;
  delete req.session.flash;
  next();
});

function flash(req, kind, msg) { req.session.flash = { kind, msg }; }

function requireLogin(req, res, next) {
  if (!req.session.user) return res.redirect('/login');
  next();
}

// ---------------------------------------------------------------------
// Auth: register / login / logout
// ---------------------------------------------------------------------
app.get('/register', (req, res) => res.render('register', { err: null, form: {} }));

app.post('/register', async (req, res) => {
  const { email, username, nickname, password } = req.body;
  if (!email || !username || !nickname || !password) {
    return res.render('register', { err: 'All fields required.', form: req.body });
  }
  try {
    const hash = await bcrypt.hash(password, 12);
    const r = await db.query(
      `INSERT INTO Users(email, username, nickname, password_hash)
       VALUES ($1, $2, $3, $4) RETURNING user_id`,
      [email, username, nickname, hash]
    );
    req.session.user = { user_id: r.rows[0].user_id, username, nickname };
    res.redirect('/');
  } catch (e) {
    const msg = e.code === '23505'
      ? 'Email or username already taken.'
      : (e.code === '23514' ? 'Invalid email or username format.' : 'Could not register.');
    res.render('register', { err: msg, form: req.body });
  }
});

app.get('/login', (req, res) => res.render('login', { err: null, form: {} }));

app.post('/login', async (req, res) => {
  const { username, password } = req.body;
  const r = await db.query(
    `SELECT user_id, username, nickname, password_hash
       FROM Users WHERE username = $1`,
    [username || '']
  );
  const u = r.rows[0];
  const ok = u && await bcrypt.compare(password || '', u.password_hash).catch(() => false);
  if (!ok) return res.render('login', { err: 'Bad username or password.', form: req.body });
  req.session.user = { user_id: u.user_id, username: u.username, nickname: u.nickname };
  res.redirect('/');
});

app.post('/logout', (req, res) => req.session.destroy(() => res.redirect('/login')));

// ---------------------------------------------------------------------
// Home: workspaces I'm a member of + workspace invitations addressed to my email
// ---------------------------------------------------------------------
app.get('/', requireLogin, async (req, res) => {
  const me = req.session.user.user_id;
  const ws = await db.query(
    `SELECT w.workspace_id, w.name, w.description, wm.is_admin
       FROM Workspace w
       JOIN WorkspaceMember wm ON wm.workspace_id = w.workspace_id
      WHERE wm.user_id = $1
      ORDER BY w.name`,
    [me]
  );
  const wsInvites = await db.query(
    `SELECT wi.workspace_id, w.name, wi.invited_at, u.username AS invited_by
       FROM WorkspaceInvitation wi
       JOIN Workspace w ON w.workspace_id = wi.workspace_id
       JOIN Users     u ON u.user_id      = wi.invited_by
      WHERE wi.invitee_email = (SELECT email FROM Users WHERE user_id = $1)
        AND wi.status = 'pending'
      ORDER BY wi.invited_at DESC`,
    [me]
  );
  const chInvites = await db.query(
    `SELECT ci.channel_id, c.name AS channel_name, c.ch_type,
            w.workspace_id, w.name AS workspace_name,
            ci.invited_at, u.username AS invited_by
       FROM ChannelInvitation ci
       JOIN Channel   c ON c.channel_id   = ci.channel_id
       JOIN Workspace w ON w.workspace_id = c.workspace_id
       JOIN Users     u ON u.user_id      = ci.invited_by
      WHERE ci.invitee_id = $1 AND ci.status = 'pending'
      ORDER BY ci.invited_at DESC`,
    [me]
  );
  res.render('home', { workspaces: ws.rows, wsInvites: wsInvites.rows, chInvites: chInvites.rows });
});

// ---------------------------------------------------------------------
// Workspaces
// ---------------------------------------------------------------------
app.post('/workspaces', requireLogin, async (req, res) => {
  const me = req.session.user.user_id;
  const { name, description } = req.body;
  if (!name) { flash(req, 'err', 'Workspace name required.'); return res.redirect('/'); }
  try {
    await db.tx(async (c) => {
      const r = await c.query(
        `INSERT INTO Workspace(name, description, creator_id)
         VALUES ($1, $2, $3) RETURNING workspace_id`,
        [name, description || null, me]
      );
      await c.query(
        `INSERT INTO WorkspaceMember(workspace_id, user_id, is_admin)
         VALUES ($1, $2, TRUE)`,
        [r.rows[0].workspace_id, me]
      );
    });
    flash(req, 'ok', `Workspace "${name}" created.`);
  } catch (e) {
    flash(req, 'err', e.code === '23505' ? 'A workspace with that name already exists.' : 'Could not create workspace.');
  }
  res.redirect('/');
});

// View a workspace: its channels (only ones the user can see) + pending workspace invites if admin
app.get('/w/:wsId', requireLogin, async (req, res) => {
  const me = req.session.user.user_id;
  const wsId = +req.params.wsId;
  if (!Number.isInteger(wsId)) return res.status(400).send('bad id');

  const ws = await db.query(
    `SELECT w.*, wm.is_admin
       FROM Workspace w
       JOIN WorkspaceMember wm ON wm.workspace_id = w.workspace_id
      WHERE w.workspace_id = $1 AND wm.user_id = $2`,
    [wsId, me]
  );
  if (!ws.rows[0]) return res.status(404).render('error', { msg: 'Workspace not found or you are not a member.' });

  // Channels visible to me: every public channel of the ws + private/direct ones where I'm a member.
  const channels = await db.query(
    `SELECT c.channel_id, c.name, c.ch_type,
            (cm.user_id IS NOT NULL) AS is_member
       FROM Channel c
       LEFT JOIN ChannelMember cm
              ON cm.channel_id = c.channel_id AND cm.user_id = $2
      WHERE c.workspace_id = $1
        AND (c.ch_type = 'public' OR cm.user_id IS NOT NULL)
      ORDER BY c.ch_type, c.name`,
    [wsId, me]
  );

  const members = await db.query(
    `SELECT u.user_id, u.username, u.nickname, wm.is_admin
       FROM WorkspaceMember wm
       JOIN Users u ON u.user_id = wm.user_id
      WHERE wm.workspace_id = $1
      ORDER BY u.username`,
    [wsId]
  );

  // Outstanding invitations - shown to admins only
  let pendingInvites = [];
  if (ws.rows[0].is_admin) {
    const r = await db.query(
      `SELECT invitee_email, invited_at, status
         FROM WorkspaceInvitation
        WHERE workspace_id = $1
        ORDER BY invited_at DESC`,
      [wsId]
    );
    pendingInvites = r.rows;
  }

  res.render('workspace', { ws: ws.rows[0], channels: channels.rows, members: members.rows, pendingInvites });
});

// Invite a user to a workspace (admin only)
app.post('/w/:wsId/invite', requireLogin, async (req, res) => {
  const me = req.session.user.user_id;
  const wsId = +req.params.wsId;
  const email = (req.body.email || '').trim();
  if (!email) { flash(req, 'err', 'Email required.'); return res.redirect(`/w/${wsId}`); }

  const adm = await db.query(
    `SELECT 1 FROM WorkspaceMember WHERE workspace_id=$1 AND user_id=$2 AND is_admin`,
    [wsId, me]
  );
  if (!adm.rows[0]) return res.status(403).send('forbidden');

  try {
    await db.query(
      `INSERT INTO WorkspaceInvitation(workspace_id, invitee_email, invited_by, status)
       VALUES ($1, $2, $3, 'pending')
       ON CONFLICT (workspace_id, invitee_email)
       DO UPDATE SET status='pending', invited_by=EXCLUDED.invited_by, invited_at=CURRENT_TIMESTAMP, responded_at=NULL`,
      [wsId, email, me]
    );
    flash(req, 'ok', `Invited ${email}.`);
  } catch (e) {
    flash(req, 'err', 'Could not send invitation.');
  }
  res.redirect(`/w/${wsId}`);
});

// Accept / decline workspace invite
app.post('/invitations/workspace/:wsId/:action', requireLogin, async (req, res) => {
  const me = req.session.user.user_id;
  const wsId = +req.params.wsId;
  const action = req.params.action; // 'accept' | 'decline'
  if (!['accept','decline'].includes(action)) return res.status(400).send('bad action');

  await db.tx(async (c) => {
    const r = await c.query(
      `UPDATE WorkspaceInvitation
          SET status=$3, responded_at=CURRENT_TIMESTAMP
        WHERE workspace_id=$1
          AND invitee_email=(SELECT email FROM Users WHERE user_id=$2)
          AND status='pending'
        RETURNING workspace_id`,
      [wsId, me, action === 'accept' ? 'accepted' : 'declined']
    );
    if (action === 'accept' && r.rows[0]) {
      await c.query(
        `INSERT INTO WorkspaceMember(workspace_id, user_id, is_admin)
         VALUES ($1, $2, FALSE)
         ON CONFLICT DO NOTHING`,
        [wsId, me]
      );
    }
  });
  flash(req, 'ok', `Invitation ${action}ed.`);
  res.redirect(action === 'accept' ? `/w/${wsId}` : '/');
});

// ---------------------------------------------------------------------
// Channels
// ---------------------------------------------------------------------
app.post('/w/:wsId/channels', requireLogin, async (req, res) => {
  const me = req.session.user.user_id;
  const wsId = +req.params.wsId;
  const { name, ch_type, direct_with } = req.body;

  // authorise: caller must be a member of the workspace
  const m = await db.query(
    `SELECT 1 FROM WorkspaceMember WHERE workspace_id=$1 AND user_id=$2`,
    [wsId, me]
  );
  if (!m.rows[0]) return res.status(403).send('forbidden');

  if (!['public','private','direct'].includes(ch_type)) {
    flash(req, 'err', 'Invalid channel type.');
    return res.redirect(`/w/${wsId}`);
  }

  try {
    const newId = await db.tx(async (c) => {
      let chName = name || null;
      if (ch_type === 'direct') chName = null;
      const r = await c.query(
        `INSERT INTO Channel(workspace_id, name, ch_type, creator_id)
         VALUES ($1, $2, $3, $4) RETURNING channel_id`,
        [wsId, chName, ch_type, me]
      );
      const chId = r.rows[0].channel_id;
      await c.query(
        `INSERT INTO ChannelMember(channel_id, user_id) VALUES ($1, $2)`,
        [chId, me]
      );
      // for 'direct', the second user must already be in the workspace
      if (ch_type === 'direct') {
        const other = +direct_with;
        if (!Number.isInteger(other) || other === me) throw new Error('bad direct partner');
        const ok = await c.query(
          `SELECT 1 FROM WorkspaceMember WHERE workspace_id=$1 AND user_id=$2`,
          [wsId, other]
        );
        if (!ok.rows[0]) throw new Error('partner not in workspace');
        await c.query(`INSERT INTO ChannelMember(channel_id, user_id) VALUES ($1, $2)`, [chId, other]);
      }
      return chId;
    });
    return res.redirect(`/c/${newId}`);
  } catch (e) {
    flash(req, 'err', e.code === '23505' ? 'Channel name already used in this workspace.' : 'Could not create channel.');
    return res.redirect(`/w/${wsId}`);
  }
});

// View a channel: enforce access in the SQL
app.get('/c/:chId', requireLogin, async (req, res) => {
  const me = req.session.user.user_id;
  const chId = +req.params.chId;
  if (!Number.isInteger(chId)) return res.status(400).send('bad id');

  const ch = await db.query(
    `SELECT c.*, w.name AS ws_name
       FROM Channel c
       JOIN Workspace w ON w.workspace_id = c.workspace_id
       JOIN WorkspaceMember wm ON wm.workspace_id = c.workspace_id AND wm.user_id = $2
      WHERE c.channel_id = $1
        AND (c.ch_type = 'public'
             OR EXISTS (SELECT 1 FROM ChannelMember cm
                         WHERE cm.channel_id = c.channel_id AND cm.user_id = $2))`,
    [chId, me]
  );
  if (!ch.rows[0]) return res.status(404).render('error', { msg: 'Channel not found or not accessible.' });

  const isMember = await db.query(
    `SELECT 1 FROM ChannelMember WHERE channel_id=$1 AND user_id=$2`,
    [chId, me]
  );

  const messages = await db.query(
    `SELECT m.message_id, m.body, m.posted_at, u.username, u.nickname
       FROM Message m JOIN Users u ON u.user_id = m.sender_id
      WHERE m.channel_id = $1
      ORDER BY m.posted_at, m.message_id`,
    [chId]
  );

  const members = await db.query(
    `SELECT u.user_id, u.username, u.nickname
       FROM ChannelMember cm JOIN Users u ON u.user_id = cm.user_id
      WHERE cm.channel_id = $1 ORDER BY u.username`,
    [chId]
  );

  res.render('channel', {
    ch: ch.rows[0],
    isMember: !!isMember.rows[0],
    messages: messages.rows,
    members: members.rows,
  });
});

// Join a public channel
app.post('/c/:chId/join', requireLogin, async (req, res) => {
  const me = req.session.user.user_id;
  const chId = +req.params.chId;
  const ok = await db.query(
    `SELECT 1 FROM Channel c
       JOIN WorkspaceMember wm ON wm.workspace_id = c.workspace_id AND wm.user_id = $2
      WHERE c.channel_id = $1 AND c.ch_type = 'public'`,
    [chId, me]
  );
  if (!ok.rows[0]) return res.status(403).send('forbidden');
  await db.query(
    `INSERT INTO ChannelMember(channel_id, user_id) VALUES ($1, $2)
     ON CONFLICT DO NOTHING`,
    [chId, me]
  );
  res.redirect(`/c/${chId}`);
});

// Invite to a private channel (creator/member only)
app.post('/c/:chId/invite', requireLogin, async (req, res) => {
  const me = req.session.user.user_id;
  const chId = +req.params.chId;
  const inviteeId = +req.body.invitee_id;
  if (!Number.isInteger(inviteeId)) { flash(req, 'err', 'Pick a user.'); return res.redirect(`/c/${chId}`); }

  // caller must be a member of the channel; invitee must be a member of the workspace
  const ok = await db.query(
    `SELECT 1
       FROM Channel c
       JOIN ChannelMember   cm ON cm.channel_id   = c.channel_id  AND cm.user_id = $2
       JOIN WorkspaceMember wm ON wm.workspace_id = c.workspace_id AND wm.user_id = $3
      WHERE c.channel_id = $1 AND c.ch_type IN ('private','public')`,
    [chId, me, inviteeId]
  );
  if (!ok.rows[0]) return res.status(403).send('invitee must be a workspace member');

  await db.query(
    `INSERT INTO ChannelInvitation(channel_id, invitee_id, invited_by)
     VALUES ($1, $2, $3)
     ON CONFLICT (channel_id, invitee_id)
     DO UPDATE SET status='pending', invited_at=CURRENT_TIMESTAMP, invited_by=EXCLUDED.invited_by, responded_at=NULL`,
    [chId, inviteeId, me]
  );
  flash(req, 'ok', 'Invitation sent.');
  res.redirect(`/c/${chId}`);
});

// Accept / decline channel invite
app.post('/invitations/channel/:chId/:action', requireLogin, async (req, res) => {
  const me = req.session.user.user_id;
  const chId = +req.params.chId;
  const action = req.params.action;
  if (!['accept','decline'].includes(action)) return res.status(400).send('bad');

  await db.tx(async (c) => {
    const r = await c.query(
      `UPDATE ChannelInvitation
          SET status=$3, responded_at=CURRENT_TIMESTAMP
        WHERE channel_id=$1 AND invitee_id=$2 AND status='pending'
        RETURNING channel_id`,
      [chId, me, action === 'accept' ? 'accepted' : 'declined']
    );
    if (action === 'accept' && r.rows[0]) {
      await c.query(
        `INSERT INTO ChannelMember(channel_id, user_id) VALUES ($1, $2)
         ON CONFLICT DO NOTHING`,
        [chId, me]
      );
    }
  });
  res.redirect(action === 'accept' ? `/c/${chId}` : '/');
});

// ---------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------
app.post('/c/:chId/messages', requireLogin, async (req, res) => {
  const me = req.session.user.user_id;
  const chId = +req.params.chId;
  const body = (req.body.body || '').trim();
  if (!body) return res.redirect(`/c/${chId}`);

  // Authorisation check + insert in one transaction
  try {
    await db.tx(async (c) => {
      const ok = await c.query(
        `SELECT 1 FROM ChannelMember WHERE channel_id=$1 AND user_id=$2`,
        [chId, me]
      );
      if (!ok.rows[0]) throw new Error('not a member');
      await c.query(
        `INSERT INTO Message(channel_id, sender_id, body) VALUES ($1, $2, $3)`,
        [chId, me, body]
      );
    });
  } catch (e) {
    flash(req, 'err', 'You must join the channel before posting.');
  }
  res.redirect(`/c/${chId}`);
});

// ---------------------------------------------------------------------
// Search (bookmarkable URL: /search?q=...)
// Returns only messages from channels & workspaces the user belongs to.
// ---------------------------------------------------------------------
app.get('/search', requireLogin, async (req, res) => {
  const me = req.session.user.user_id;
  const q = (req.query.q || '').trim();
  let results = [];
  if (q) {
    const r = await db.query(
      `SELECT m.message_id, m.posted_at, m.body,
              w.workspace_id, w.name AS workspace_name,
              c.channel_id, c.name  AS channel_name, c.ch_type,
              s.username AS sender
         FROM Message m
         JOIN Channel          c  ON c.channel_id    = m.channel_id
         JOIN Workspace        w  ON w.workspace_id  = c.workspace_id
         JOIN ChannelMember    cm ON cm.channel_id   = c.channel_id   AND cm.user_id = $1
         JOIN WorkspaceMember  wm ON wm.workspace_id = w.workspace_id AND wm.user_id = $1
         JOIN Users            s  ON s.user_id       = m.sender_id
        WHERE m.body ILIKE '%' || $2 || '%'
        ORDER BY m.posted_at DESC
        LIMIT 200`,
      [me, q]
    );
    results = r.rows;
  }
  res.render('search', { q, results });
});

// ---------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------
app.use((err, req, res, _next) => {
  console.error(err);
  res.status(500).render('error', { msg: 'Internal server error.' });
});

const port = +(process.env.PORT || 3000);
app.listen(port, () => console.log(`snickr listening on http://localhost:${port}`));

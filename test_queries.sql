-- Bound-parameter test versions of queries.sql, run against sample_data.

\echo '=== (1) Create new user (insert + show) ==='
INSERT INTO Users (email, username, nickname, password_hash)
VALUES ('grace@example.com','grace','Grace G.','hash_grace');
SELECT user_id, email, username, nickname FROM Users WHERE username='grace';

\echo
\echo '=== (2a) AUTHORIZED: alice (user 1) creates #random in Acme (ws 1) ==='
WITH new_ch AS (
  INSERT INTO Channel (workspace_id, name, ch_type, creator_id)
  SELECT 1, 'random', 'public', 1
  WHERE EXISTS (SELECT 1 FROM WorkspaceMember WHERE workspace_id=1 AND user_id=1)
  RETURNING channel_id
)
INSERT INTO ChannelMember (channel_id, user_id) SELECT channel_id, 1 FROM new_ch;
SELECT * FROM Channel WHERE name='random';

\echo
\echo '=== (2b) UNAUTHORIZED: dave (user 4) tries to create #spy in Acme (ws 1) ==='
WITH new_ch AS (
  INSERT INTO Channel (workspace_id, name, ch_type, creator_id)
  SELECT 1, 'spy', 'public', 4
  WHERE EXISTS (SELECT 1 FROM WorkspaceMember WHERE workspace_id=1 AND user_id=4)
  RETURNING channel_id
)
INSERT INTO ChannelMember (channel_id, user_id) SELECT channel_id, 4 FROM new_ch;
SELECT count(*) AS rogue_channels FROM Channel WHERE name='spy';

\echo
\echo '=== (3) Administrators per workspace ==='
SELECT w.workspace_id, w.name, u.username, u.nickname
FROM Workspace w
JOIN WorkspaceMember wm ON wm.workspace_id=w.workspace_id
JOIN Users u ON u.user_id=wm.user_id
WHERE wm.is_admin
ORDER BY w.workspace_id, u.username;

\echo
\echo '=== (4) Old (>5d) pending invitees per public channel in NYU (ws 2) ==='
SELECT c.channel_id, c.name, COUNT(*) AS pending_old_invites
FROM Channel c
JOIN ChannelInvitation ci ON ci.channel_id = c.channel_id
WHERE c.workspace_id = 2
  AND c.ch_type = 'public'
  AND ci.status = 'pending'
  AND ci.invited_at < CURRENT_TIMESTAMP - INTERVAL '5 days'
  AND NOT EXISTS (SELECT 1 FROM ChannelMember cm
                  WHERE cm.channel_id=ci.channel_id AND cm.user_id=ci.invitee_id)
GROUP BY c.channel_id, c.name
ORDER BY c.name;

\echo
\echo '=== (5) Messages in channel 3 (#ugrad) chronologically ==='
SELECT m.message_id, m.posted_at, u.username AS sender, m.body
FROM Message m JOIN Users u ON u.user_id=m.sender_id
WHERE m.channel_id=3
ORDER BY m.posted_at, m.message_id;

\echo
\echo '=== (6) All messages by user 4 (dave) ==='
SELECT m.message_id, m.posted_at, w.name AS ws, c.name AS ch, c.ch_type, m.body
FROM Message m
JOIN Channel c   ON c.channel_id=m.channel_id
JOIN Workspace w ON w.workspace_id=c.workspace_id
WHERE m.sender_id=4
ORDER BY m.posted_at DESC;

\echo
\echo '=== (7) Messages accessible to user 5 (eve) containing perpendicular ==='
SELECT m.message_id, m.posted_at, w.name AS ws, c.name AS ch, s.username AS sender, m.body
FROM Message m
JOIN Channel c          ON c.channel_id=m.channel_id
JOIN Workspace w        ON w.workspace_id=c.workspace_id
JOIN ChannelMember cm   ON cm.channel_id=c.channel_id AND cm.user_id=5
JOIN WorkspaceMember wm ON wm.workspace_id=w.workspace_id AND wm.user_id=5
JOIN Users s            ON s.user_id=m.sender_id
WHERE m.body ILIKE '%perpendicular%'
ORDER BY m.posted_at DESC;

\echo
\echo '=== (7b) Same query for user 6 (frank) -- should NOT see #grad-admissions msg ==='
SELECT m.message_id, c.name AS ch, m.body
FROM Message m
JOIN Channel c          ON c.channel_id=m.channel_id
JOIN Workspace w        ON w.workspace_id=c.workspace_id
JOIN ChannelMember cm   ON cm.channel_id=c.channel_id AND cm.user_id=6
JOIN WorkspaceMember wm ON wm.workspace_id=w.workspace_id AND wm.user_id=6
WHERE m.body ILIKE '%perpendicular%';

-- =====================================================================
-- snickr  -  Required SQL queries (Part c, items 1-7)
-- Placeholders use the :name notation (psql variables) for clarity.
-- =====================================================================

-- ---------------------------------------------------------------------
-- (1) Create a new user account.
-- ---------------------------------------------------------------------
INSERT INTO Users (email, username, nickname, password_hash)
VALUES (:email, :username, :nickname, :password_hash);

-- ---------------------------------------------------------------------
-- (2) Create a new public channel inside a workspace by a particular
--     user.  The user is "authorized" iff they are a member of the
--     workspace.  We use INSERT ... SELECT so that the row is only
--     created when the authorization check succeeds.
--     A second statement adds the creator as the first channel member.
-- ---------------------------------------------------------------------
WITH new_ch AS (
    INSERT INTO Channel (workspace_id, name, ch_type, creator_id)
    SELECT :workspace_id, :channel_name, 'public', :user_id
    WHERE EXISTS (
        SELECT 1 FROM WorkspaceMember
        WHERE workspace_id = :workspace_id
          AND user_id      = :user_id
    )
    RETURNING channel_id
)
INSERT INTO ChannelMember (channel_id, user_id)
SELECT channel_id, :user_id FROM new_ch;

-- ---------------------------------------------------------------------
-- (3) For each workspace, list all current administrators.
-- ---------------------------------------------------------------------
SELECT w.workspace_id,
       w.name      AS workspace_name,
       u.user_id,
       u.username,
       u.nickname
FROM   Workspace        w
JOIN   WorkspaceMember  wm ON wm.workspace_id = w.workspace_id
JOIN   Users            u  ON u.user_id       = wm.user_id
WHERE  wm.is_admin = TRUE
ORDER BY w.workspace_id, u.username;

-- ---------------------------------------------------------------------
-- (4) For each public channel in a given workspace, the number of
--     users that were invited more than 5 days ago and have not yet
--     joined.
-- ---------------------------------------------------------------------
SELECT c.channel_id,
       c.name AS channel_name,
       COUNT(*) AS pending_old_invites
FROM   Channel           c
JOIN   ChannelInvitation ci ON ci.channel_id = c.channel_id
WHERE  c.workspace_id = :workspace_id
  AND  c.ch_type      = 'public'
  AND  ci.status      = 'pending'
  AND  ci.invited_at  < CURRENT_TIMESTAMP - INTERVAL '5 days'
  AND  NOT EXISTS (
        SELECT 1 FROM ChannelMember cm
        WHERE cm.channel_id = ci.channel_id
          AND cm.user_id    = ci.invitee_id
       )
GROUP BY c.channel_id, c.name
ORDER BY c.name;

-- ---------------------------------------------------------------------
-- (5) For a particular channel, list all messages in chronological order.
-- ---------------------------------------------------------------------
SELECT m.message_id,
       m.posted_at,
       u.username AS sender,
       m.body
FROM   Message m
JOIN   Users   u ON u.user_id = m.sender_id
WHERE  m.channel_id = :channel_id
ORDER BY m.posted_at ASC, m.message_id ASC;

-- ---------------------------------------------------------------------
-- (6) For a particular user, list all messages they have posted in
--     any channel.
-- ---------------------------------------------------------------------
SELECT m.message_id,
       m.posted_at,
       w.name AS workspace_name,
       c.name AS channel_name,
       c.ch_type,
       m.body
FROM   Message    m
JOIN   Channel    c ON c.channel_id   = m.channel_id
JOIN   Workspace  w ON w.workspace_id = c.workspace_id
WHERE  m.sender_id = :user_id
ORDER BY m.posted_at DESC;

-- ---------------------------------------------------------------------
-- (7) For a particular user, all messages accessible to that user
--     containing the keyword 'perpendicular'.  Accessible means:
--       - user is a member of the workspace, AND
--       - user is a member of the specific channel
--         (the second condition is the strict one and implies the
--         first for any well-formed dataset, but we check both
--         explicitly to match the spec).
-- ---------------------------------------------------------------------
SELECT m.message_id,
       m.posted_at,
       w.name  AS workspace_name,
       c.name  AS channel_name,
       sender.username AS sender,
       m.body
FROM   Message          m
JOIN   Channel          c       ON c.channel_id    = m.channel_id
JOIN   Workspace        w       ON w.workspace_id  = c.workspace_id
JOIN   ChannelMember    cm      ON cm.channel_id   = c.channel_id
                                AND cm.user_id     = :user_id
JOIN   WorkspaceMember  wm      ON wm.workspace_id = w.workspace_id
                                AND wm.user_id     = :user_id
JOIN   Users            sender  ON sender.user_id  = m.sender_id
WHERE  m.body ILIKE '%perpendicular%'
ORDER BY m.posted_at DESC;

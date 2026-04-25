-- =====================================================================
-- snickr  -  Sample data for testing.
-- 6 users, 2 workspaces, 5 channels, 1 direct conversation, ~14 messages,
-- plus invitations covering all 4 statuses and an "old" pending invite
-- so query (4) returns a non-empty result.
-- =====================================================================

-- ---------- USERS ----------------------------------------------------
INSERT INTO Users (email, username, nickname, password_hash) VALUES
  ('alice@example.com', 'alice',   'Alice A.',  'hash_alice'),     -- 1
  ('bob@example.com',   'bob',     'Bobby',     'hash_bob'),       -- 2
  ('carol@example.com', 'carol',   'Carol C.',  'hash_carol'),     -- 3
  ('dave@nyu.edu',      'dave',    'Dave D.',   'hash_dave'),      -- 4
  ('eve@nyu.edu',       'eve',     'Eve E.',    'hash_eve'),       -- 5
  ('frank@nyu.edu',     'frank',   'Frank F.',  'hash_frank');     -- 6

-- ---------- WORKSPACES -----------------------------------------------
INSERT INTO Workspace (name, description, creator_id) VALUES
  ('Acme Inc.',     'Internal company workspace',  1),  -- ws 1, by alice
  ('NYU CS Dept.',  'Faculty discussions',         4);  -- ws 2, by dave

-- ---------- WORKSPACE MEMBERS ----------------------------------------
-- creator is admin; we backdate joined_at slightly for realism
INSERT INTO WorkspaceMember (workspace_id, user_id, is_admin, joined_at) VALUES
  (1, 1, TRUE,  CURRENT_TIMESTAMP - INTERVAL '30 days'),
  (1, 2, TRUE,  CURRENT_TIMESTAMP - INTERVAL '20 days'),  -- bob promoted
  (1, 3, FALSE, CURRENT_TIMESTAMP - INTERVAL '20 days'),
  (2, 4, TRUE,  CURRENT_TIMESTAMP - INTERVAL '60 days'),
  (2, 5, FALSE, CURRENT_TIMESTAMP - INTERVAL '40 days'),
  (2, 6, FALSE, CURRENT_TIMESTAMP - INTERVAL '40 days');

-- ---------- WORKSPACE INVITATIONS ------------------------------------
-- one accepted (carol), one pending (dave -> not yet a member of Acme),
-- one declined (frank), one revoked (already-handled).
INSERT INTO WorkspaceInvitation
  (workspace_id, invitee_email, invited_by, invited_at, status, responded_at) VALUES
  (1, 'carol@example.com', 1, CURRENT_TIMESTAMP - INTERVAL '21 days', 'accepted',
       CURRENT_TIMESTAMP - INTERVAL '20 days'),
  (1, 'dave@nyu.edu',      1, CURRENT_TIMESTAMP - INTERVAL '2 days',  'pending', NULL),
  (2, 'frank@nyu.edu',     4, CURRENT_TIMESTAMP - INTERVAL '50 days', 'accepted',
       CURRENT_TIMESTAMP - INTERVAL '40 days'),
  (2, 'alice@example.com', 4, CURRENT_TIMESTAMP - INTERVAL '10 days', 'declined',
       CURRENT_TIMESTAMP - INTERVAL '9 days');

-- ---------- CHANNELS -------------------------------------------------
-- workspace 1 (Acme): #general (public), #hiring (private)
-- workspace 2 (NYU):  #ugrad (public), #grad-admissions (public),
--                     #promotion (private), plus a direct dave<->eve.
INSERT INTO Channel (workspace_id, name, ch_type, creator_id, created_at) VALUES
  (1, 'general',         'public',  1, CURRENT_TIMESTAMP - INTERVAL '30 days'), -- 1
  (1, 'hiring',          'private', 2, CURRENT_TIMESTAMP - INTERVAL '15 days'), -- 2
  (2, 'ugrad',           'public',  4, CURRENT_TIMESTAMP - INTERVAL '60 days'), -- 3
  (2, 'grad-admissions', 'public',  4, CURRENT_TIMESTAMP - INTERVAL '60 days'), -- 4
  (2, 'promotion',       'private', 4, CURRENT_TIMESTAMP - INTERVAL '40 days'), -- 5
  (2, NULL,              'direct',  4, CURRENT_TIMESTAMP - INTERVAL '10 days'); -- 6

-- ---------- CHANNEL MEMBERS -----------------------------------------
INSERT INTO ChannelMember (channel_id, user_id, joined_at) VALUES
  -- #general (everyone in Acme)
  (1, 1, CURRENT_TIMESTAMP - INTERVAL '30 days'),
  (1, 2, CURRENT_TIMESTAMP - INTERVAL '20 days'),
  (1, 3, CURRENT_TIMESTAMP - INTERVAL '19 days'),
  -- #hiring (alice + bob only)
  (2, 1, CURRENT_TIMESTAMP - INTERVAL '15 days'),
  (2, 2, CURRENT_TIMESTAMP - INTERVAL '15 days'),
  -- #ugrad (all three NYU)
  (3, 4, CURRENT_TIMESTAMP - INTERVAL '60 days'),
  (3, 5, CURRENT_TIMESTAMP - INTERVAL '40 days'),
  (3, 6, CURRENT_TIMESTAMP - INTERVAL '40 days'),
  -- #grad-admissions (dave + eve so far; frank is invited but not joined)
  (4, 4, CURRENT_TIMESTAMP - INTERVAL '60 days'),
  (4, 5, CURRENT_TIMESTAMP - INTERVAL '40 days'),
  -- #promotion (dave alone)
  (5, 4, CURRENT_TIMESTAMP - INTERVAL '40 days'),
  -- direct dave <-> eve
  (6, 4, CURRENT_TIMESTAMP - INTERVAL '10 days'),
  (6, 5, CURRENT_TIMESTAMP - INTERVAL '10 days');

-- ---------- CHANNEL INVITATIONS --------------------------------------
-- ch 4 (#grad-admissions): old pending invite for frank  -> query (4) hit
-- ch 4: recent (within 5d) pending invite for alice      -> excluded
-- ch 3 (#ugrad):  old pending for alice                  -> hit
-- ch 5 (#promotion, private): pending for eve            -> not in query 4
-- One accepted invite to bob in #ugrad (he then "joined" -> removed
--   from candidates by NOT EXISTS).
INSERT INTO ChannelInvitation
  (channel_id, invitee_id, invited_by, invited_at, status) VALUES
  (4, 6, 4, CURRENT_TIMESTAMP - INTERVAL '8 days',  'pending'),  -- frank, OLD
  (4, 1, 4, CURRENT_TIMESTAMP - INTERVAL '1 day',   'pending'),  -- alice, recent
  (3, 1, 4, CURRENT_TIMESTAMP - INTERVAL '7 days',  'pending'),  -- alice, OLD
  (5, 5, 4, CURRENT_TIMESTAMP - INTERVAL '20 days', 'pending');  -- eve, private

-- ---------- MESSAGES -------------------------------------------------
INSERT INTO Message (channel_id, sender_id, body, posted_at) VALUES
  -- #general
  (1, 1, 'Welcome to Acme everyone!',                       CURRENT_TIMESTAMP - INTERVAL '29 days'),
  (1, 2, 'Glad to be here.',                                 CURRENT_TIMESTAMP - INTERVAL '28 days'),
  (1, 3, 'Hello team, looking forward to working with you.', CURRENT_TIMESTAMP - INTERVAL '18 days'),
  -- #hiring
  (2, 2, 'We have 3 candidates lined up for next week.',     CURRENT_TIMESTAMP - INTERVAL '14 days'),
  (2, 1, 'Great, let''s sync Friday.',                       CURRENT_TIMESTAMP - INTERVAL '13 days'),
  -- #ugrad
  (3, 4, 'The new curriculum proposal is ready for review.', CURRENT_TIMESTAMP - INTERVAL '20 days'),
  (3, 5, 'I think the geometry section needs work - the perpendicular bisector exercises are confusing.',
                                                              CURRENT_TIMESTAMP - INTERVAL '19 days'),
  (3, 6, 'Agreed, the perpendicular projection lab is too long.',
                                                              CURRENT_TIMESTAMP - INTERVAL '18 days'),
  -- #grad-admissions
  (4, 4, 'Application deadline reminder: Dec 15.',           CURRENT_TIMESTAMP - INTERVAL '10 days'),
  (4, 5, 'Got it, I will send out the perpendicular admissions matrix later today.',
                                                              CURRENT_TIMESTAMP - INTERVAL '9 days'),
  -- #promotion (private; only dave; eve still pending invite)
  (5, 4, 'Drafting the committee charter.',                   CURRENT_TIMESTAMP - INTERVAL '30 days'),
  -- direct dave<->eve
  (6, 4, 'Quick chat tomorrow?',                              CURRENT_TIMESTAMP - INTERVAL '9 days'),
  (6, 5, 'Sure, 10am works.',                                 CURRENT_TIMESTAMP - INTERVAL '9 days'),
  (6, 4, 'Also, the perpendicular comment in #ugrad earlier was spot-on.',
                                                              CURRENT_TIMESTAMP - INTERVAL '8 days');

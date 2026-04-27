# snickr — Database Design Report

**Course:** CS6083, Spring 2026 — Project #1  
**Due:** April 27, 2026

---

## Overview

Snickr is a Slack-like collaboration platform where users sign up with an email, choose a username and password, then create or join workspaces. Inside a workspace, members create channels of three kinds: public, private, and direct. Messages are exchanged chronologically within these channels.

This document addresses project requirements (a) through (e) as specified in the assignment.

---

## (a) Design and Justify an Appropriate Database Schema

### Entity-Relationship Design

#### Core Entities

The data model centers on four core entities:
- **User** - A sign-up account (email, username, nickname, password_hash)
- **Workspace** - Top-level container for channels and members (name, description, creator)
- **Channel** - Chat room of one of three types within a workspace (name, type, creator)
- **Message** - Text posted by users chronologically within channels (body, sender, timestamp)

#### Relationships and Junction Tables

- **WorkspaceMember** - Many-to-many relationship between User and Workspace, storing membership and admin status
- **ChannelMember** - Many-to-many relationship between User and Channel, tracking membership
- **WorkspaceInvitation** - Invitations from users to email addresses (email-based, allows pre-registration)
- **ChannelInvitation** - Invitations within workspaces to existing users
- **Message Authorship** - One-to-many from Users to Messages

#### ER Diagram

```
                ┌────────┐
                │ Users  │
                └────┬───┘
       creates       │  posts
   ┌────────────────-┼────────────────┐
   ▼                 ▼                 ▼
┌───────────┐   ┌──────────────┐   ┌──────────┐
│ Workspace │◄──┤WorkspaceMember├──►│  Users   │
└─────┬─────┘   └──────────────┘   └──────────┘
      │ contains              ▲
      ▼                       │
┌───────────┐   ┌──────────────┐   ┌──────────┐
│  Channel  │◄──┤ChannelMember ├──►│  Users   │
└─────┬─────┘   └──────────────┘   └──────────┘
      │ contains
      ▼
┌───────────┐
│  Message  │ (sender_id → Users)
└───────────┘

WorkspaceInvitation : (Workspace, email) → invited_by(User), status, responded_at
ChannelInvitation   : (Channel, invitee) → invited_by(User), status, responded_at
```

### Relational Schema and Design Justification

The schema is composed of eight tables with clearly defined keys, foreign key constraints, and validation rules. Each design decision is justified with reference to the project requirements.

#### Eight Tables with Keys and Foreign Keys

| Table | Primary Key | Unique Keys | Foreign Keys | Delete Behavior |
|-------|-------------|-------------|--------------|-----------------|
| Users | user_id (BIGINT GENERATED) | email, username | None | — |
| Workspace | workspace_id (BIGINT GENERATED) | name | creator_id → Users | RESTRICT on creator |
| WorkspaceMember | (workspace_id, user_id) | None | workspace_id → Workspace, user_id → Users | CASCADE both |
| WorkspaceInvitation | (workspace_id, invitee_email) | None | workspace_id → Workspace, invited_by → Users | CASCADE workspace |
| Channel | channel_id (BIGINT GENERATED) | (workspace_id, name) WHERE ch_type != 'direct' | workspace_id → Workspace, creator_id → Users | CASCADE workspace |
| ChannelMember | (channel_id, user_id) | None | channel_id → Channel, user_id → Users | CASCADE both |
| ChannelInvitation | (channel_id, invitee_id) | None | channel_id → Channel, invitee_id → Users, invited_by → Users | CASCADE channel |
| Message | message_id (BIGINT GENERATED) | None | channel_id → Channel, sender_id → Users | CASCADE channel |

**Important Design Note on Invitations:**
The WORKSPACE_INVITATION table intentionally does not use a foreign key for invitee_email, since the spec allows inviting someone who hasn't registered yet. Once they sign up and accept, a WORKSPACE_MEMBER row is created and the status changes to 'accepted'. Channel invitations, by contrast, do require user_id to exist because you can only be invited to a channel inside a workspace you're already a member of.

#### CHECK Constraints and Validation

| Table | Constraint | Purpose |
|-------|-----------|---------|
| Users | email LIKE '_%@_%.__%' | Basic email shape validation |
| Users | username matches [A-Za-z0-9_.-], length 3-40 | Username format and length |
| Workspace | (implicit via UNIQUE) | Workspace names must be globally unique |
| Channel | ch_type IN (public, private, direct) | Channel type restricted to three values |
| Channel | ch_type = 'direct' OR name IS NOT NULL | Direct channels don't require names; others must |
| Channel | partial unique index: (workspace_id, name) WHERE ch_type != 'direct' | Channel names unique per workspace except direct |
| WorkspaceInvitation | status IN (pending, accepted, declined, revoked) | Invitation state machine |
| ChannelInvitation | status IN (pending, accepted, declined, revoked) | Invitation state machine |

#### Design Assumptions and Rationale

**1. Surrogate Keys for Primary Identity**
Slack-scale datasets quickly exceed 32-bit integers. Natural keys like email and workspace names are wide and expensive as foreign key references. Surrogate BIGINT keys allow usernames and channel names to change without cascading updates.

**2. Email Uniqueness is Global**
Email is the spec's sign-up identifier. Each email belongs to exactly one user. This is enforced via UNIQUE constraint and simplifies authentication.

**3. Workspace Names are Globally Unique**
Simplifies discovery and invitation. Future versions could relax this to per-creator uniqueness (creator_id, name) if needed.

**4. Admin Status as a Boolean Column**
Rather than a separate Administrator table, is_admin BOOLEAN in WorkspaceMember models admin status directly. This works because every admin must also be a member, avoiding redundant referential constraints.

**5. Workspace Invitations Use Email (Not user_id)**
The spec explicitly allows inviting someone who hasn't signed up yet. Email-based invitations support this. After sign-up and acceptance, a WorkspaceMember row is inserted and the invitation status becomes 'accepted'.

**6. Channel Invitations Use user_id (Recipient Must Exist)**
Channel invitations only make sense for existing workspace members. Direct user_id references provide simpler validation and no ambiguity about unregistered invitees.

**7. Direct Channels Have No Name**
Direct (1-to-1) channels are identified solely by their two ChannelMember rows. This avoids synthetic names like dm-3-7, since the UI normally shows the other participant. The partial unique index allows multiple unnamed direct channels in a workspace without constraint violations.

**8. No Cascading Delete on Creator Foreign Keys**
Workspace.creator_id has ON DELETE RESTRICT and Channel.creator_id has no cascade. Deleting a user should not silently delete their workspaces or channels. This prevents accidental data loss; a production system would reassign ownership or archive instead.

**9. Timestamps on All Actions**
Every significant action is timestamped: user creation, workspace creation, message posting, invitation send/respond, and member join. This is required for Query 4 and enables audit trails. posted_at and joined_at are indexed for performance.

**10. No Deletion of Messages or Channels**
The spec does not require deletion support. Cascading deletes exist for administrative cleanup (workspace deletion cascades to channels and messages), but the application doesn't expose delete endpoints. This simplifies the model and keeps audit trails intact.

**11. No Permission Rows or Views for Access Control**
The database itself is not multi-tenant. All data is visible to the application code. Access control is enforced in the application layer via session cookies and membership checks, not via database permissions. Per the spec: the system sees all content but enforces access at the application level.

**12. Space Efficiency**
We use surrogate BIGINT PKs instead of wide natural keys. Membership and admin status share one WorkspaceMember row instead of duplicating data in a separate Administrator table. Direct channels don't store names (nullable column with partial unique index). Invitations and memberships are separate to avoid storing per-row invited_by/invited_at on every membership.

#### Indexes for Query Performance

- idx_msg_channel_time (channel_id, posted_at) — Query 5: chronological message list in a channel
- idx_msg_sender (sender_id) — Query 6: all messages by a user
- idx_msg_body_trgm (GIN, full-text) — Query 7: keyword search on message body
- idx_wm_user, idx_cm_user — Fast "what workspaces/channels does this user belong to?" lookups, used by Query 7 authorization joins and almost every page

Full DDL with all constraints and indexes is in schema.sql

---

## (b) Create the Schema with Constraints

The complete DDL is in [schema.sql](schema.sql), which includes:
- All eight table definitions with GENERATED ALWAYS AS IDENTITY surrogate keys
- Foreign key constraints with appropriate CASCADE/RESTRICT behaviors
- Unique constraints and partial unique indexes
- CHECK constraints for email, username, channel type, and invitation status validation
- Composite indexes on (channel_id, posted_at), (sender_id), and full-text search

Target DBMS: PostgreSQL 14 or later. The schema uses GENERATED ALWAYS AS IDENTITY, partial unique indexes, ILIKE, and GIN full-text indexes—all standard features with equivalents in MySQL 8.0+.

---

## (c) SQL Queries for Required Tasks

All queries handle the required operations for the snickr system. They are designed to enforce authorization and access control at the application level (no DB-level per-user accounts). The full text and executable versions are in [queries.sql](queries.sql) and [test_queries.sql](test_queries.sql). Here is a summary of intent and correctness argument for each.

1. Create a user - Single INSERT. The unique constraints on (email, username) enforce uniqueness; if either collides the insert fails atomically.

2. Create a public channel, with authorization check - Uses INSERT ... SELECT ... WHERE EXISTS so that the channel is created only when the requesting user is already a member of the workspace. The companion INSERT INTO ChannelMember adds the creator. Both statements should run inside a transaction so the channel never exists without its creator being a member.

3. Administrators per workspace - Straight join of Workspace, WorkspaceMember (is_admin), and Users.

4. Pending old invitees per public channel - Joins Channel to ChannelInvitation, filters on ch_type='public', status='pending', invited_at older than 5 days, and excludes anyone who later joined via an EXISTS check against ChannelMember. This is safer than relying on status alone, in case the application forgets to update the status when a user joins.

5. Messages in a channel - Single equality query plus sort. The composite index (channel_id, posted_at) makes this an efficient index range scan.

6. All messages by a user - Equality on sender_id, joined to Channel and Workspace for context.

7. Accessible "perpendicular" messages - The access check is two joins: the user must appear in ChannelMember for the message's channel AND in WorkspaceMember for that channel's workspace. The keyword filter uses ILIKE '%perpendicular%' for case-insensitive search; a production system would use the GIN full-text index with to_tsvector and plainto_tsquery.

---

## (d) Test Data and Query Validation

The data set in sample_data.sql is intentionally small but engineered to hit every edge case required by the seven queries.

### Test Data Overview

The data set in [sample_data.sql](sample_data.sql) is intentionally minimal but engineered to hit every edge case required by the seven queries. It contains 6 users, 2 workspaces, 5 named channels (plus 1 direct channel), and carefully placed invitations and messages.

### Test Data Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ USERS (6 total)                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│ 1. alice@example.com  [alice]   2. bob@example.com        [bob]              │
│ 3. carol@example.com  [carol]   4. dave@nyu.edu          [dave]              │
│ 5. eve@nyu.edu        [eve]     6. frank@nyu.edu         [frank]             │
└──────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌──────────────────────────────────────────────────────────────────────────────┐
│ WORKSPACE 1: "Acme Inc." (creator: alice)                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│ MEMBERS:  alice (admin*), bob (admin*), carol (member)                       │
│ INVITATIONS:                                                                 │
│   - carol@     → ACCEPTED (20d ago → now member)                             │
│   - dave@nyu   → PENDING   (2d ago, cross-org)                               │
│                                                                              │
│ CHANNELS:                                                                    │
│ • #general (public, creator: alice)                                          │
│     members: {alice, bob, carol}                                             │
│     3 messages                                                               │
│                                                                              │
│ • #hiring (private, creator: bob)                                            │
│     members: {alice, bob}                                                    │
│     2 messages                                                               │
└──────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌──────────────────────────────────────────────────────────────────────────────┐
│ WORKSPACE 2: "NYU CS Dept." (creator: dave)                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│ MEMBERS:  dave (admin*), eve (member), frank (member)                        │
│ INVITATIONS:                                                                 │
│   - frank@     → ACCEPTED (40d ago → now member)                             │
│   - alice@     → DECLINED (9d ago)                                           │
│                                                                              │
│ CHANNELS:                                                                    │
│ • #ugrad (public, creator: dave)                                             │
│     members: {dave, eve, frank}                                              │
│     invitations: alice (PENDING, 7d old) ← Query 4 candidate                 │
│     3 messages (2 contain "perpendicular")                                   │
│                                                                              │
│ • #grad-admissions (public, creator: dave)                                   │
│     members: {dave, eve}                                                     │
│     invitations: frank (PENDING, 8d old) ← Query 4 candidate                 │
│                  alice (PENDING, 1d old) ← filtered (too recent)             │
│     2 messages (1 contains "perpendicular")                                  │
│                                                                              │
│ • #promotion (private, creator: dave)                                        │
│     members: {dave}                                                          │
│     invitations: eve (PENDING, 20d old) ← Not in Query 4 (private)           │
│     1 message (dave only, private)                                           │
│                                                                              │
│ • (direct, creator: dave, type: direct, no name)                             │
│     members: {dave, eve}                                                     │
│     3 messages (1 contains "perpendicular")                                  │
└──────────────────────────────────────────────────────────────────────────────┘

LEGEND:
  * = admin
  PENDING invitation 7d+ old = candidate for Query 4
  PENDING invitation <5d old  = filtered by Query 4
  "perpendicular" = keyword for Query 7 testing
```

### Why the Data is Structured This Way

The 6-user, 2-workspace, 5-named-channel test set covers all edge cases required by the 7 queries:

| Feature | How Tested | Location |
|---------|-----------|----------|
| Multiple admins | alice and bob both admin in Acme | ws1, Query 3 |
| Cross-workspace boundaries | alice invited to both but declined ws2 | invitations, Query 7 |
| Old vs. recent pending invites | frank 8d old included, alice 1d old excluded | #grad-admissions, Query 4 |
| Invite to member transition | carol invited 20d ago, now member | ws1, Query 4 NOT EXISTS |
| Private channel with pending invite | eve invited to #promotion but not member | #promotion, Query 7 |
| Keyword access control | "perpendicular" in public, private, direct | Query 7 multi-perspective |
| Chronological ordering | messages from 30d ago to present | Query 5 |
| User message collection | dave has 5 messages across 4 channels | Query 6 |

### Query Validation Results

All queries were tested against the sample data using [test_queries.sql](test_queries.sql). Results are in [test_results.txt](test_results.txt).

All queries were executed via `psql` against the loaded database. Highlights:

- (2a) alice (a member of Acme) successfully creates #random.
- (2b) dave (NOT a member of Acme) is silently rejected with zero rows
  inserted into Channel, demonstrating the inline authorization check.
- (3) Returns alice, bob for Acme and dave for NYU CS, matching the test data.
- (4) Returns #grad-admissions = 1 (frank) and #ugrad = 1 (alice). The 1-day-old
  invite to alice in #grad-admissions is correctly excluded.
- (5) Three #ugrad messages in chronological order.
- (6) Five messages by dave across #ugrad, #grad-admissions, #promotion, and
  the direct channel.
- (7) For eve (member of #ugrad, #grad-admissions, direct) the query returns 4
  messages. For frank (member of #ugrad only) the query returns 2 messages, with
  #grad-admissions and direct messages correctly hidden.

The complete captured output is in test_results.txt.

---

## (e) Documentation and Design Summary

### Operational Notes and Implementation Considerations

Transactions - Query 2 is shown as a CTE INSERT ... RETURNING followed by the membership insert. In production code the two statements should be wrapped in BEGIN ... COMMIT so that a crash between them cannot leave a channel without its creator as a member.

Application-level authorization - As the spec requires, no DB-level user accounts are used for end-users. The web tier authenticates the user via cookies and includes the user's user_id in every authorization predicate. Query 7 shows the canonical example of how per-message access control is implemented as a JOIN on the membership tables.

Password storage - password_hash stores a bcrypt or argon2 hash; the application never stores or transmits plaintext. The column is sized generously (255 chars) to accommodate any reasonable hash format.

Time zones - All timestamps are stored as TIMESTAMP (server-local). In production we would prefer TIMESTAMPTZ, which is a one-line change that doesn't affect any of the queries.

### How to Reproduce and Validate

**Setup:**
```bash
createdb snickr
psql -d snickr -v ON_ERROR_STOP=1 -f schema.sql
psql -d snickr -v ON_ERROR_STOP=1 -f sample_data.sql
psql -d snickr -v ON_ERROR_STOP=1 -f test_queries.sql | tee test_results.txt
```

---

## Summary

This document provides a complete relational database design for snickr that satisfies all project requirements:

- **(a) Design & Schema:** Eight-table design with clear entity relationships, comprehensive justification for each design choice, and full ER diagram.
- **(b) Schema Creation:** Production-ready DDL in schema.sql with foreign key constraints, indexes, and validation rules.
- **(c) Seven Required Queries:** All queries implemented with authorization/access control checks built in.
- **(d) Test Data & Validation:** Minimal but comprehensive test data covering all edge cases, with query results documented.
- **(e) Documentation:** Complete justification of design choices, implementation notes, and reproducibility instructions.

All supporting files (schema.sql, queries.sql, sample_data.sql, test_queries.sql, test_results.txt) are included in the repository.

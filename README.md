# snickr — Database Design Report

**Course:** CS6083, Spring 2026 — Project

---

## 1. Introduction

`snickr` is a Slack-like collaboration platform. Users sign up with an email,
choose a username/nickname/password, and can then create or join *workspaces*
(e.g. one per company or organization). Inside a workspace, members create
*channels* of three kinds — **public**, **private**, and **direct** —
and exchange chronologically ordered text *messages*.

This document covers Part 1 of the project: the **database design**. It
contains:

- the entity-relationship (ER) model and the rationale behind it,
- the relational translation, including keys, foreign keys, and CHECK
  constraints,
- the seven required SQL queries,
- a description of the test data and the results obtained when each query is
  executed against it.

The accompanying files are:

| File | Purpose |
|------|---------|
| `schema.sql`        | DDL for all eight tables, constraints, and indexes |
| `queries.sql`       | The seven required queries with `:placeholder` parameters |
| `sample_data.sql`   | Sample insert statements for testing |
| `test_queries.sql`  | Bound versions of the queries that exercise edge cases |
| `test_results.txt`  | Captured output from running `test_queries.sql` |

The target DBMS is **PostgreSQL 14+**. The schema uses standard SQL where
possible; PostgreSQL-specific features used are `GENERATED ALWAYS AS
IDENTITY`, partial unique indexes, `ILIKE`, and a GIN full-text index.
These all have direct equivalents in MySQL/MariaDB.

---

## 2. Assumptions

A number of design decisions follow from explicit (or implicit) statements in
the project handout. The most important assumptions are:

1. **Email is the global user identifier.** Sign-up is by email, so emails
   must be unique across all users.
2. **Username and email are both unique** and both serve as natural keys, but
   we still use a surrogate `user_id` for foreign-key references because
   usernames may change in the future.
3. **A workspace name is unique** to make discovery and invitation simpler.
   (This could easily be relaxed by replacing the unique constraint with a
   surrogate-only key.)
4. **A user is a member of a workspace** iff there is a row in
   `WorkspaceMember`. A user is an **administrator** of that workspace iff
   that row has `is_admin = TRUE`. Modelling admin-ness as a boolean column
   rather than a separate `Administrator` table avoids a redundant referential
   constraint (every administrator is by definition a member).
5. **Workspace invitations are addressed to an email**, not a `user_id`,
   because the spec explicitly allows inviting people who have not yet signed
   up. After they accept, a `WorkspaceMember` row is added and the
   invitation status moves to `'accepted'`.
6. **Channel invitations**, by contrast, only make sense for existing users
   (you can only be invited to a private/direct channel inside a workspace
   you already belong to). They reference `user_id` directly.
7. **Public channels need no invitation**; any workspace member may join.
   Therefore `ChannelInvitation` only contains rows for private and direct
   channels in normal operation. (For the required Query 4 we still allow
   invitations to public channels — this is how Slack itself works: an
   admin can pre-invite a user even though the channel is open.)
8. **Direct channels** are modelled as channels with `ch_type = 'direct'` and
   exactly two `ChannelMember` rows. They are *not* given a name (the UI
   normally shows the other participant). Because of this the unique
   constraint on `(workspace_id, name)` is a *partial* index that excludes
   direct channels.
9. **No deletion of channels or individual messages** is supported, in line
   with the spec. Cascading deletes are still defined for completeness so
   that removing a workspace cleans up its dependents.
10. **Time stamps** are stored on every action (user/workspace/channel
    creation, message posting, invitation send/response, member join). The
    spec recommends this and it is required for Query 4.

---

## 3. ER Design

### 3.1 Entities

- **User** — sign-up account.
- **Workspace** — top-level container of channels and members.
- **Channel** — chat room of one of three types within a workspace.
- **Message** — text written by a user inside a channel.

### 3.2 Relationships

- **WorkspaceMember** *(many-to-many)* — User ↔ Workspace, with attributes
  `is_admin`, `joined_at`. The administrator role is captured here as a
  boolean rather than a separate entity, since every admin is a member.
- **ChannelMember** *(many-to-many)* — User ↔ Channel, with `joined_at`.
- **WorkspaceInvitation** — A weak relationship from Workspace and Email to
  the user who sent the invite. Email is used because invitees may not yet
  exist as Users.
- **ChannelInvitation** — Weak relationship from Channel to invitee User and
  inviter User.
- **Authorship** *(one-to-many)* — User → Message.
- **Containment** *(one-to-many)* — Channel → Message, Workspace → Channel.

### 3.3 ER diagram (text form)

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

WorkspaceInvitation : (Workspace, email) → invited_by(User), status, ...
ChannelInvitation   : (Channel, invitee User) → invited_by(User), status, ...
```

---

## 4. Relational Translation

The eight tables are summarised here. Full DDL with constraints is in
[`schema.sql`](schema.sql).

| Table | Primary Key | Notable constraints |
|-------|-------------|--------------------|
| `Users` | `user_id` | `UNIQUE(email)`, `UNIQUE(username)`, CHECK on email shape |
| `Workspace` | `workspace_id` | `UNIQUE(name)`, `creator_id → Users` |
| `WorkspaceMember` | `(workspace_id, user_id)` | composite FK to both parents, `is_admin BOOLEAN` |
| `WorkspaceInvitation` | `(workspace_id, invitee_email)` | `status ∈ {pending, accepted, declined, revoked}` |
| `Channel` | `channel_id` | `ch_type ∈ {public, private, direct}`; partial `UNIQUE(workspace_id, name)` excluding direct channels |
| `ChannelMember` | `(channel_id, user_id)` | FKs to Channel and Users |
| `ChannelInvitation` | `(channel_id, invitee_id)` | status enum, FKs to Channel and Users |
| `Message` | `message_id` | FK channel, FK sender, `posted_at` indexed |

### 4.1 Indexes for the required workload

- `idx_msg_channel_time (channel_id, posted_at)` — Query 5 (chronological
  list of messages in a channel).
- `idx_msg_sender (sender_id)` — Query 6.
- `idx_msg_body_trgm` (GIN, full-text) — Query 7 keyword search.
- `idx_wm_user`, `idx_cm_user` — fast "what workspaces/channels does this
  user belong to?" lookups, used by Query 7's authorisation joins and by
  almost every page in the (forthcoming) web UI.

### 4.2 Space efficiency notes

- We use surrogate `BIGINT IDENTITY` PKs because Slack-scale data sets quickly
  exceed 32 bits and the natural keys (email, name) are wide.
- Membership and admin-ness share one row (`WorkspaceMember`) instead of
  duplicating membership data in a separate `Administrator` table.
- Direct channels do not store a name (NULLable column with partial unique
  index), avoiding throwaway synthetic names like `dm-3-7`.
- Invitations and memberships are separate so that we do not need to store
  per-row "invited_by" / "invited_at" on every membership record (most
  workspaces have far more memberships than invitations once stable).

---

## 5. The Seven Required Queries

The full text is in [`queries.sql`](queries.sql); a summary of intent and
correctness argument follows.

1. **Create a user** — single `INSERT`. The unique constraints on
   `(email, username)` enforce uniqueness; if either collides the insert
   fails atomically.
2. **Create a public channel, with authorisation check** — uses
   `INSERT ... SELECT ... WHERE EXISTS` so that the channel is created
   only when the requesting user is already a member of the workspace.
   The companion `INSERT INTO ChannelMember` then adds the creator. Both
   statements should run inside a single transaction so the channel
   never exists without its creator being a member.
3. **Administrators per workspace** — straight join of `Workspace`,
   `WorkspaceMember (is_admin)`, `Users`.
4. **Pending old invitees per public channel** — joins `Channel`
   to `ChannelInvitation`, filters on `ch_type='public'`,
   `status='pending'`, `invited_at < now − 5 days`, and excludes anyone who
   later joined via an `EXISTS` correlated against `ChannelMember`. This is
   safer than relying on `status` alone, in case the application forgets to
   flip the status when a user joins on their own.
5. **Messages in a channel** — single equality + sort. The composite index
   `(channel_id, posted_at)` makes this an index range scan.
6. **All messages by a user** — equality on `sender_id`, joined to
   `Channel` and `Workspace` for context.
7. **Accessible "perpendicular" messages** — the access check is two joins:
   the user must appear in `ChannelMember` for the message's channel **and**
   in `WorkspaceMember` for that channel's workspace. The keyword filter
   uses `ILIKE '%perpendicular%'` which is case-insensitive; for a
   production system the GIN full-text index would be queried with
   `to_tsvector(body) @@ plainto_tsquery('perpendicular')`.

---

## 6. Test Data

The data set in `sample_data.sql` is intentionally small but engineered to
hit every interesting case. A diagram of the data:

```
USERS
  1 alice    2 bob    3 carol    4 dave    5 eve    6 frank

WORKSPACES
  ws1 "Acme Inc."        creator=alice    members={alice*, bob*, carol}
  ws2 "NYU CS Dept."     creator=dave     members={dave*, eve, frank}
                                          (* = admin)

CHANNELS
  ws1 #general    public   members={alice, bob, carol}
  ws1 #hiring     private  members={alice, bob}
  ws2 #ugrad      public   members={dave, eve, frank}
                            invites: alice (pending, 7d old)
  ws2 #grad-admissions public members={dave, eve}
                            invites: frank (pending, 8d old)
                                     alice (pending, 1d old)
  ws2 #promotion  private  members={dave}
                            invites: eve (pending, 20d old)
  ws2 (direct)    direct   members={dave, eve}

WORKSPACE INVITATIONS
  ws1 -> carol@   accepted
  ws1 -> dave@    pending  (cross-org invite)
  ws2 -> frank@   accepted
  ws2 -> alice@   declined

MESSAGES
  - 3 in #general, 2 in #hiring
  - 3 in #ugrad including 2 mentioning "perpendicular"
  - 2 in #grad-admissions including 1 mentioning "perpendicular"
  - 1 in #promotion (private to dave)
  - 3 in the dave<->eve direct channel including 1 mentioning "perpendicular"
```

Why the data is shaped this way:

- **Multiple admins per workspace** (alice and bob in Acme) so Query 3 is
  not trivial.
- **Cross-workspace invitation** (alice declined NYU, dave still pending in
  Acme) to make sure invitation queries do not leak across workspaces.
- **Old vs recent invitations** in the same channel (`#grad-admissions` has
  one 8-day-old and one 1-day-old) to verify the `> 5 days` predicate in
  Query 4.
- **An accepted invitation that became a membership** (carol in ws1) to
  verify the `NOT EXISTS` exclusion in Query 4.
- **Private channel + non-member with a pending invitation** (`#promotion`,
  eve still pending) to make sure Query 7 hides messages even when the
  user is invited but hasn't joined.
- **`perpendicular` keyword** seeded in three different channels covering
  public-but-inaccessible, public-and-accessible, and direct contexts so
  Query 7's authorisation logic can be checked from at least two different
  user perspectives.

### 6.1 Query results (from `test_results.txt`)

All queries were executed via `psql` against the loaded database. Highlights:

- **(2a)** `alice` (a member of Acme) successfully creates `#random`.
- **(2b)** `dave` (NOT a member of Acme) is silently rejected — zero rows
  inserted into `Channel`, demonstrating the inline authorisation check.
- **(3)** Returns `alice, bob` for Acme and `dave` for NYU CS — matches the
  intended seed.
- **(4)** Returns `#grad-admissions = 1` (frank) and `#ugrad = 1` (alice).
  The 1-day-old invite to alice in `#grad-admissions` is correctly excluded.
- **(5)** Three `#ugrad` messages in chronological order.
- **(6)** Five messages by dave across `#ugrad`, `#grad-admissions`,
  `#promotion`, and the direct channel.
- **(7)** For `eve` (member of `#ugrad`, `#grad-admissions`, direct) the
  query returns 4 messages. For `frank` (member of `#ugrad` only) the
  query returns just 2 messages — the `#grad-admissions` and direct
  messages are correctly hidden.

The complete captured output is in `test_results.txt`.

---

## 7. Operational Notes

- **Transactions.** Query 2 is shown as a CTE `INSERT ... RETURNING` followed
  by the membership insert. In production code the two statements should be
  wrapped in `BEGIN ... COMMIT` so that a crash between them cannot leave a
  channel without its creator as a member.
- **Application-level authorisation.** As the spec requires, no DB-level
  user accounts are used for end-users; the web tier authenticates the user
  (via cookies, in Part 2) and includes the user's `user_id` in every
  authorisation predicate. Query 7 is the canonical example of how
  per-message access control is implemented as a `JOIN` on the membership
  tables.
- **Password storage.** `password_hash` stores a bcrypt/argon2 hash; the
  application never stores or transmits plaintext. The column is sized
  generously (255 chars) to accommodate any reasonable hash format.
- **Time zones.** All timestamps are stored as `TIMESTAMP` (server-local).
  In production we would prefer `TIMESTAMPTZ`; this is a one-line change
  and does not affect any of the queries.

---

## 8. How to Reproduce

```bash
createdb snickr
psql -d snickr -v ON_ERROR_STOP=1 -f schema.sql
psql -d snickr -v ON_ERROR_STOP=1 -f sample_data.sql
psql -d snickr -v ON_ERROR_STOP=1 -f test_queries.sql | tee test_results.txt
```

---

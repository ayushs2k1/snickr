# Snickr - Design Documentation

**CS6083 Database Systems Project #2**  
**Spring 2026**

---

## Table of Contents
1. [System Overview](#system-overview)
2. [Architecture](#architecture)
3. [Database Design](#database-design)
4. [Security Implementation](#security-implementation)
5. [User Interface Design](#user-interface-design)
6. [Key Features](#key-features)
7. [Implementation Decisions](#implementation-decisions)

---

## System Overview

Snickr is a web-based collaboration platform inspired by Slack, built with Node.js, Express, PostgreSQL, and EJS templates. The system allows users to create workspaces, organize conversations into channels, send direct messages, and search across all accessible content.

**Technology Stack:**
- **Backend:** Node.js with Express.js framework
- **Database:** PostgreSQL 14+
- **Template Engine:** EJS (Embedded JavaScript)
- **Authentication:** bcrypt for password hashing, express-session for session management
- **Frontend:** Vanilla HTML/CSS (no frameworks)

---

## Architecture

### Three-Tier Architecture

```
┌─────────────────────────────────────┐
│     Presentation Layer (Browser)    │
│  HTML/CSS/Forms → EJS Templates     │
└──────────────┬──────────────────────┘
               │ HTTP/HTTPS
┌──────────────▼──────────────────────┐
│     Application Layer (Node.js)     │
│  Express Routes → Business Logic    │
│  Session Management → Authorization │
└──────────────┬──────────────────────┘
               │ SQL (parameterized)
┌──────────────▼──────────────────────┐
│      Data Layer (PostgreSQL)        │
│  Tables → Constraints → Indexes     │
└─────────────────────────────────────┘
```

### Request Flow

1. **User Action** → Browser sends HTTP request (GET/POST)
2. **Middleware** → Session validation, user authentication
3. **Route Handler** → Business logic, authorization checks
4. **Database Query** → Parameterized SQL via pg library
5. **Response** → EJS template rendered with data
6. **Browser** → HTML/CSS displayed to user

---

## Database Design

### Entity-Relationship Model

**Core Entities:**
- **Users:** Account information, credentials
- **Workspaces:** Top-level organizational units
- **Channels:** Communication spaces (public/private/direct)
- **Messages:** Content posted in channels

**Relationships:**
- **WorkspaceMember:** Many-to-many between Users and Workspaces (includes admin flag)
- **ChannelMember:** Many-to-many between Users and Channels
- **WorkspaceInvitation:** Pending invites by email
- **ChannelInvitation:** Pending invites by user ID

### Key Design Decisions

**1. Email-based Workspace Invitations**
- Invitations use `invitee_email` instead of `user_id`
- Allows inviting users who haven't registered yet
- After registration, user can accept pending invites

**2. Channel Types**
- **Public:** Visible to all workspace members, anyone can join
- **Private:** Only visible to members, requires invitation
- **Direct:** Two-person conversation, name is NULL

**3. Invitation Status Tracking**
- Status: `pending`, `accepted`, `declined`, `revoked`
- `responded_at` timestamp tracks when user acted
- `ON CONFLICT` allows re-inviting (resets to pending)

**4. Access Control in SQL**
- Authorization enforced at query level via JOINs
- Example: Channel access requires both workspace membership AND (public channel OR channel membership)
- Prevents data leaks even if application logic fails

### Indexes

```sql
-- Performance optimization for common queries
CREATE INDEX idx_wm_user ON WorkspaceMember(user_id);
CREATE INDEX idx_cm_user ON ChannelMember(user_id);
CREATE INDEX idx_msg_channel_time ON Message(channel_id, posted_at);
CREATE INDEX idx_msg_sender ON Message(sender_id);
CREATE INDEX idx_msg_body_trgm ON Message USING GIN (to_tsvector('english', body));
```

**Rationale:**
- `idx_wm_user`, `idx_cm_user`: Fast lookup of user's workspaces/channels
- `idx_msg_channel_time`: Efficient message retrieval in chronological order
- `idx_msg_body_trgm`: Full-text search on message content

---

## Security Implementation

### 1. SQL Injection Prevention

**Method:** Parameterized queries using `pg` library's `$1, $2, ...` placeholders

**Example:**
```javascript
// SAFE - parameterized
db.query(`SELECT * FROM Users WHERE username = $1`, [username])

// UNSAFE - string concatenation (NOT USED)
db.query(`SELECT * FROM Users WHERE username = '${username}'`)
```

**Coverage:** All 40+ queries in the application use parameterized statements.

### 2. Cross-Site Scripting (XSS) Prevention

**Method:** EJS auto-escaping with `<%= %>` syntax

**Example:**
```html
<!-- SAFE - auto-escaped -->
<p>Welcome, <%= user.nickname %></p>

<!-- UNSAFE - raw output (NOT USED) -->
<p>Welcome, <%- user.nickname %></p>
```

**Coverage:** All user-generated content (usernames, messages, channel names) is escaped.

### 3. Session Security

**Configuration:**
```javascript
session({
  secret: process.env.SESSION_SECRET,
  cookie: {
    httpOnly: true,      // Prevents JavaScript access
    sameSite: 'lax',     // CSRF protection
    maxAge: 86400000     // 24 hours
  }
})
```

**Features:**
- Session stored in encrypted cookie
- `httpOnly` prevents XSS-based session theft
- `sameSite: 'lax'` prevents CSRF attacks
- Automatic expiration after 24 hours

### 4. Password Security

**Method:** bcrypt hashing with cost factor 12

```javascript
// Registration
const hash = await bcrypt.hash(password, 12);
db.query(`INSERT INTO Users(..., password_hash) VALUES (..., $1)`, [hash]);

// Login
const match = await bcrypt.compare(inputPassword, storedHash);
```

**Features:**
- One-way hashing (cannot be reversed)
- Salt automatically generated per password
- Cost factor 12 = ~250ms computation time (resistant to brute force)

### 5. Concurrency Control

**Method:** Database transactions for multi-step operations

**Example:**
```javascript
await db.tx(async (client) => {
  // Step 1: Create workspace
  const ws = await client.query(`INSERT INTO Workspace...`);
  // Step 2: Add creator as admin
  await client.query(`INSERT INTO WorkspaceMember...`);
  // Both succeed or both roll back
});
```

**Coverage:** All operations that modify multiple tables use transactions.

---

## User Interface Design

### Design Philosophy

**Inspiration:** Slack's clean, functional aesthetic  
**Principles:**
- Clarity over decoration
- Consistent spacing and typography
- Subtle hover states and transitions
- Mobile-responsive layout

### Color Palette

```
Primary Purple:   #350d36  (header background)
Primary Green:    #007a5a  (buttons, success)
Link Blue:        #1264a3  (links, focus states)
Text Dark:        #1d1c1d  (primary text)
Text Muted:       #616061  (secondary text)
Background:       #f8f8f8  (page background)
Card Background:  #ffffff  (content cards)
Border:           #ddd     (subtle borders)
```

### Typography

```
Font Family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto
Base Size:   15px
Line Height: 1.5

Headings:
  h1: 32px, weight 900, letter-spacing -0.5px
  h2: 18px, weight 700
  h3: 15px, weight 700

Body:
  Regular: 15px, weight 400
  Bold:    15px, weight 700
  Muted:   13px, weight 400
```

### Layout Structure

**Header:**
- Fixed-height navigation bar
- Brand logo (left), search bar (center), user menu (right)
- Consistent across all pages

**Main Content:**
- Max-width 1080px, centered
- 32px vertical padding, 24px horizontal padding
- Responsive: collapses to single column on mobile

**Two-Column Layout (Workspace/Channel pages):**
- Left column (2fr): Primary content (channels, messages)
- Right column (1fr): Sidebar (members, actions)
- Grid gap: 32px

### Interactive Elements

**Buttons:**
- Primary: Green background, white text, rounded corners
- Hover: Darker shade + subtle shadow
- Focus: Blue outline ring (accessibility)

**Forms:**
- Labels: Bold, 14px
- Inputs: 10px padding, 1px border, rounded corners
- Focus: Blue border + glow effect (Slack-style)

**Lists:**
- No bullets, clean spacing
- Hover: Light gray background
- Active: Blue text for links

**Messages:**
- White container with border
- Username in bold (weight 900)
- Timestamp in muted gray
- Body text with preserved whitespace

---

## Key Features

### 1. User Registration and Authentication

**Registration:**
- Email, username, nickname, password required
- Email format validated by database CHECK constraint
- Username must be 3-40 characters, alphanumeric + `_.-`
- Password hashed with bcrypt before storage
- Automatic login after successful registration

**Login:**
- Username + password authentication
- bcrypt comparison against stored hash
- Session created on success, valid for 24 hours
- Redirect to home page showing user's workspaces

**Password Reset:**
- Verify username + email combination
- No email server required (demo mode)
- New password hashed and updated in database

### 2. Workspaces

**Creation:**
- Name (required, unique), description (optional)
- Creator automatically added as admin
- Transaction ensures both workspace and membership are created atomically

**Membership:**
- Admin flag determines permissions
- Admins can invite users by email
- Members can create channels and view public channels

**Invitations:**
- Email-based (allows inviting unregistered users)
- Status: pending → accepted/declined
- Re-inviting resets status to pending
- Accepting adds user to WorkspaceMember table

### 3. Channels

**Types:**
- **Public:** Visible to all workspace members, anyone can join
- **Private:** Only visible to members, requires invitation
- **Direct:** Two-person conversation, no name

**Creation:**
- Public/private: Name required
- Direct: Select partner from workspace members
- Creator automatically added as member
- For direct channels, both users added immediately

**Access Control:**
- Public channels: Workspace members can view and join
- Private channels: Only members can view
- Direct channels: Only the two participants can view
- Enforced in SQL via JOIN conditions

**Invitations:**
- Private/public channels: Invite workspace members
- Dropdown shows only non-members
- Status tracking (pending/accepted/declined)

### 4. Messages

**Posting:**
- Text input with preserved whitespace
- Sender, timestamp, body stored in database
- Authorization: Must be channel member to post
- Transaction ensures membership check and insert are atomic

**Display:**
- Chronological order (oldest first)
- Username in bold, timestamp in gray
- Body text with line breaks preserved
- Scrollable container with max-height

### 5. Search

**Functionality:**
- Keyword search across all message bodies
- Case-insensitive (ILIKE operator)
- Results limited to 200 most recent matches
- Only shows messages from channels/workspaces user belongs to

**Authorization:**
- Double JOIN on ChannelMember and WorkspaceMember
- Filters by user_id on both tables
- Prevents access to unauthorized content

**Bookmarkable:**
- URL format: `/search?q=keyword`
- Query string preserved in URL
- Can bookmark and share search results

### 6. Invitations

**Workspace Invitations:**
- Sent by email address
- Displayed on home page for matching users
- Accept → added to workspace as regular member
- Decline → status updated, no membership created

**Channel Invitations:**
- Sent by user ID (must be workspace member)
- Displayed on home page
- Accept → added to channel as member
- Decline → status updated, no membership created

---

## Implementation Decisions

### 1. Why EJS Instead of React/Vue?

**Rationale:**
- Server-side rendering (simpler deployment)
- No build step required
- Auto-escaping prevents XSS by default
- Easier to demonstrate SQL queries (no API layer)
- Meets project requirements without overengineering

### 2. Why Session Cookies Instead of JWT?

**Rationale:**
- Simpler implementation for demo purposes
- express-session handles encryption automatically
- httpOnly cookies prevent XSS theft
- Automatic expiration after 24 hours
- No need for token refresh logic

### 3. Why Transactions for Multi-Step Operations?

**Rationale:**
- Prevents partial writes (e.g., workspace created but creator not added as member)
- Ensures data consistency under concurrent access
- Automatic rollback on error
- Demonstrates proper database usage

### 4. Why Email-Based Workspace Invitations?

**Rationale:**
- Allows inviting users before they register
- Matches real-world collaboration tools (Slack, Discord)
- Subquery maps logged-in user to their email for matching
- More flexible than user ID-based invitations

### 5. Why Access Control in SQL?

**Rationale:**
- Defense in depth (even if app logic fails, DB enforces rules)
- Single source of truth for authorization
- Prevents data leaks via direct DB access
- Demonstrates advanced SQL (JOINs, EXISTS, subqueries)

### 6. Why Parameterized Queries Instead of ORM?

**Rationale:**
- Direct control over SQL for optimization
- Demonstrates understanding of SQL injection prevention
- No abstraction layer hiding query logic
- Easier to debug and explain in documentation

### 7. Why Bookmarkable URLs?

**Rationale:**
- RESTful design principle
- Users can share links to specific workspaces/channels
- Search results can be bookmarked and revisited
- Better user experience (browser back button works correctly)

---

## Future Enhancements

**Not Implemented (Out of Scope for Project):**
- Real-time updates (WebSockets)
- File uploads and attachments
- Message editing and deletion
- Emoji reactions
- Threaded replies
- User presence indicators (online/offline)
- Email notifications for invitations
- Profile pictures and avatars
- Workspace/channel settings and permissions
- Message formatting (bold, italic, code blocks)
- @mentions and notifications

**Why Not Included:**
- Project focuses on database design and SQL
- Real-time features require WebSocket infrastructure
- File uploads require storage and CDN considerations
- These features don't demonstrate additional database concepts

---

## Testing and Validation

### Manual Testing Performed

**Security:**
-  SQL injection: Tested with `' OR '1'='1` in all input fields
-  XSS: Tested with `<script>alert('xss')</script>` in messages
-  Session theft: Verified httpOnly cookie prevents JavaScript access
-  Authorization: Verified private channels hidden from non-members

**Functionality:**
-  User registration with duplicate email/username
-  Login with wrong password
-  Password reset with mismatched email/username
-  Creating workspaces with duplicate names
-  Inviting users to workspaces and channels
-  Accepting and declining invitations
-  Posting messages in channels
-  Searching across messages
-  Joining public channels
-  Creating direct message channels

**Concurrency:**
-  Multiple users posting to same channel simultaneously
-  Accepting invitation while workspace is being modified
-  Creating channel while user is being invited

### Browser Compatibility

**Tested On:**

- Firefox 

**Responsive Design:**
- Laptop

---
## Conclusion

Snickr demonstrates a complete implementation of a database-backed web application with proper security measures, clean architecture, and user-friendly design. The system successfully implements all required features from the project specification while maintaining code quality and following best practices for web development and database design.


-- =====================================================================
-- snickr  -  CS6083 Project #1, Spring 2026
-- Relational schema for a Slack-like collaboration system.
-- Target DBMS: PostgreSQL 14+ (uses CHECK, ENUM-style CHECK, GENERATED IDs).
-- =====================================================================

DROP TABLE IF EXISTS Message              CASCADE;
DROP TABLE IF EXISTS ChannelInvitation    CASCADE;
DROP TABLE IF EXISTS ChannelMember        CASCADE;
DROP TABLE IF EXISTS Channel              CASCADE;
DROP TABLE IF EXISTS WorkspaceInvitation  CASCADE;
DROP TABLE IF EXISTS WorkspaceMember      CASCADE;
DROP TABLE IF EXISTS Workspace            CASCADE;
DROP TABLE IF EXISTS Users                CASCADE;

-- ---------------------------------------------------------------------
-- 1. Users
-- ---------------------------------------------------------------------
CREATE TABLE Users (
    user_id        BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email          VARCHAR(254) NOT NULL UNIQUE,
    username       VARCHAR(40)  NOT NULL UNIQUE,
    nickname       VARCHAR(60)  NOT NULL,
    password_hash  VARCHAR(255) NOT NULL,         -- never store plaintext
    created_at     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_email_shape    CHECK (email LIKE '_%@_%.__%'),
    CONSTRAINT chk_username_shape CHECK (username ~ '^[A-Za-z0-9_.-]{3,40}$')
);

-- ---------------------------------------------------------------------
-- 2. Workspaces
-- ---------------------------------------------------------------------
CREATE TABLE Workspace (
    workspace_id  BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          VARCHAR(80)  NOT NULL UNIQUE,
    description   VARCHAR(500),
    creator_id    BIGINT       NOT NULL,
    created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_ws_creator
        FOREIGN KEY (creator_id) REFERENCES Users(user_id)
        ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------
-- 3. WorkspaceMember     (membership + admin flag)
--    A user is an admin of a workspace iff the row exists with
--    is_admin = TRUE.  The creator is inserted as is_admin = TRUE.
-- ---------------------------------------------------------------------
CREATE TABLE WorkspaceMember (
    workspace_id  BIGINT     NOT NULL,
    user_id       BIGINT     NOT NULL,
    is_admin      BOOLEAN    NOT NULL DEFAULT FALSE,
    joined_at     TIMESTAMP  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (workspace_id, user_id),
    FOREIGN KEY (workspace_id) REFERENCES Workspace(workspace_id) ON DELETE CASCADE,
    FOREIGN KEY (user_id)      REFERENCES Users(user_id)         ON DELETE CASCADE
);
CREATE INDEX idx_wm_user ON WorkspaceMember(user_id);

-- ---------------------------------------------------------------------
-- 4. WorkspaceInvitation
--    invitee_email is used (rather than user_id) because the spec says
--    you may invite someone who has not signed up yet.  After the
--    invitee signs up and accepts, a row is inserted into
--    WorkspaceMember and the invitation status becomes 'accepted'.
-- ---------------------------------------------------------------------
CREATE TABLE WorkspaceInvitation (
    workspace_id   BIGINT       NOT NULL,
    invitee_email  VARCHAR(254) NOT NULL,
    invited_by     BIGINT       NOT NULL,
    invited_at     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status         VARCHAR(10)  NOT NULL DEFAULT 'pending',
    responded_at   TIMESTAMP,
    PRIMARY KEY (workspace_id, invitee_email),
    FOREIGN KEY (workspace_id) REFERENCES Workspace(workspace_id) ON DELETE CASCADE,
    FOREIGN KEY (invited_by)   REFERENCES Users(user_id),
    CONSTRAINT chk_wi_status CHECK (status IN ('pending','accepted','declined','revoked'))
);

-- ---------------------------------------------------------------------
-- 5. Channel
--    type ∈ {public, private, direct}.
--    A channel name is unique within a workspace (NULL allowed for
--    direct channels which we identify by their two members).
-- ---------------------------------------------------------------------
CREATE TABLE Channel (
    channel_id   BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    workspace_id BIGINT      NOT NULL,
    name         VARCHAR(80),
    ch_type      VARCHAR(10) NOT NULL,
    creator_id   BIGINT      NOT NULL,
    created_at   TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (workspace_id) REFERENCES Workspace(workspace_id) ON DELETE CASCADE,
    FOREIGN KEY (creator_id)   REFERENCES Users(user_id),
    CONSTRAINT chk_ch_type CHECK (ch_type IN ('public','private','direct')),
    CONSTRAINT chk_named_when_not_direct
        CHECK (ch_type = 'direct' OR name IS NOT NULL)
);
-- A non-direct channel name must be unique inside its workspace.
CREATE UNIQUE INDEX uq_channel_name_per_ws
    ON Channel(workspace_id, name)
    WHERE ch_type <> 'direct';

-- ---------------------------------------------------------------------
-- 6. ChannelMember
-- ---------------------------------------------------------------------
CREATE TABLE ChannelMember (
    channel_id  BIGINT     NOT NULL,
    user_id     BIGINT     NOT NULL,
    joined_at   TIMESTAMP  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (channel_id, user_id),
    FOREIGN KEY (channel_id) REFERENCES Channel(channel_id) ON DELETE CASCADE,
    FOREIGN KEY (user_id)    REFERENCES Users(user_id)      ON DELETE CASCADE
);
CREATE INDEX idx_cm_user ON ChannelMember(user_id);

-- ---------------------------------------------------------------------
-- 7. ChannelInvitation  (private + direct channels)
--    For direct channels the "invitation" is the row that lets the
--    second user accept the conversation.  For public channels no
--    invitation is required, so rows here will only exist for the
--    other two channel types.
-- ---------------------------------------------------------------------
CREATE TABLE ChannelInvitation (
    channel_id    BIGINT     NOT NULL,
    invitee_id    BIGINT     NOT NULL,
    invited_by    BIGINT     NOT NULL,
    invited_at    TIMESTAMP  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status        VARCHAR(10) NOT NULL DEFAULT 'pending',
    responded_at  TIMESTAMP,
    PRIMARY KEY (channel_id, invitee_id),
    FOREIGN KEY (channel_id) REFERENCES Channel(channel_id) ON DELETE CASCADE,
    FOREIGN KEY (invitee_id) REFERENCES Users(user_id)      ON DELETE CASCADE,
    FOREIGN KEY (invited_by) REFERENCES Users(user_id),
    CONSTRAINT chk_ci_status CHECK (status IN ('pending','accepted','declined','revoked'))
);

-- ---------------------------------------------------------------------
-- 8. Message
-- ---------------------------------------------------------------------
CREATE TABLE Message (
    message_id  BIGINT     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    channel_id  BIGINT     NOT NULL,
    sender_id   BIGINT     NOT NULL,
    body        TEXT       NOT NULL,
    posted_at   TIMESTAMP  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (channel_id) REFERENCES Channel(channel_id) ON DELETE CASCADE,
    FOREIGN KEY (sender_id)  REFERENCES Users(user_id)
);
CREATE INDEX idx_msg_channel_time ON Message(channel_id, posted_at);
CREATE INDEX idx_msg_sender       ON Message(sender_id);
-- Full-text search support for query (7).
CREATE INDEX idx_msg_body_trgm ON Message USING GIN (to_tsvector('english', body));

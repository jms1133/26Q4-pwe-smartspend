-- User accounts; every expense and category now belongs to one user.
-- Applied once by lib/db/migrations.dart inside its transaction; never edit
-- after it has been applied anywhere.

-- Existing rows have no owner, and the new user_id columns are NOT NULL.
-- All data so far is local development data (and the 9 global seed
-- categories from 001), so it is deleted instead of being assigned to a
-- placeholder user. Demo data comes from the seed script; the per-user seed
-- categories are copied on registration (lib/auth/auth_handlers.dart).
DELETE FROM expenses;
DELETE FROM categories;

CREATE TABLE users (
  id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- Stored lowercase by the server; the index also guards against a
  -- mixed-case row inserted by hand.
  username TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX users_username_lower_key ON users (lower(username));

-- Categories: name uniqueness moves from global to per user. The
-- find-or-create ON CONFLICT target must match this index expression exactly:
-- ON CONFLICT (user_id, (lower(name))).
DROP INDEX categories_name_lower_key;

ALTER TABLE categories
  ADD COLUMN user_id INTEGER NOT NULL REFERENCES users ON DELETE CASCADE,
  -- Target for the composite foreign key from expenses below. id alone is
  -- already unique; the pair lets PostgreSQL check the owner as well.
  ADD CONSTRAINT categories_user_id_id_key UNIQUE (user_id, id);

CREATE UNIQUE INDEX categories_user_name_lower_key
  ON categories (user_id, lower(name));

-- Expenses: the category is now referenced by id instead of stored as a name,
-- and the composite foreign key guarantees that an expense can only point to
-- a category of the same user.
ALTER TABLE expenses
  DROP COLUMN category,
  ADD COLUMN user_id INTEGER NOT NULL REFERENCES users ON DELETE CASCADE,
  ADD COLUMN category_id INTEGER NOT NULL,
  ADD CONSTRAINT expenses_user_category_fkey
    FOREIGN KEY (user_id, category_id) REFERENCES categories (user_id, id);

-- Every list query is "this user's expenses, newest first".
CREATE INDEX expenses_user_timestamp_idx
  ON expenses (user_id, timestamp DESC, id DESC);

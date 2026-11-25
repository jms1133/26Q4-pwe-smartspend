-- Initial schema, ported from the SQLite version of the server.
-- Applied once by lib/db/migrations.dart; never edit after it has been
-- applied anywhere. Schema changes go into a new numbered file.

CREATE TABLE categories (
  id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name TEXT NOT NULL
);

-- Case-insensitive uniqueness (replaces SQLite's COLLATE NOCASE UNIQUE).
-- find-or-create targets this index with ON CONFLICT ((lower(name))).
CREATE UNIQUE INDEX categories_name_lower_key ON categories (lower(name));

CREATE TABLE expenses (
  id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title TEXT NOT NULL,
  category TEXT NOT NULL,
  subcategory TEXT,
  description TEXT,
  -- Exact cents, up to 9,999,999,999.99.
  amount NUMERIC(12, 2) NOT NULL,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The former category enum from api.yaml. 'other' is deliberately not
-- seeded (see documentation.md, design decision 6).
INSERT INTO categories (name) VALUES
  ('food'),
  ('transport'),
  ('entertainment'),
  ('housing'),
  ('health'),
  ('insurance'),
  ('shopping'),
  ('subscriptions'),
  ('education');

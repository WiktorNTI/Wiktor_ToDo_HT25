require 'sqlite3'
require_relative 'cat_seeder'

db_path = File.expand_path('todos.db', __dir__)
db = SQLite3::Database.new(db_path)

def seed!(db, db_path)
  puts "Using db file: #{db_path}"
  puts 'Dropping todo table...'
  drop_todo_table(db)
  puts 'Dropping todo_tags table...'
  drop_todo_tags_table(db)
  puts 'Seeding categories...'
  seed_categories!(db, db_path)
  puts 'Creating todo table...'
  create_todo_table(db)
  puts 'Creating todo_tags table...'
  create_todo_tags_table(db)
  puts 'Populating todo table...'
  populate_todos(db)
  puts 'Done seeding the database!'
end

def drop_todo_table(db)
  db.execute('DROP TABLE IF EXISTS todos')
end

def drop_todo_tags_table(db)
  db.execute('DROP TABLE IF EXISTS todo_tags')
end

def create_todo_table(db)
  db.execute('CREATE TABLE todos (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              description TEXT,
              completed BOOL)')
end

def create_todo_tags_table(db)
  db.execute('CREATE TABLE todo_tags (
              todo_id INTEGER NOT NULL,
              category_id INTEGER NOT NULL,
              PRIMARY KEY (todo_id, category_id),
              FOREIGN KEY (todo_id) REFERENCES todos(id),
              FOREIGN KEY (category_id) REFERENCES cat(category_id))')
end

def populate_todos(db)
  db.execute('INSERT INTO todos (name, description, completed) VALUES (?, ?, 0)', ['Köp mjölk', '3 liter mellanmjölk, eko'])
  milk_id = db.last_insert_row_id
  db.execute('INSERT INTO todo_tags (todo_id, category_id) VALUES (?, ?), (?, ?)', [milk_id, 1, milk_id, 3])

  db.execute('INSERT INTO todos (name, description, completed) VALUES (?, ?, 1)', ['Köp julgran', 'En röd gran'])
  tree_id = db.last_insert_row_id
  db.execute('INSERT INTO todo_tags (todo_id, category_id) VALUES (?, ?)', [tree_id, 2])

  db.execute('INSERT INTO todos (name, description, completed) VALUES (?, ?, 0)', ['Pynta gran', 'Glöm inte lamporna i granen och tomten'])
  decorate_id = db.last_insert_row_id
  db.execute('INSERT INTO todo_tags (todo_id, category_id) VALUES (?, ?)', [decorate_id, 4])
end

seed!(db, db_path)

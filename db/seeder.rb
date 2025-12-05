require 'sqlite3'
require_relative 'cat_seeder'

db_path = File.expand_path('todos.db', __dir__)
db = SQLite3::Database.new(db_path)

def seed!(db, db_path)
  puts "Using db file: #{db_path}"
  puts 'Dropping todo table...'
  drop_todo_table(db)
  puts 'Seeding categories...'
  seed_categories!(db, db_path)
  puts 'Creating todo table...'
  create_todo_table(db)
  puts 'Populating todo table...'
  populate_todos(db)
  puts 'Done seeding the database!'
end

def drop_todo_table(db)
  db.execute('DROP TABLE IF EXISTS todos')
end

def create_todo_table(db)
  db.execute('CREATE TABLE todos (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              description TEXT,
              completed BOOL,
              category_id INTEGER,
              FOREIGN KEY (category_id) REFERENCES cat(category_id))')
end

def populate_todos(db)
  db.execute('INSERT INTO todos (name, description, completed, category_id) VALUES (?, ?, 0, 1)', ['Köp mjölk', '3 liter mellanmjölk, eko'])
  db.execute('INSERT INTO todos (name, description, completed, category_id) VALUES (?, ?, 1, 2)', ['Köp julgran', 'En röd gran'])
  db.execute('INSERT INTO todos (name, description, completed, category_id) VALUES (?, ?, 0, 4)', ['Pynta gran', 'Glöm inte lamporna i granen och tomten'])
end

seed!(db, db_path)

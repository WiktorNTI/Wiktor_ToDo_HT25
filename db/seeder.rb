require 'sqlite3'

db_path = File.expand_path('todos.db', __dir__)
db = SQLite3::Database.new(db_path)

def seed!(db, db_path)
  puts "Using db file: #{db_path}"
  puts "Dropping old tables..."
  drop_tables(db)
  puts "Creating tables..."
  create_tables(db)
  puts "Populating tables..."
  populate_tables(db)
  puts "Done seeding the database!"
end

def drop_tables(db)
  db.execute('DROP TABLE IF EXISTS todos')
end

def create_tables(db)
  db.execute('CREATE TABLE todos (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL, 
              description TEXT,
              completed INTEGER NOT NULL DEFAULT 0)')
end

def populate_tables(db)
  db.execute('INSERT INTO todos (name, description, completed) VALUES ("Köp mjölk", "3 liter mellanmjölk, eko", 0)')
  db.execute('INSERT INTO todos (name, description, completed) VALUES ("Köp julgran", "En röd gran", 1)')
  db.execute('INSERT INTO todos (name, description, completed) VALUES ("Pynta gran", "Glöm inte lamporna i granen och tomten", 0)')
end

seed!(db, db_path)

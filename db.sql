CREATE TABLE IF NOT EXISTS User(id INTEGER NOT NULL, name TEXT NOT NULL, PRIMARY KEY(id));
CREATE TABLE IF NOT EXISTS Process(id INTEGER NOT NULL, name TEXT NOT NULL UNIQUE, PRIMARY KEY(id));
CREATE TABLE Window(id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL UNIQUE, handle TEXT, p_id INTEGER NOT NULL, FOREIGN KEY(p_id) REFERENCES Process(id));
CREATE TABLE IF NOT EXISTS Worklog(
			id	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
			p_id	INTEGER NOT NULL,
			pid	INTEGER NOT NULL DEFAULT 0,
			u_id	INTEGER NOT NULL,
			w_id 	INTEGER DEFAULT 0,
			start_date TEXT NOT NULL,
			end_date TEXT NOT NULL,
			idle	INTEGER DEFAULT 0,
			processed	INTEGER DEFAULT 0,
			dns_processed	INTEGER DEFAULT 0,
			FOREIGN KEY(p_id) REFERENCES Process(id),
			FOREIGN KEY(u_id) REFERENCES User(id),
			FOREIGN KEY(w_id) REFERENCES Window(id));
CREATE TABLE DNSClient(
			pid	INTEGER NOT NULL DEFAULT 0,
			query_name	TEXT,
			parent_pid	INTEGER,
			time_created	TEXT);
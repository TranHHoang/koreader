local SQ3 = require("lua-ljsqlite3/init")
local DataStorage = require("datastorage")

local VocabBuilder = {}

local VOCAB_DB_SCHEMA = [[
    CREATE TABLE IF NOT EXISTS Vocab (
        Text       TEXT PRIMARY KEY,
        FileName    TEXT NOT NULL
    )
]]
local VOCAB_INSERT_SQL = "INSERT OR IGNORE INTO Vocab VALUES (?, ?)"
local VOCAB_KEY_EXISTS_SQL = "SELECT count(1) FROM Vocab WHERE Text = ?"
local VOCAB_DELETE_SQL = "DELETE FROM Vocab WHERE Text = ?"

local db_location = DataStorage:getSettingsDir().."/vocab.sqlite3"

function VocabBuilder:init()
    if self.conn then return end

    self.conn = SQ3.open(db_location)
    self.conn:exec(VOCAB_DB_SCHEMA)

    self.insert_stmt = self.conn:prepare(VOCAB_INSERT_SQL)
    self.exists_stmt = self.conn:prepare(VOCAB_KEY_EXISTS_SQL)
    self.delete_stmt = self.conn:prepare(VOCAB_DELETE_SQL)
end

function VocabBuilder:exists(vocab)
    local result = self.exists_stmt:reset():bind(vocab):step()
    local num = tonumber(result[1])

    return num == 1
end

function VocabBuilder:add(vocab, file)
    self.insert_stmt:reset():bind(vocab, file):step()
end

function VocabBuilder:delete(vocab)
    self.delete_stmt:reset():bind(vocab):step()
end

function VocabBuilder:close()
    if self.conn then
        self.insert_stmt:close()
        self.exists_stmt:close()
        self.conn:close()
        self.conn = nil
    end
end

return VocabBuilder
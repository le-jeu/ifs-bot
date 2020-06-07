local sqlite3 = require("lsqlite3")

local function mapDB(model, f, s, v)
  local function domap(...)
    v = ...
    if v ~= nil then
      return model:from(v, true)
    end
  end
  return function()
    return domap(f(s, v))
  end
end

-- convert number to boolean and use default for everything else
local function value2boolean(n, default)
	if n == true or n == false then
		return n
	end
	if type(n) == 'number' then
		return n ~= 0
	end
	return default and true or false
end

local function convert_from_sql(type, value)
	if value == nil then
		return nil
	end
	if type == 'BOOLEAN' then
		return value2boolean(value)
	end
	return value
end

local function convert_to_sql(type, value)
	if value == nil then
		return nil
	end
	if type == 'BOOLEAN' then
		return value and 1 or 0
	end
	return value
end

local function open(db)
	db:trace(function(udata, ...) print(...) end)
	local Model = { db = db}
	Model.__index = Model
	function Model:model(description)
	    local name = description.__tablename__
	    local primary = description.__primarykey__ or 'rowid'
		local fieldsType = {}
		local fieldsName = {}
		for k,v in pairs(description) do
			if k:sub(1,1) ~= '_' then
				fieldsType[k] = v
				table.insert(fieldsName, k)
			end
		end

	    local sql_fields = {}
		for k,v in pairs(fieldsType) do
			local entry = k .. ' ' .. v
			if k == primary then
				entry = entry .. ' PRIMARY KEY'
			end
			table.insert(sql_fields, entry)
		end
		db:exec(string.format("CREATE TABLE %s (%s);", name, table.concat(sql_fields, ', ')))

	    local meta = { name = name, primary = primary, fields = fieldsName, fieldsType = fieldsType }
	    meta.__index = self.index
	    meta.__newindex = self.newindex
	    return setmetatable(meta, self)
	end

	function Model:newindex(field, value)
		if self.__table__.fieldsType[field] and self.__table__.primary ~= field then
			local value = convert_to_sql(self.__table__.fieldsType[field], value)
			if self['_' .. field] ~= value then
				rawset(self, '_' .. field, value)
				self.__table__.update(self, field)
			end
		end
	end

	function Model:index(field)
		if self.__table__.fieldsType[field] then
			return convert_from_sql(self.__table__.fieldsType[field], rawget(self, '_' .. field))
		end
	end

	function Model:insert_list(list)
		if #list > 1 then db:exec 'BEGIN' end
		local sql = string.format(
			"INSERT INTO %s(%s) VALUES (:_%s);",
			self.name,
			table.concat(self.fields, ', '),
			table.concat(self.fields, ', :_')
		)
		local stmt = assert(db:prepare(sql), db:errmsg() .. ': ' .. sql)
		for i,instance in ipairs(list) do
			stmt:reset()
			stmt:bind_names(instance)
			stmt:step()
		end
		local ret = stmt:finalize()
		if #list > 1 then ret = db:exec 'COMMIT' end
		return ret
	end

	function Model:insert(instance)
		return self:insert_list{instance}
	end

	function Model:insert_from_list(list)
		local instances = {}
		for i,item in ipairs(list) do
			table.insert(instances, self:from(item))
		end
		return self:insert_list(instances)
	end

	function Model:insert_from(item)
		return self:insert_from_list{item}
	end

	function Model:update(field)
		if self.__table__.fieldsType[field] and self.__table__.primary ~= field then
			local sql = string.format(
				"UPDATE %s SET %s=:_%s WHERE %s=:_%s",
				self.__table__.name,
				field, field,
				self.__table__.primary, self.__table__.primary)
			local stmt = db:prepare(sql)
			stmt:bind_names(self)
			stmt:step()
			stmt:finalize()
		end
	end

	function Model:all_iterator()
		return mapDB(self, db:nrows("SELECT * FROM " .. self.name))
	end

	function Model:all()
		local ret = {}
		for r in self:all_iterator() do
			table.insert(ret, r)
		end
		return ret
	end

	function Model:where_iterator(kwargs)
		local sql_fields = {}
		for field in pairs(kwargs) do
			if not self.fieldsType[field] then
				return pairs{}
			end
			table.insert(sql_fields, string.format("%s = :%s", field, field))
		end
		local sql = string.format("SELECT * FROM %s WHERE %s", self.name, table.concat(sql_fields, ' AND '))
		local stmt = db:prepare(sql)
		stmt:bind_names(kwargs)
		return mapDB(self, stmt:nrows())
	end

	function Model:where(...)
		local ret = {}
		for r in self:where_iterator(...) do
			table.insert(ret, r)
		end
		return ret
	end

	function Model:get(kwargs)
		local sql_fields = {}
		for field in pairs(kwargs) do
			if not self.fieldsType[field] then
				return
			end
			table.insert(sql_fields, string.format("%s = :%s", field, field))
		end
		local sql = string.format("SELECT * FROM %s WHERE %s LIMIT 1", self.name, table.concat(sql_fields, ' AND '))
		local stmt = db:prepare(sql)
		stmt:bind_names(kwargs)
		for row in stmt:nrows() do
			return self:from(row, true)
		end
	end

	function Model:delete_where(kwargs)
		local sql_fields = {}
		for field in pairs(kwargs) do
			if not self.fieldsType[field] then
				return pairs{}
			end
			table.insert(sql_fields, string.format("%s = :%s", field, field))
		end
		local sql = string.format("DELETE FROM %s WHERE %s", self.name, table.concat(sql_fields, ' AND '))
		local stmt = db:prepare(sql)
		stmt:bind_names(kwargs)
		stmt:step()
		return stmt:finalize()
	end

	function Model:from(obj, from_db)
		if not obj then return end
		return self(obj, true, from_db)
	end

	function Model:__call(init, dont_insert, from_db)
		local instance = {}
		instance.__table__ = self
		for k,v in pairs(self.fieldsType) do
			if from_db then
				instance['_' .. k] = init[k]
			else
				instance['_' .. k] = convert_to_sql(v, init[k])
			end
		end
		setmetatable(instance, self)
		if not dont_insert then
			if self:insert(instance) ~= sqlite3.OK then
				if self.primary and init[self.primary] then
					return self:where{[self.primary] = init[self.primary]}[1]
				end
			end
		end
		return instance
	end

	function Model:close()
		return self.db:close()
	end

	return Model
end

local function open_file(filename)
	return open(sqlite3.open(filename))
end

local function open_memory(filename)
	return open(sqlite3.open_memory())
end

return {
	open = open,
	open_file = open_file,
	open_memory = open_memory,
}

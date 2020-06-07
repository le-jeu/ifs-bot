local orm = require("orm")

return function(filename)
	--local db = orm.open_memory()
	local db = orm.open_file(filename)

	local TelegramUser = db:model {
		__tablename__ = 'telegram_user',
		__primarykey__ = 'user_id',
		user_id = 'TEXT',
		username = 'TEXT',
		member = 'INTEGER',
		admin = 'INTEGER'
	}

	local TelegramPhoto = db:model {
		__tablename__ = 'telegram_photo',
		__primarykey__ = 'file_unique_id',
		file_unique_id = 'TEXT',
		file_id = 'TEXT',
		user_id = 'TEXT', -- foreign key (telegram_user.user_id)
		public = 'INTEGER',
		status = 'TEXT',
		valid = 'INTEGER',
		timestamp = 'INTEGER'
	}

	local IngressAgent = db:model {
		__tablename__ = 'ingress_agent',
		__primarykey__ = 'agent_id',
		agent_id = 'TEXT',
		name = 'TEXT',
		registered = 'INTEGER'
	}

	local PhotoAgent = db:model {
		__tablename__ = 'photo_agent',
		agent_id = 'TEXT', -- foreign key (ingress_agent.agent_id)
		photo_id = 'TEXT', -- foreign key (telegram_photo.file_unique_id)
	}

	local AgentStat = db:model {
		__tablename__ = 'agent_stat',
		agent_id = 'TEXT', -- foreign key (ingress_agent.agent_id)
		timestamp = 'INTEGER',
		time_span = 'TEXT',
    	faction = 'TEXT',
    	date = 'TEXT',
   		time = 'TEXT',
    	level = 'INTEGER',
    	lifetime_ap = 'INTEGER',
    	xm_recharged_portals = 'INTEGER',
	}

	-- db cleanup forcing pseudo foreign key
	db.db:exec [[
		delete from telegram_photo where NOT EXISTS(SELECT 1 FROM telegram_user WHERE telegram_photo.user_id=telegram_user.user_id);
		delete from photo_agent where NOT EXISTS(SELECT 1 FROM telegram_photo WHERE photo_agent.photo_id=telegram_photo.file_unique_id);
		delete from photo_agent where NOT EXISTS(SELECT 1 FROM ingress_agent WHERE photo_agent.agent_id=ingress_agent.agent_id);
	]]

	return {
		TelegramUser = TelegramUser,
		TelegramPhoto = TelegramPhoto,
		IngressAgent = IngressAgent,
		PhotoAgent = PhotoAgent,
		AgentStat = AgentStat
	}
end

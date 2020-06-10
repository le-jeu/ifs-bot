local config = {}

config.db_file = 'foobar.db'

config.bot_token = '<bot api token>'

-- chat id to check people membership
config.chat_membership = 0
-- chat id for admin control
config.admin_chat = 1
-- chat id to forward selfies verification
config.fwd_to = 2

config.update_file = 'updates.json'

config.msg_ok = [[Your selfie has been verified.]]

return config
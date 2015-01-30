default['keymaster']['storage']['master_key'] = '/etc/keymaster/keymaster.key'
default['keymaster']['storage']['path'] = '/etc/keymaster/keys/'
default['keymaster']['key_bag_name'] = 'keymaster'
default['keymaster']['distribute']['every'] = 420
default['keymaster']['user'] = 'keymaster'
default['keymaster']['history'] = {}
# this should be set to `false` in the keymaster role
# so the server itself doesn't apply it
default['keymaster']['client']['enable'] = true

#
# Cookbook Name:: keymaster
# Recipe:: client
#
# Copyright 2012, AWeber - Julien Vehent
#
# All rights reserved - Do Not Redistribute
#

if node['keymaster']['client']['enable'] == false
  return true
end

# Create a UUID to uniquely identify this keymaster client
unless node['keymaster'].has_key?('uuid')
  node['keymaster']['uuid'] = UUIDTools::UUID.random_create.to_s
end

# Create a keymaster user, retrieve the public ssh key from the server
storage = node['keymaster']['storage']['path']
keymaster_user = node['keymaster']['user']
keymaster_home = "/home/#{keymaster_user}/"
keymaster_public_key = []
# If running on Chef Solo, return an empty result
if Chef::Config[:solo]
  Chef::Log.warn("Chef Solo does not support search.")
else
  keymaster_public_key = search(:node, "roles:keymaster AND " \
                                       "chef_environment:#{node.chef_environment}"
                               ).map {|n| n['keymaster']['public_key']}
end
if keymaster_public_key.count < 1
  log("KEYMASTER: no server found. Client not provisionned.") {level :error}
  return true
end

user node['keymaster']['user'] do
  comment  "Receive databag keys"
  system   false
  home     "/home/#{node['keymaster']['user']}"
  shell    "/bin/bash"
  supports :manage_home => true, :non_unique => false
  action   :create
end

directory storage do
  owner keymaster_user
  group keymaster_user
  mode 0700
  recursive true
  action :create
end

directory "#{keymaster_home}/.ssh" do
  not_if "test -d #{keymaster_home}/.ssh"
  owner keymaster_user
  group keymaster_user
  mode 0700
  action :create
end

template "#{keymaster_home}/.ssh/authorized_keys" do
  only_if "test -d #{keymaster_home}/.ssh"
  source "authorized_keys.erb"
  owner node['keymaster']['user']
  group node['keymaster']['user']
  mode  0400
  variables( :public_keys => keymaster_public_key)
end

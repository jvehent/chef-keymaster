#
# Cookbook Name:: keymaster
# Recipe:: default
#
# Copyright 2012, AWeber - Julien Vehent
#
# All rights reserved - Do Not Redistribute
#

def keymaster_already_knows_key?(key, bag, storage_location)
  filepath = "#{storage_location}/#{bag}.key"
  if File.exists?(filepath)
    open(filepath) do |f|
      if f.include?(key)
        log("KEYMASTER: #{bag} is already stored locally")
        return true
      end
    end
  end
  return false
end


def store_key(key, bag, storage_location)
  log("KEYMASTER: writing key #{bag} to #{storage_location}}")
  file "#{storage_location}/#{bag}.key" do
    owner node['keymaster']['user']
    group node['keymaster']['user']
    mode  "0600"
    backup false
    content key
    action  :create
  end
end


def resolve_key_destination(destination)
  ips = search(:node, destination
              ).map{|n| n['network']['lanip'] || n.ipaddress}
  if (ips.count < 1)
    log("KEYMASTER: search '#{destination}' returned empty results.")
  end
  return ips
end


def check_dest_uuid(ip)
  uuid = "none"
  # If running on Chef Solo, return an empty result
  if Chef::Config[:solo]
    Chef::Log.warn("Chef Solo does not support search.")
  else
    r = search(:node, "ipaddress:#{ip} " +
                      "AND chef_environment:#{node.chef_environment}"
              ).map{|n| n['keymaster']['uuid'] || "none"}
    if r.empty?
      Chef::Log.info("Keymaster: Search for '#{ip}' returned empty result.")
    else
      uuid = r.first
    end
  end
  return uuid
end


def distribute(destination, bag, keymaster_user, keymaster_home,
               storage, private_key_path)
  log("KEYMASTER: distributing #{bag} to #{destination}")

  cmd = Chef::ShellOut.new("scp -o StrictHostKeyChecking=no " +
                           "-o NumberOfPasswordPrompts=0 " +
                           "-i #{private_key_path} " +
                           "#{storage}/#{bag}.key " +
                           "#{keymaster_user}@#{destination}:#{storage}/")
  begin
    cmd.run_command
  rescue
    Chef::Log.info("Keymaster: distribution to '#{destination}' failed")
    return false
  end

  if cmd.exitstatus == 0
    return true
  else
    Chef::Log.info("Keymaster: distribution to '#{destination}' failed")
    return false
  end
end


# Create the Keymaster
user node['keymaster']['user'] do
  comment  "Store and Distribute databag keys"
  system   false
  home     "/home/#{node['keymaster']['user']}"
  shell    "/bin/bash"
  supports :manage_home => true, :non_unique => false
  action   :create
end

# -- Variables
#
key_bag = node['keymaster']['key_bag_name']
storage = node['keymaster']['storage']['path']
keymaster_user = node['keymaster']['user']
keymaster_home = "/home/#{keymaster_user}/"
private_key_path = "#{keymaster_home}/.ssh/#{keymaster_user}.priv.key"
distribute_keys = {}

directory storage do
  owner     keymaster_user
  group     keymaster_user
  mode      0700
  recursive true
  action    :create
end

directory "#{keymaster_home}/.ssh" do
  not_if "test -d #{keymaster_home}/.ssh"
  owner  keymaster_user
  group  keymaster_user
  mode   0700
  action :create
end

bash "Generate SSH key pair for user" do
  not_if "test -e #{private_key_path}"
  user   keymaster_user
  cwd    keymaster_home
  code   <<-EOH
         /usr/bin/ssh-keygen -b 2048 -C #{keymaster_user}-at-$(hostname) \
         -q -t rsa -P '' -f #{private_key_path}
         EOH
  action :run
end
if File.exists?(private_key_path)
  node['keymaster']['public_key'] = File.read("#{private_key_path}.pub")
end


has_master_key = true
begin
  masterkey = Chef::EncryptedDataBagItem.load_secret(
                node['keymaster']['storage']['master_key'])
rescue Errno::ENOENT
  log("KEYMASTER: master key not found at " \
      "'#{node['keymaster']['storage']['master_key']}'"){level :error}
  has_master_key = false
end


# download all the keys for this environment from the keymaster databag
if has_master_key
  bags = data_bag(key_bag)

  bags.each do |bag|
    # bag naming convention requires to have the environment in the last part
    # of the name
    if bag =~ /-#{node.chef_environment}$/

      Chef::Log.info("KEYMASTER: decrypting #{bag}")
      items = Chef::EncryptedDataBagItem.load(key_bag, bag, masterkey).to_hash

      # databag must have a destination and a key, otherwise must be skipped
      unless items.key?("destination") and items.key?("key")
        log("Keymaster: Missing items in databag #{bag}"){level :error}
        next
      end

      # if we don't know this key, add it to the list to be distributed
      # and go to the next key
      if not keymaster_already_knows_key?(items["key"], bag, storage)
        store_key(items["key"], bag, storage)
      end

      # We have to resolve the list of destination for each bag every time, to
      # make sure that each destination received the key
      distribute_keys[bag] = resolve_key_destination(items["destination"])
    end
  end
end


# Iterate through the distribution list and check the ones that need to be
# done
distribute_keys.each do |bag, dest_ips|
  dest_ips.each do |dest_ip|

    # check the uuid
    dest_uuid = check_dest_uuid(dest_ip)
    if dest_uuid.eql?("none")
      Chef::Log.info("Keymaster: destination #{dest_ip} doesn't have UUID yet")
      next
    end

    lookup_key = Digest::MD5.hexdigest(masterkey + bag + dest_ip + dest_uuid)

    # If a lookup key exist for this destination + bag, we check when the last
    # distribution was done. If it is older than the set value, redistribute.
    if node['keymaster']['history'].key?(lookup_key)
      last_distrib = node['keymaster']['history'][lookup_key]['last_distribution']
      last = Time.parse(last_distrib)
      delay = (Time.now - (60*node['keymaster']['distribute']['every']))
      if delay < last
        next
      end
    else
      node['keymaster']['history'][lookup_key] = {}
    end

    # The key needs to be (re)distributed to this node
    if distribute(dest_ip, bag, keymaster_user, keymaster_home,
                  storage, private_key_path)
      # register the time of distribution if it succeeded
      node['keymaster']['history'][lookup_key]['last_distribution'] = Time.now
    end
  end
end

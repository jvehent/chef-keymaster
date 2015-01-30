module Keymaster
  module_function

  def decrypt_data_bag_item(databag, item, key_location)
    Chef::Log.info("Keymaster: Decrypting '#{databag}::#{item}' with '#{key_location}'")
    if not File.exists?(key_location)
      raise IOError, "Keymaster: Key not found at '#{key_location}'"
    end
    decryption_key = Chef::EncryptedDataBagItem.load_secret(key_location)
    content = Chef::EncryptedDataBagItem.load(databag, item,
                                              decryption_key).to_hash
    return content
  end
end


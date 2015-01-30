# KeyMaster - Encrypted DataBag Key Distribution Service
This cookbook configures a service that will distribute encryption keys across
the environment.
Encrypted databags are immensely useful, but Chef doesn't provide a mechanism
for managing the keys. Each encrypted databag requires a symetric key. Using
only one symetric key for the entire system defeats the purpose of encryption.

The Keymaster cookbooks provides a method for distributing keys on nodes. It
requires only one Master Key that is manually copied to the keymaster server,
and will be used to distribute all other encryption keys used in encrypted
databags.

## Attributes
Path to the Master key on the keymaster server. __Keep this secure__
```
default[:keymaster][:storage][:master_key] = '/etc/keymaster/keymaster.key'
```

Directory where all the distributed keys will be stored
```
default[:keymaster][:storage][:path] = '/etc/keymaster/keys/'
```

Name of the data bag that contains the keys to be distributed
```
default[:keymaster][:key_bag_name] = 'keymaster'
```

How often to we redistribute the key on a destination node, in minutes.
```
default[:keymaster][:distribute][:every] = 420
```

Name of the keymaster system user that will be SSHing onto the destination nodes.
```
default[:keymaster][:user] = 'keymaster'
```

Enable the keymaster client recipe, should be set to `false` on the keymaster
server.
```
default[:keymaster][:client][:enable] = true
```

### Distribution History
When keys are distributed, a history of the distribution is kept. It's a simple
key value hash, where the key is an identifier of the destination and the
distributed key, and the value is the time of last distribution.


## Principle
### Client side
Each client must run the recipe `keymaster::client` in order to create a keymaster
user locally, and put the public SSH key of the keymaster server into
`/home/keymaster/.ssh/authorized_keys`.
This keymaster server cookbook will connect to the keymaster user on each
destination node, and distribute the keys using SCP.

### Mode of operations
```

    xxxxxxx
   x -    -x                                        +-----------------------+
   x   --  x                                        |                       |
   x \____/x                                        |   CHEF                |
    xxxxxxx                                         |                       |
       x        +-------------+                     |                       |
      xxx       |enc. databag +--------------------->        SERVER         |
     x x x      |  +---+      |         (2)         |                       |
    x  x  x     |  |key|      |                     |                       |
      xxx       +--+---+------+                     |                       |
     x   x   +-----------+         __________________                       |
    x     x  |+---------+|        /                 |                       |
 security    ||MasterKey||       /                  +-----------------------+
 focused     |+---------+|      /
 invididual  +---+-------+     /
                 |            / (3)
                 |(1)        /
                 |          /
   +-------------v---+     /
   |                 <-----                              +-------------------+
   |  KEYMASTER      |                     (4)           | DESTINATION       |
   |        SERVER   +---------------------------------->|            NODE   |
   +-----------------+                                   +-------------------+
```

Say that you need an encrypted databagXYZ for service123. You create a secret
`secretXYZ` and encrypt databagXYZ with it. Now you want `secretXYZ` to be copied
over the nodes A, B and C so that they can decrypt databagXYZ.

The KeyMaster cookbook does this for you.

1. Create a Master Key (preferably one per environment)
`openssl rand -base64 2048 | tr -d '\r\n' > ~/.chef/keymaster.key`
Copy the key manually to the Keymaster server
`scp ~/.chef/keymaster.key /etc/keymaster/keymaster.key`

2. Using Knife, create a Keymaster encrypted databag for secretXYZ in the keymaster
databag, using `keymaster.key`
`knife data bag create --secret-file ~/.chef/keymaster.key keymaster secretXYZ`
The databag must contain a `destination` (chef search that returns the nodes that
need secretXYZ), and a `key` (secretXYZ).
```
id:           service123-databagXYZ-production
destination:  tags:service123 AND roles:python-api-node AND chef_environment:production
key:          kDXL84t+6LRm0Kbqqhef72......
```
The encrypted version will look as follow:
```
destination:  6p4obWgLtbFOWRvfNMN1RwtroTwx/9hB88xsgM5fnP6j1rMeJ/OL2Sgm8ulQ
              3DfMn5b8E7PCoYuEa99u7Plox+JyAUHK/TiE2TGhTt16bQxQFL+ZN4YK+bv8
              TxNZpxhgB43R+7qG+HVYAgmPu9Sr/g==
id:           service123-databagXYZ-production
key:          wKEx1zGdDQfsyterl/2mLLZ68ZNsjks3ZAEo2bIDux0Ux6fh3UDztoNt2NJ1
              xk8bhSkLtQkSNTXBPYWGGDElo1Ttx9xZC1KLUPEW2EzWy4Vb3m/UI+ly53Z9
              3I4RMXDVl+RQl8pWMIig9SbeneUY+C8iojLkx71qmD5ksxrjehgsZPpNct3s
              zmS5Wlxzl7HG6AYs4t084su+Yj0sRG4kkmzh0AKCjLu5nyElRtpcm63G9G5o
              r7114Prrkqj6giDiIHmuPZE7g3cACtJwGOYTJ4yKKu2XvCs7QyYOYYP++ycS
              iMvp4fMv3XN+quWd4wCy/zpjssmLr+YveZzk5E6acCkPdu4Fkumb8JZKgtic
              +OlTNKsA8E8r7i9yDesNi1Xnq5/Kro
```
3. During provisioning, the Keymaster will retrieve the encrypted databag from
chef-server, decrypt the keys and store them locally.
4. The destination of each key is resolved, and keymaster uses `scp` to send the
keys over to the destination nodes.
## Keymaster server directories organization
Inside the keymaster, all keys are stored in the directory defined in
`default[:keymaster][:storage][:path]` (default to `/etc/keymaster/keys/`). The
cookbooks stored the keys unencrypted and uses SSH to copy them over to the
destination nodes.
The Master Key must be stored at the location of `default[:keymaster][:storage][:master_key]`
(defaults to `/etc/keymaster/keymaster.key`). It is stored unencrypted.

### Key re-distribution
The Keymaster does not have a reliable way to determine if a key has changed on
the destination node. Therefore, keys are overwritten on a regular basis (defaults
to 420 minutes - 7 hours - and defined by `default[:keymaster][:distribute][:every]`).

The keymaster keeps history of when a key was distributed to a node, this history
is kept in a node attribute `node[:keymaster][:history]`. Node names are hashes
to prevent information leakage from the history.

## Data Bag Items Decryption
`Keymaster` is stricly a key distribution service. It does not care for what you
encrypt using the keys it distributes.
Nevertheless, `Keymaster` provides a function that can be used in recipes of
other cookbook to decrypt data bag items.

A cookbook that `depends "keymaster"` can use the following code to decrypt
an encrypted databag:
```
  key_location = "#{node['keymaster']['storage']['path']}/cookbooksecure.key"
  dbag_item = {}
  begin
    dbag_item = Keymaster.decrypt_data_bag_item("mydatabag",
                                                "myitem",
                                                key_location)
  rescue IOError
    Chef::Log.info("Decryption failed. Moving on.")
    return true
  end
```
The variable `dbag_item` will receive a hash with the decrypted values, that can
be used in a template or anywhere else in the recipe.

__Note:__ The cookbook must have `depends "keymaster"` in its `metadata.rb` in
order to have access to this `Keymaster` module function.

__Note:__ If the begin/rescue block catches an IOError exception, the processing of
the entire recipe will *NOT* fail.  Only the resources listed *after* the begin/rescue
block will be skipped.  To make the recipe truly atomic and prevent a recipe from
being partially deployed, either put the begin/rescue block at the top of your recipe,
or put all of the resources in the 'begin' portion of the block.

## Vagrant
The vagrant VMs come with a master key by default, such that the keymaster VM
can be provisionned without having to recreate a key.
The key is:
```
+Vrfxe35zyoqYFon7DrMEiudouoJutm8lNoOHSHXsTVCgjcALmwCXkVgR0vyJ+h4mPI0l3wCUC7aiTxcJsPWlSIvvLhcmJv2YVyjnerDZ0Z/y9rdab2yYJLV+gE1LnSZD4LHk/0AsF5nOCZVXwdjFDxq70TZUJcm19t27OUlvPwf3cG9LoAaH5p0SRvomkNCAqRNrn0323pj8vTicTtbosPDEVapuXh8pJwWedSu8Em4/qyG6TJzU3XMB/Q993UBwzNYnzzmGMJj+PuF91bLWqj/HF6rctHvyNex/ASew5chsAebCRDG8f7G8hv7x3n2phDzKyRK8w1/hXywh85IUDLdI/sNlJy1ZR1iOHC/RaUa8MUL1trLlD8TA4JW1ifPKnp4zMSIf880r8Po6kCnxlD8WLCxx1sVK92BtSuysr9qYPJU5ghzDv6+O6mNqUDY+MoSiryiAW7oDKWmQOKM2CekmSO9/VuYTzgbOxY+bfscQIUvONJX46n/4OH80OVcayjcf6C6FjMBEhD7owfA6BbrXSju08IcdH6KTAH4FEGjexXpSTHhf7QAUh77x6CES55CLMvWw17spI+W1lgc/NC2czAPoOtTg+wxWSzNzwPBfdD3jVaZCH+qyfYtkONkaqCvMVbLrUmBmLLNNJodBgQQf99cQYtmr18mU1MWaCM=
```

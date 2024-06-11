# ZeroTier One

Run ZTO from the console as `zerotiner-one -d &`.

Create an account at https://my.zerotier.com/.

Get a network_id and set it as private network.

In the camera console, run `zerotier-cli join <network_id>`.

Successful connection will return `200 join OK`.

Go to https://my.zerotier.com/ and authorize the connected camera by checking the peer.

The configuration is stored in the file /var/lib/zerotier-one.

To leave the network, run `zerotier-cli leave network_id`.

A successful disconnect will return `200 leave OK`.
